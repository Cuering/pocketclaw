// Central configuration for everything Gemma-related.
// One file to edit if we ever change the model, backend, or token budget.

import 'package:flutter_gemma/flutter_gemma.dart';

// `abstract class` here is a stylistic trick: combined with the private
// `_()` constructor, it makes this class *impossible to instantiate*. It exists
// purely as a namespace for static constants. (We could also use a normal
// class — `abstract` just signals intent more loudly: "don't try to new this.")
abstract class GemmaConfig {
  // Private named constructor with no body. The leading underscore makes it
  // library-private, so nothing outside this file can call it. Combined with
  // the lack of any public constructor, the class can't be instantiated at all.
  GemmaConfig._();

  // The official Gemma 4 E2B model URL on Hugging Face.
  // `.litertlm` is the LiteRT-LM format — required for Gemma 4 on Android.
  // `litert-community/...` is a PUBLIC repo, no HF token needed.
  //
  // `static const`: belongs to the class (no instance needed) AND known at
  // compile time. The compiler can inline this string everywhere it's used.
  static const String modelUrl =
      'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm';

  // The ModelType enum tells flutter_gemma which chat-template path to use.
  // For Gemma 4 we MUST use `gemma4` (not `gemmaIt`) — Gemma 4 has its own
  // tool-call tokens and chat template. Using the wrong enum = broken outputs.
  static const ModelType modelType = ModelType.gemma4;

  // ModelFileType: which file FORMAT — drives engine selection.
  // CRITICAL: defaults to ModelFileType.task in flutter_gemma, but our model
  // is .litertlm. Without this, the plugin routes load() to the Kotlin
  // EngineFactory (for .task files), which throws because it knows it's the
  // wrong engine for .litertlm files. With this, load() correctly routes to
  // the Dart FFI LiteRT-LM client.

  static const ModelFileType fileType = ModelFileType.litertlm;
  // Enable Gemma 4's vision modality at the engine level. Without this,
  // flutter_gemma silently strips image bytes from Message.withImage(...)
  // calls — only the text portion reaches the model, which then asks
  // "please provide the image." Same class of bug as the Day-2 fileType
  // default. Always-on for PocketClaw since multimodal is core to v1.
  static const bool supportImage = true;
  // Max number of images per turn. We send at most one per generate() call.
  // Higher = more KV cache memory reserved up front.
  static const int maxNumImages = 1;
  // Max tokens the model can produce in one response. 2048 is a sensible
  // default — long enough for paragraphs, short enough not to hang the UI.
  // We can tune this later per-screen if needed.
  static const int maxTokens = 2048;

  // GPU backend is ~5-7x faster than CPU on phones (per flutter_gemma docs).
  // On devices without GPU support, the plugin auto-falls-back to CPU.
  static const PreferredBackend preferredBackend = PreferredBackend.gpu;

  // ── Embedding model (Gecko 110M EN, quantized) ────────────────────────
  //
  // For RAG (document Q&A). Lives in the same litert-community repo as
  // our Gemma 4 mirror — public, no HF token required (verified
  // 2026-05-21). The plugin ships an EmbeddingModel enum but its
  // gecko110M URL is stale (404); we bypass it and pass the URL directly.
  //
  // 110 MB on top of Gemma 4 E2B's 1.5 GB = ~7% extra download. Worth it
  // for on-device document retrieval.
  static const String embeddingModelUrl =
      'https://huggingface.co/litert-community/Gecko-110m-en/resolve/main/Gecko_1024_quant.tflite';

  static const String embeddingTokenizerUrl =
      'https://huggingface.co/litert-community/Gecko-110m-en/resolve/main/sentencepiece.model';

  // Embedding output dimension. Gecko 110M produces 768-dim vectors;
  // we pass this to the vector store on first init (it auto-detects,
  // but having it explicit makes debugging clearer).
  static const int embeddingDimension = 768;
}
