import 'dart:convert';

import '../primitive_engine/primitive_models.dart';

class SkillModel {
  final String id;
  final String name;
  final String description;
  final String version;
  final List<PrimitiveStep> steps;
  final DateTime createdAt;
  int useCount;

  SkillModel({
    required this.id,
    required this.name,
    this.description = '',
    this.version = '1.0',
    required this.steps,
    required this.createdAt,
    this.useCount = 0,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'version': version,
    'steps': steps
        .map((s) => {'primitive': s.primitive, 'args': s.args})
        .toList(),
    'createdAt': createdAt.toIso8601String(),
    'useCount': useCount,
  };

  factory SkillModel.fromJson(Map<String, dynamic> json) => SkillModel(
    id: json['id'] as String,
    name: json['name'] as String,
    description: json['description'] as String? ?? '',
    version: json['version'] as String? ?? '1.0',
    steps: (json['steps'] as List<dynamic>? ?? [])
        .map((s) => PrimitiveStep.fromJson(s as Map<String, dynamic>))
        .toList(),
    createdAt: DateTime.parse(json['createdAt'] as String),
    useCount: json['useCount'] as int? ?? 0,
  );

  String toJsonString() => jsonEncode(toJson());
}
