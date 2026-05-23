// lib/services/gemma_service.dart
//
// Owns the Gemma 4 model's full lifecycle: install, load, generate, dispose.
// Singleton — only one instance app-wide. All Gemma access goes through here.

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart' as fg;

import '../core/constants/gemma_config.dart';
import '../core/errors/app_exception.dart';

// `as fg` aliases the import — wherever we'd write `Message` (from flutter_gemma)
// we write `fg.Message` instead. This prevents a name clash with our own
// `Message` class in lib/models/message.dart. Pattern: alias third-party
// imports when their type names collide with ours.

// All possible states the model can be in. The UI watches the current state
// and renders accordingly.
enum GemmaState {
  notInstalled, // model file isn't on the device yet
  installing, // download in progress (watch `downloadProgress` too)
  installed, // file on disk, but model not loaded into memory
  loading, // loading file → native memory; takes seconds
  ready, // model loaded, ready to chat
  generating, // currently producing a response
  error, // something broke; check `lastError`
}

/// Embedder lifecycle. Independent of GemmaState because the embedder
/// is a separate model (Gecko 110M tflite + sentencepiece tokenizer).
/// The chat model (Gemma 4 E2B) can be ready while the embedder is
/// still downloading, and vice versa.
enum EmbedderState {
  notInstalled,
  installing,
  installed, // files on disk, plugin's active embedder spec set
  error,
}

class GemmaService {
  // ── Singleton plumbing ─────────────────────────────────────────────────

  // Private named constructor — only this file can call it.
  // The leading underscore makes it library-private.
  GemmaService._();

  // The one instance, eagerly created. `static final` = class-level + set once.
  // First time anyone reads `GemmaService.instance`, this initializer runs;
  // every subsequent read returns the same object. Standard Dart singleton.
  static final GemmaService instance = GemmaService._();

  // ── Reactive state ─────────────────────────────────────────────────────

  // `ValueNotifier<T>` holds a `T` and notifies listeners when `.value` changes.
  // UI watches via `ValueListenableBuilder` (or `.addListener` for non-widgets).
  //
  // We expose them as `ValueListenable<T>` (read-only view) so external code
  // can listen but can't mutate. We mutate from inside this class only.
  final ValueNotifier<GemmaState> _state = ValueNotifier(
    GemmaState.notInstalled,
  );
  ValueListenable<GemmaState> get state => _state;

  // Download progress 0–100. Only meaningful while state == installing.
  final ValueNotifier<int> _downloadProgress = ValueNotifier(0);
  ValueListenable<int> get downloadProgress => _downloadProgress;

  // Last error, for the UI to surface. `Object?` because errors can be anything.
  Object? _lastError;
  Object? get lastError => _lastError;

  // ── Private model handle ───────────────────────────────────────────────

  // Whether we've called FlutterGemma.installModel().install() this session.
  // The plugin's "active model" pointer is process-scoped and only set by
  // calling install() — even if the file is already on disk. Without this
  // flag, ensureInstalled() short-circuits on the "file exists" state and
  // load() fails with "No active inference model set". Bug reproduced
  // 2026-05-21 in the onboarding flow.
  bool _pluginInstallDone = false;

  // Same logic for the embedder. The plugin tracks an "active embedding
  // model" separately from the inference model; both need install() to
  // register, even when files are already on disk.
  bool _embedderInstallDone = false;

  // Cached embedder instance (loaded once, reused). Lazily created in
  // getEmbedder() so we don't pay the cost during onboarding.
  fg.EmbeddingModel? _embedder;

  // Public state for the embedder. Watch this from RAG-related UI.
  final ValueNotifier<EmbedderState> _embedderState = ValueNotifier(
    EmbedderState.notInstalled,
  );
  ValueListenable<EmbedderState> get embedderState => _embedderState;

