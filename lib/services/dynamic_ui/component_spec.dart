/// A typed, validated dynamic-UI component. Built from a `pcui` JSON block
/// emitted by Gemma or by the render_component primitive.
///
/// Supported types: card, list, key_value, buttons.
class ComponentSpec {
  final String type;
  final String? title;
  final String? body; // card
  final List<ListItem>? items; // list
  final List<KvRow>? rows; // key_value
  final List<UiButton>? buttons; // buttons

  const ComponentSpec({
    required this.type,
    this.title,
    this.body,
    this.items,
    this.rows,
    this.buttons,
  });

  static const supportedTypes = {'card', 'list', 'key_value', 'buttons'};

  /// Builds a spec from decoded JSON. Throws [FormatException] on any
  /// malformed or unknown spec — callers (DynamicUiService) catch this and
  /// degrade to plain text.
  factory ComponentSpec.fromJson(Map<String, dynamic> json) {
    final type = json['type'];
    if (type is! String || !supportedTypes.contains(type)) {
      throw FormatException('Unknown component type: $type');
    }

    switch (type) {
      case 'card':
        return ComponentSpec(
          type: type,
          title: json['title'] as String?,
          body: json['body'] as String?,
        );
      case 'list':
        final raw = json['items'];
        if (raw is! List) {
          throw const FormatException("list requires 'items': array");
        }
        return ComponentSpec(
          type: type,
          title: json['title'] as String?,
          items: raw
              .map((e) => ListItem.fromJson(e as Map<String, dynamic>))
              .toList(),
        );
      case 'key_value':
        final raw = json['rows'];
        if (raw is! List) {
          throw const FormatException("key_value requires 'rows': array");
        }
        return ComponentSpec(
          type: type,
          title: json['title'] as String?,
          rows: raw
              .map((e) => KvRow.fromJson(e as Map<String, dynamic>))
              .toList(),
        );
      case 'buttons':
        final raw = json['buttons'];
        if (raw is! List) {
          throw const FormatException("buttons requires 'buttons': array");
        }
        return ComponentSpec(
          type: type,
          buttons: raw
              .map((e) => UiButton.fromJson(e as Map<String, dynamic>))
              .toList(),
        );
      default:
        throw FormatException('Unknown component type: $type');
    }
  }
}

class ListItem {
  final String title;
  final String? subtitle;
  const ListItem({required this.title, this.subtitle});

  factory ListItem.fromJson(Map<String, dynamic> json) {
    final title = json['title'];
    if (title is! String || title.isEmpty) {
      throw const FormatException("list item requires 'title': String");
    }
    return ListItem(title: title, subtitle: json['subtitle'] as String?);
  }
}

class KvRow {
  final String label;
  final String value;
  const KvRow({required this.label, required this.value});

  factory KvRow.fromJson(Map<String, dynamic> json) {
    final label = json['label'];
    final value = json['value'];
    if (label is! String || value is! String) {
      throw const FormatException("key_value row requires 'label' + 'value'");
    }
    return KvRow(label: label, value: value);
  }
}

class UiButton {
  final String label;
  final String command;
  const UiButton({required this.label, required this.command});

  factory UiButton.fromJson(Map<String, dynamic> json) {
    final label = json['label'];
    final command = json['command'];
    if (label is! String || label.isEmpty || command is! String || command.isEmpty) {
      throw const FormatException("button requires 'label' + 'command'");
    }
    return UiButton(label: label, command: command);
  }
}
