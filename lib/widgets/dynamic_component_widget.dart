import 'package:flutter/material.dart';

import '../core/pocketclaw_theme.dart';
import '../services/dynamic_ui/component_spec.dart';

/// Renders a validated [ComponentSpec] using neobrutalism theme tokens.
/// Button taps forward their command string via [onCommand].
class DynamicComponentWidget extends StatelessWidget {
  const DynamicComponentWidget({super.key, required this.spec, this.onCommand});

  final ComponentSpec spec;
  final void Function(String command)? onCommand;

  @override
  Widget build(BuildContext context) {
    return switch (spec.type) {
      'card' => _card(context),
      'list' => _list(context),
      'key_value' => _keyValue(context),
      'buttons' => _buttons(context),
      _ => const SizedBox.shrink(),
    };
  }

  Widget _panel(BuildContext context, Widget child) => Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: PocketClawTheme.panel(
          color: PocketClawTheme.bg,
          border: PocketClawTheme.cyan,
          radius: 8,
        ),
        child: child,
      );

  Widget _card(BuildContext context) {
    final theme = Theme.of(context);
    return _panel(
      context,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (spec.title != null && spec.title!.isNotEmpty)
            Text(spec.title!, style: theme.textTheme.titleMedium),
          if (spec.title != null && spec.body != null)
            const SizedBox(height: 6),
          if (spec.body != null && spec.body!.isNotEmpty)
            Text(spec.body!, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }

  Widget _list(BuildContext context) {
    final theme = Theme.of(context);
    final items = spec.items ?? const [];
    return _panel(
      context,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (spec.title != null && spec.title!.isNotEmpty) ...[
            Text(spec.title!, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
          ],
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const Divider(height: 14, color: PocketClawTheme.bg3),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(items[i].title, style: theme.textTheme.bodyMedium),
                if (items[i].subtitle != null && items[i].subtitle!.isNotEmpty)
                  Text(
                    items[i].subtitle!,
                    style: theme.textTheme.labelSmall,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _keyValue(BuildContext context) {
    final theme = Theme.of(context);
    final rows = spec.rows ?? const [];
    return _panel(
      context,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (spec.title != null && spec.title!.isNotEmpty) ...[
            Text(spec.title!, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
          ],
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(r.label, style: theme.textTheme.labelSmall),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: Text(r.value, style: theme.textTheme.bodyMedium),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buttons(BuildContext context) {
    final buttons = spec.buttons ?? const [];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final b in buttons)
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: PocketClawTheme.cyan, width: 2),
                foregroundColor: PocketClawTheme.cyan,
              ),
              onPressed: onCommand == null ? null : () => onCommand!(b.command),
              child: Text(b.label),
            ),
        ],
      ),
    );
  }
}