  // Download progress for the embedder install (0..100). Independent of
  // the main download progress so onboarding can show both if desired.
  final ValueNotifier<int> _embedderDownloadProgress = ValueNotifier(0);
  ValueListenable<int> get embedderDownloadProgress =>
      _embedderDownloadProgress;

  // The loaded model instance from flutter_gemma. Null until loaded.
  // `_` prefix = file-private. `InferenceModel?` because it's nullable
  // (null when not loaded).
  fg.InferenceModel? _model;

  // ── Public API ─────────────────────────────────────────────────────────

  // Check whether the model file is already on the device.
  // Returns true if installed (from a previous run), false otherwise.
  /// One-time bootstrap. Call once from main() before runApp().
  /// Idempotent: safe to call multiple times.
  ///
  /// Behaviour:
  ///   1. Calls FlutterGemma.initialize() to set up the plugin internals.
  ///   2. Checks if the model file is already on disk.
  ///   3. If installed, auto-loads it into memory in the background.
  ///      State transitions installed → loading → ready with no UI taps.
  ///   4. If not installed, leaves state at notInstalled. UI shows the
  ///      download button.
  ///
  /// Auto-load errors surface via the state ValueListenable (transitions
  /// to error). Caller does not need to await successful load — UI watches
  /// state and reacts when it flips to ready.
  /// One-time plugin bootstrap. Idempotent: safe to call multiple times.
  ///
  /// After this returns, [state] is one of:
  ///   - [GemmaState.notInstalled] — first-time user, must run [ensureInstalled]
  ///   - [GemmaState.installed]    — file on disk but not loaded yet
  ///                                  (onboarding can fire [ensureLoaded] in
  ///                                  background; chat screen does this for
  ///                                  returning users)
  ///
  /// Does NOT auto-install or auto-load. Callers decide when those happen so
  /// onboarding can stage them deliberately. For returning users, see
  /// [resumeIfInstalled] below.
  Future<void> init() async {
    await fg.FlutterGemma.initialize();
    final installed = await isInstalled();
    _state.value = installed ? GemmaState.installed : GemmaState.notInstalled;
  }

  /// Returning-user convenience: if the file is on disk, kick off install()
  /// (idempotent — registers active model) and a background load(). Used by
  /// main() after init() so the chat screen lights up without extra taps.
  /// First-time users skip this entirely and go through onboarding.
  Future<void> resumeIfInstalled() async {
    if (_state.value != GemmaState.installed) return;
    try {
      await ensureInstalled();
    } catch (e, stack) {
      debugPrint('🐾 GEMMA: resume install() failed: $e\n$stack');
      return;
    }
    // ignore: discarded_futures
    ensureLoaded().catchError((e, stack) {
      debugPrint('🐾 GEMMA: resume load() failed: $e\n$stack');
    });

    // The embedder lives a separate lifecycle but has the same "active
    // model pointer is process-scoped" trap: even when the file is on
    // disk, the plugin needs installEmbedder() called once per session
    // to register the active spec. Without this call, RAG silently
    // fails on returning users with: "Document understanding isn't
    // ready yet." Bug observed 2026-05-22 00:30.
    //
    // Fire-and-forget — chat doesn't block on it, RAG just stays
    // disabled until it completes.
    // ignore: discarded_futures
    installEmbedder().catchError((e, stack) {
      debugPrint('🐾 GEMMA: resume installEmbedder() failed: $e\n$stack');
    });
  }

