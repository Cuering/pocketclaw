// Central configuration for everything Gemma-related.
// One file to edit if we ever change the model, backend, or token budget.

import 'package:flutter_gemma/flutter_gemma.dart';

// `abstract class` here is a stylistic trick: combined with the private
// `_()` constructor, it makes this class *impossible to instantiate*. It exists
// purely as a namespace for static constants.
abstract class GemmaConfig {
  GemmaConfig._();

  // Official Hugging Face host. Often slow/unreachable from CN networks.
  static const String hfHost = 'https://huggingface.co';

  // China-friendly mirror (https://hf-mirror.com). Same path layout as HF.
  // Verified 2026-07-26: resolve endpoints return 302 → real file blob.
  static const String hfMirrorHost = 'https://hf-mirror.com';

  // Model paths (relative to host).
  static const String _modelPath =
      '/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm';
  static const String _embeddingModelPath =
      '/litert-community/Gecko-110m-en/resolve/main/Gecko_1024_quant.tflite';
  static const String _embeddingTokenizerPath =
      '/litert-community/Gecko-110m-en/resolve/main/sentencepiece.model';

  /// Primary download URL (mirror first for better CN reachability).
  static const String modelUrl = '$hfMirrorHost$_modelPath';

  /// Fallback if mirror fails (official HF).
  static const String modelUrlFallback = '$hfHost$_modelPath';

  /// Ordered candidates for inference model download.
  static const List<String> modelUrlCandidates = [
    modelUrl,
    modelUrlFallback,
  ];

  static const ModelType modelType = ModelType.gemma4;
  static const ModelFileType fileType = ModelFileType.litertlm;
  static const bool supportImage = true;
  static const int maxNumImages = 1;
  static const int maxTokens = 3072;
  static const PreferredBackend preferredBackend = PreferredBackend.gpu;

  /// Primary embedder URLs (mirror first).
  static const String embeddingModelUrl = '$hfMirrorHost$_embeddingModelPath';
  static const String embeddingTokenizerUrl =
      '$hfMirrorHost$_embeddingTokenizerPath';

  /// Fallback embedder URLs (official HF).
  static const String embeddingModelUrlFallback =
      '$hfHost$_embeddingModelPath';
  static const String embeddingTokenizerUrlFallback =
      '$hfHost$_embeddingTokenizerPath';

  static const List<String> embeddingModelUrlCandidates = [
    embeddingModelUrl,
    embeddingModelUrlFallback,
  ];

  static const List<String> embeddingTokenizerUrlCandidates = [
    embeddingTokenizerUrl,
    embeddingTokenizerUrlFallback,
  ];

  static const int embeddingDimension = 768;

  /// Human-readable sizes for progress UI.
  static const String modelSizeLabel = '~2.4 GB';
  static const String embedderSizeLabel = '~110 MB';
}
