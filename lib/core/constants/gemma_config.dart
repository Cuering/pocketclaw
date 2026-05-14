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
  // Max tokens the model can produce in one response. 2048 is a sensible
  // default — long enough for paragraphs, short enough not to hang the UI.
  // We can tune this later per-screen if needed.
  static const int maxTokens = 2048;

  // GPU backend is ~5-7x faster than CPU on phones (per flutter_gemma docs).
  // On devices without GPU support, the plugin auto-falls-back to CPU.
  static const PreferredBackend preferredBackend = PreferredBackend.gpu;
}