  /// Idempotent install. Downloads the model if not present, then calls
  /// the plugin's setActiveModel internally. Cheap when the file already
  /// exists (~hundreds of ms to register the spec).
  ///
  /// Onboarding's "Download" button calls this and awaits completion
  /// (showing progress). After it returns, state is [GemmaState.installed].
  Future<void> ensureInstalled() async {
    // If we've already registered the plugin's active model this session,
    // short-circuit. Otherwise we MUST call installModel() — even if the
    // file is on disk — because the active-model pointer is process-scoped
    // and not implied by the file's existence.
    if (_pluginInstallDone) return;
    if (_state.value == GemmaState.installing) return;
    if (_state.value == GemmaState.loading ||
        _state.value == GemmaState.ready ||
        _state.value == GemmaState.generating) {
      // Some other path has progressed past install (e.g. via resumeIfInstalled).
      // Treat plugin install as done.
      _pluginInstallDone = true;
      return;
    }
    try {
      _state.value = GemmaState.installing;
      _downloadProgress.value = 0;
      await fg.FlutterGemma.installModel(
        modelType: GemmaConfig.modelType,
        fileType: GemmaConfig.fileType,
      ).fromNetwork(GemmaConfig.modelUrl).withProgress((p) {
        _downloadProgress.value = p;
      }).install();
      _pluginInstallDone = true;
      _state.value = GemmaState.installed;
    } catch (e, stack) {
      _lastError = e;
      _state.value = GemmaState.error;
      debugPrint('🐾 GEMMA: ensureInstalled() failed: $e\n$stack');
      throw GemmaException('Failed to install Gemma model', e);
    }
  }

  /// Idempotent load. Pulls the active model into memory.
  /// Existing guards in load() prevent double-allocation.
  Future<void> ensureLoaded() async {
    if (_state.value == GemmaState.ready ||
        _state.value == GemmaState.generating ||
        _state.value == GemmaState.loading) {
      return;
    }
    if (_state.value != GemmaState.installed) {
      throw const GemmaException(
        'Model not installed. Call ensureInstalled() first.',
      );
    }
    await load();
  }

  /// Install the embedder (Gecko 110M + sentencepiece tokenizer).
  ///
  /// Idempotent — safe to call multiple times. On a warm start where the
  /// files are already on disk, the plugin skips the download and just
  /// registers the active embedder spec.
  ///
  /// Onboarding calls this AFTER the main inference model install so the
  /// user sees two progress bars in sequence rather than two overlapping
  /// downloads. (Same SmartDownloader queue under the hood — parallel
  /// downloads would only fight for bandwidth, not save time.)
  ///
  /// Throws [GemmaException] on failure; transitions [embedderState] to
  /// error.
  Future<void> installEmbedder() async {
    if (_embedderInstallDone) return;
    if (_embedderState.value == EmbedderState.installing) return;
    if (_embedderState.value == EmbedderState.installed) {
      _embedderInstallDone = true;
      return;
    }
    try {
      _embedderState.value = EmbedderState.installing;
      _embedderDownloadProgress.value = 0;

      await fg.FlutterGemma.installEmbedder()
          .modelFromNetwork(GemmaConfig.embeddingModelUrl)
          .tokenizerFromNetwork(GemmaConfig.embeddingTokenizerUrl)
          .withModelProgress((p) {
            _embedderDownloadProgress.value = p;
          })
          .install();

      _embedderInstallDone = true;
      _embedderState.value = EmbedderState.installed;
      debugPrint('🐾 GEMMA: embedder installed and active');
    } catch (e, stack) {
      _embedderState.value = EmbedderState.error;
      debugPrint('🐾 GEMMA: installEmbedder() failed: $e\n$stack');
      throw GemmaException('Failed to install Gecko embedder', e);
    }
  }

  /// Lazily fetch (and cache) the active embedder instance. Throws if the
  /// embedder hasn't been installed yet — call [installEmbedder] first.
  ///
  /// The first call constructs the [EmbeddingModel] from the active spec,
  /// which is cheap (~tens of ms — no GPU allocation, unlike inference
  /// model load). Subsequent calls return the cached instance.
  Future<fg.EmbeddingModel> getEmbedder() async {
    final cached = _embedder;
    if (cached != null) return cached;
    if (_embedderState.value != EmbedderState.installed) {
      throw const GemmaException(
        'Embedder not installed. Call installEmbedder() first.',
      );
    }
    try {
      final model = await fg.FlutterGemma.getActiveEmbedder();
      _embedder = model;
      return model;
    } catch (e, stack) {
      debugPrint('🐾 GEMMA: getEmbedder() failed: $e\n$stack');
      throw GemmaException('Failed to load embedder', e);
    }
  }

