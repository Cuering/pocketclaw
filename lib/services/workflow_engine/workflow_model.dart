import 'dart:convert';

class WorkflowModel {
  final String id;
  final String name;
  final String description;
  final String triggerType;
  final List<String> stepSkillIds;
  final DateTime createdAt;
  DateTime? lastRunAt;
  int runCount;

  WorkflowModel({
    required this.id,
    required this.name,
    this.description = '',
    this.triggerType = 'manual',
    required this.stepSkillIds,
    required this.createdAt,
    this.lastRunAt,
    this.runCount = 0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'triggerType': triggerType,
        'stepSkillIds': stepSkillIds,
        'createdAt': createdAt.toIso8601String(),
        'lastRunAt': lastRunAt?.toIso8601String(),
        'runCount': runCount,
      };

  factory WorkflowModel.fromJson(Map<String, dynamic> json) => WorkflowModel(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String? ?? '',
        triggerType: json['triggerType'] as String? ?? 'manual',
        stepSkillIds: List<String>.from(json['stepSkillIds'] as List),
        createdAt: DateTime.parse(json['createdAt'] as String),
        lastRunAt: json['lastRunAt'] != null
            ? DateTime.parse(json['lastRunAt'] as String)
            : null,
        runCount: json['runCount'] as int? ?? 0,
      );

  String toJsonString() => jsonEncode(toJson());
}
