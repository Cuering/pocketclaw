import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'component_spec.dart';

/// Parses `pcui` JSON blocks into [ComponentSpec]s. Stateless and pure —
/// a singleton only for pattern consistency.
class DynamicUiService {
  DynamicUiService._();
  static final DynamicUiService instance = DynamicUiService._();

  Future<void> init() async {}
  Future<void> dispose() async {}

  /// Matches ```pcui … ``` fenced blocks (case-insensitive tag).
  /// Group 1 is the inner JSON.
  static final RegExp _blockPattern =
      RegExp(r'```pcui[ \t]*\n([\s\S]*?)```', caseSensitive: false);

  /// Returns null on any decode/validation failure — never throws.
  ComponentSpec? parse(String json) {
    try {
      final decoded = jsonDecode(json);
      if (decoded is! Map<String, dynamic>) return null;
      return ComponentSpec.fromJson(decoded);
    } catch (e) {
      debugPrint('🐾 DYNAMIC UI: parse failed: $e');
      return null;
    }
  }

  /// Extracts the inner JSON of every pcui fenced block, in order.
  List<String> extractBlocks(String text) {
    return _blockPattern
        .allMatches(text)
        .map((m) => m.group(1) ?? '')
        .toList();
  }
}