  Future<bool> isInstalled() async {
    try {
      // flutter_gemma stores models by filename derived from the URL.
      // We pass the same URL we'd use to install.
      // The plugin extracts the filename and checks its on-disk path.
      return await fg.FlutterGemma.isModelInstalled(
        _filenameFromUrl(GemmaConfig.modelUrl),
      );
    } catch (e) {
      // Don't crash if the check itself fails — treat as "not installed"
      // and the caller can attempt install.
      return false;
    }
  }

  // Install (download) the model. Idempotent: safe to call even if already
  // installed; the plugin checks internally and skips the download.
  //
  // Throws GemmaException on failure. State transitions:
  //   notInstalled → installing (progress updates) → installed
  //                        ↓ on error
  //                       error
  // Install (download) the model. Idempotent: safe to call even if already
  // installed; the plugin checks internally and skips the download.
  //
  // Throws GemmaException on failure. State transitions:
  //   notInstalled → installing (progress updates) → installed
  //                        ↓ on error
  //                       error
  Future<void> install() async {
    if (_state.value == GemmaState.installing) {
      debugPrint(
        '🐾 GEMMA: install() called while already installing; skipping',
      );
      return;
    }
    try {
      _state.value = GemmaState.installing;
      _downloadProgress.value = 0;

      await fg.FlutterGemma.installModel(
        modelType: GemmaConfig.modelType,
        fileType: GemmaConfig.fileType,
      ).fromNetwork(GemmaConfig.modelUrl).withProgress((progress) {
        // `withProgress` callback fires repeatedly during download.
        // `progress` is an int 0–100 per the modern API contract.
        _downloadProgress.value = progress;
      }).install();

      _pluginInstallDone = true;
      _state.value = GemmaState.installed;
    } catch (e) {
      _lastError = e;
      _state.value = GemmaState.error;
      // Re-throw as our typed exception so callers can handle it cleanly.
      throw GemmaException('Failed to install Gemma model', e);
    }
  }

  // Load the installed model into memory. Must be called after install().
  // After this returns, state == ready and you can call generate().
  Future<void> load() async {
    // Idempotency guard: if a load is already in progress, or the model
    // is already ready, don't kick off a second load. Two concurrent
    // load() calls allocate two copies of the ~1.5 GB model weights and
    // OOM the phone. Crash reproduced 2026-05-20.
    if (_state.value == GemmaState.loading) {
      debugPrint('🐾 GEMMA: load() called while already loading; skipping');
      return;
    }
    if (_state.value == GemmaState.ready ||
        _state.value == GemmaState.generating) {
      debugPrint('🐾 GEMMA: load() called but model already ready; skipping');
      return;
    }

    try {
      _state.value = GemmaState.loading;

      _model = await fg.FlutterGemma.getActiveModel(
        maxTokens: GemmaConfig.maxTokens,
        preferredBackend: GemmaConfig.preferredBackend,
        // Enable Gemma 4 vision. Without these, image bytes from
        // Message.withImage(...) are silently dropped — model receives
        // text-only prompt and asks "please provide the image."
        supportImage: GemmaConfig.supportImage,
        maxNumImages: GemmaConfig.maxNumImages,
      );

      _state.value = GemmaState.ready;
    } catch (e) {
      _lastError = e;
      _state.value = GemmaState.error;
      throw GemmaException('Failed to load Gemma model', e);
    }
  }

