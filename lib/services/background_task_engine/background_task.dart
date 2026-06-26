enum TaskStatus { pending, running, done, failed, cancelled }

class BackgroundTask {
  final String id;
  final String title;
  final String? workflowId;
  TaskStatus status;
  final DateTime createdAt;
  DateTime? scheduledFor;
  DateTime? completedAt;
  String? result;

  BackgroundTask({
    required this.id,
    required this.title,
    this.workflowId,
    this.status = TaskStatus.pending,
    required this.createdAt,
    this.scheduledFor,
    this.completedAt,
    this.result,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'workflowId': workflowId,
        'status': status.name,
        'createdAt': createdAt.toIso8601String(),
        'scheduledFor': scheduledFor?.toIso8601String(),
        'completedAt': completedAt?.toIso8601String(),
        'result': result,
      };

  factory BackgroundTask.fromJson(Map<String, dynamic> json) => BackgroundTask(
        id: json['id'] as String,
        title: json['title'] as String,
        workflowId: json['workflowId'] as String?,
        status: TaskStatus.values.firstWhere(
          (s) => s.name == json['status'],
          orElse: () => TaskStatus.pending,
        ),
        createdAt: DateTime.parse(json['createdAt'] as String),
        scheduledFor: json['scheduledFor'] != null
            ? DateTime.parse(json['scheduledFor'] as String)
            : null,
        completedAt: json['completedAt'] != null
            ? DateTime.parse(json['completedAt'] as String)
            : null,
        result: json['result'] as String?,
      );
}
