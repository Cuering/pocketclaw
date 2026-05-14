import 'dart:typed_data';

// lib/models/message.dart
//
// PocketClaw's own message model — represents one chat bubble in the UI.
// Distinct from flutter_gemma's Message (which is a transport object).
// Reason for two classes: theirs can change with their package updates;
// ours stays under our control.

// Who sent a message. `enum` is a fixed set of named values — type-safe and
// exhaustive in switches.
enum MessageSender { user, claw }

// Lifecycle of a message in the UI.
//   sending — user pressed send, awaiting model reply (show spinner)
//   sent    — successfully delivered (model returned, or user's own message)
//   failed  — something broke (show retry button)
enum MessageStatus { sending, sent, failed }

// `@immutable` annotation would require `package:meta`; we'll skip it for now.
// Convention: all fields `final`, no setters. New instance via `copyWith`.
class Message {
  // Unique identifier. We use a String (typically a timestamp-based ID we
  // generate when creating the message) instead of int, so it's stable across
  // serialization without collision risks.
  final String id;

  final MessageSender sender;
  final String text;

  // When the message was created. `DateTime` is Dart's standard datetime type.
  final DateTime timestamp;

  // Optional image attachment (raw bytes). `Uint8List?` because:
  //   - `Uint8List` is the standard type for raw binary in Dart
  //   - `?` makes it nullable; most messages won't have an image
  // Note: we DON'T import dart:typed_data here — we use the global typedef.
  // (If your linter complains, add `import 'dart:typed_data';`.)
  final Uint8List? imageBytes;

  final MessageStatus status;

  // Constructor. `const` so messages CAN be const-allocated where possible
  // (only works if all fields are const-compatible at the call site).
  // `required` on `id`, `sender`, `text`, `timestamp` — they're mandatory.
  // `imageBytes` defaults to null; `status` defaults to `sent`.
  const Message({
    required this.id,
    required this.sender,
    required this.text,
    required this.timestamp,
    this.imageBytes,
    this.status = MessageStatus.sent,
  });

  // `copyWith`: returns a NEW instance with some fields changed.
  // Standard pattern for working with immutable data.
  //
  // Example use: `final updated = msg.copyWith(status: MessageStatus.failed);`
  //
  // All params nullable + use `??` to fall back to current value. The user
  // passes only what they want to change.
  //
  // Subtle gotcha: this pattern can't represent "set this field to null"
  // for nullable fields. We don't need that today; if we ever do, we'll
  // switch to a sentinel-value pattern. Don't worry about it now.
  Message copyWith({
    String? id,
    MessageSender? sender,
    String? text,
    DateTime? timestamp,
    Uint8List? imageBytes,
    MessageStatus? status,
  }) {
    return Message(
      id: id ?? this.id,
      sender: sender ?? this.sender,
      text: text ?? this.text,
      timestamp: timestamp ?? this.timestamp,
      imageBytes: imageBytes ?? this.imageBytes,
      status: status ?? this.status,
    );
  }

  // toJson: convert to a Map for storage (Hive, SQLite, SharedPreferences,
  // or sending across isolates). We don't serialize imageBytes here — too
  // big and binary; we'll store images separately by reference if needed.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sender': sender.name, // enum.name → "user" / "claw"
      'text': text,
      'timestamp': timestamp.toIso8601String(),
      'status': status.name,
    };
  }

  // fromJson: factory constructor that builds a Message from a Map.
  // `factory` (vs regular constructor) lets us run logic before returning
  // an instance — here, parsing enums and dates from their string forms.
  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'] as String,
      sender: MessageSender.values.byName(json['sender'] as String),
      text: json['text'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      status: MessageStatus.values.byName(json['status'] as String),
    );
  }

  // == and hashCode: required so Lists, Sets, Maps treat messages with the
  // same ID as equal. Without this, `list.contains(msg)` won't work properly
  // and Flutter's `Key`-based reconciliation can mis-render the chat.
  //
  // We compare by ID only (the rest can change via copyWith and still be
  // "the same message"). Standard pattern for entities with stable IDs.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Message && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