  // Generate a single text response (non-streaming, simplest possible API).
  // Throws if the model isn't loaded. We'll add streaming + image input
  // in a later iteration once this works end-to-end.
  Future<String> generate(
    String prompt, {
    // Optional image attachment. When supplied, we send a multimodal query
    // (image + text) and Gemma's vision encoder processes the image first.
    // Pass null (default) for text-only prompts — keeps existing call sites
    // working without changes.
    Uint8List? imageBytes,
    void Function(String chunk)? onToken,
    // Optional display name from UserPrefs. When supplied, the system
    // preamble tells Gemma the user's name so "what's my name" works.
    String? userName,
  }) async {
    final model = _model;
    if (model == null) {
      throw const GemmaException('Model not loaded. Call load() first.');
    }

    try {
      _state.value = GemmaState.generating;
      // Create a fresh chat session for this prompt.
      // (For multi-turn we'd keep one chat and add chunks; we'll get to that.)
      final chat = await model.createChat();
      // Name goes at the front, before everything else. Small models
      // (Gemma 4 E2B is 2B effective) reliably pick up facts at the
      // start of the prompt but flake on instructions buried mid-text.
      // Just state the fact; don't coach the model on how to use it.
      final namePart = (userName != null && userName.trim().isNotEmpty)
          ? "The name of the user is ${userName.trim()}.\n\n"
          : '';
      final systemPreamble =
          '${namePart}You are Claw, the on-device assistant inside PocketClaw on Android. '
          'You run locally and offline. '
          'Match your answer length to the question: brief for simple questions, '
          'detailed when the user clearly wants depth, code when code is asked for. '
          'Prefer plain answers over preambles; never restate the question. '
          'If unsure, say so briefly rather than padding.';
      final fullPrompt = '$systemPreamble\n\nUser: $prompt';
      if (imageBytes != null) {
        await chat.addQueryChunk(
          fg.Message.withImage(
            text: fullPrompt,
            imageBytes: imageBytes,
            isUser: true,
          ),
        );
      } else {
        await chat.addQueryChunk(
          fg.Message.text(text: fullPrompt, isUser: true),
        );
      }
      // Buffer to assemble the full response. We append to this as chunks
      // arrive, and return it at the end so callers that want the whole
      // string still get it.
      final buffer = StringBuffer();
      // `await for` reads a Stream one element at a time, synchronously
      // (with respect to this function), suspending until the next element
      // arrives. The body runs once per ModelResponse the model emits.
      await for (final response in chat.generateChatResponseAsync()) {
        // Same type-narrowing pattern as before, but now per-chunk.
        if (response is fg.TextResponse) {
          buffer.write(response.token);
          onToken?.call(
            response.token,
          ); // null-safe call — `?.` short-circuits if onToken is null
        } else if (response is fg.ThinkingResponse) {
          // Thinking mode chunks — we're not enabling thinking mode for v1,
          // but handle defensively. We DON'T send these to onToken because
          // they're the model's internal reasoning, not the user-facing reply.
          buffer.write(response.content);
        } else {
          // FunctionCallResponse or any unexpected type — we throw on unknown
          // so we don't return garbled content. v1 isn't using tools.
          throw GemmaException(
            'Unexpected response type during streaming: ${response.runtimeType}',
          );
        }
      }
      await chat.close();

      _state.value = GemmaState.ready;
      return buffer.toString();
    } catch (e) {
      _lastError = e;
      _state.value = GemmaState.error;
      throw GemmaException('Failed to generate response', e);
    }
  }

  // Dispose: release the model's native memory. Call when shutting down
  // or when backgrounding for a long time. After this, state == installed
  // (file is still on disk) and load() can be called again.
  Future<void> dispose() async {
    try {
      await _model?.close(); // `?.` = no-op if _model is null
      _model = null;
      _state.value = GemmaState.installed;
    } catch (e) {
      // Disposal errors are rarely actionable — log and move on.
      _lastError = e;
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────

  // Pull the filename out of a URL. flutter_gemma's isModelInstalled() wants
  // just the filename (it knows where to look on disk).
  // e.g. ".../resolve/main/gemma-4-E2B-it.litertlm" → "gemma-4-E2B-it.litertlm"
  String _filenameFromUrl(String url) => url.split('/').last;
}
