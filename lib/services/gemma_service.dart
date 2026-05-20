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
  Future<void> init() async {
    // Step 1: bootstrap the plugin. Per docs, multiple calls are safe.
    await fg.FlutterGemma.initialize();

    // Step 2: check disk
    final installed = await isInstalled();
    if (!installed) {
      // First-time launch (or fresh install). UI shows the download button;
      // user taps it, install() runs, then load() runs. We do nothing here.
      _state.value = GemmaState.notInstalled;
      return;
    }

    // Model file is on disk but the plugin has no notion of an "active model"
    // until install() runs. install() is idempotent: when the file already
    // exists it skips the download and just calls setActiveModel internally.
    // So we always run install() to register the file with the plugin, then
    // load it into memory.
    //
    // Net cost on a warm boot (file already present): a few hundred ms.
    // The user sees the "Loading Claw…" banner during this whole sequence.
    try {
      _state.value = GemmaState.installing;
      await fg.FlutterGemma.installModel(
        modelType: GemmaConfig.modelType,
        fileType: GemmaConfig.fileType,
      ).fromNetwork(GemmaConfig.modelUrl).install();

      _state.value = GemmaState.installed;
    } catch (e, stack) {
      _lastError = e;
      _state.value = GemmaState.error;
      debugPrint('🐾 GEMMA: init install() failed: $e\n$stack');
      return;
    }

    // Step 3: auto-load in the background. We do NOT await — the UI watches
    // the state ValueListenable and reacts when it flips to ready.
    // ignore: discarded_futures
    load().catchError((e, stack) {
      debugPrint('🐾 GEMMA: auto-load failed: $e\n$stack');
      // State is already GemmaState.error inside load()'s catch block.
    });
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
      debugPrint('🐾 GEMMA: install() called while already installing; skipping');
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
      const systemPreamble =
          'You are Claw, the on-device assistant inside PocketClaw on Android. '
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
