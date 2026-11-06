import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/extensions/l10n.dart';

/// How a [DialogCancel] looks: a text button, one in the muted text colour, or
/// one with an outline.
enum DialogCancelStyle { text, mutedText, outlined }

/// The Cancel button of a dialog. [onPressed] defaults to closing the dialog.
class DialogCancel extends StatelessWidget {
  const DialogCancel({
    super.key,
    this.onPressed,
    this.style = DialogCancelStyle.text,
  });

  final VoidCallback? onPressed;
  final DialogCancelStyle style;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final onPressed = this.onPressed ?? () => Navigator.pop(context);
    final label = context.l10n!.cancel;
    return switch (style) {
      DialogCancelStyle.text => TextButton(
        onPressed: onPressed,
        child: Text(label),
      ),
      DialogCancelStyle.mutedText => TextButton(
        onPressed: onPressed,
        child: Text(
          label,
          style: TextStyle(color: colorScheme.onSurfaceVariant),
        ),
      ),
      DialogCancelStyle.outlined => OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: colorScheme.outline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(label),
      ),
    };
  }
}

/// The round icon at the top of a dialog: [icon] on a 56 circle, in the primary
/// colours (a 32 icon) or, with [secondary], the secondary ones (a 28 icon).
class DialogIconHeader extends StatelessWidget {
  const DialogIconHeader({
    super.key,
    required this.icon,
    this.secondary = false,
  });

  final IconData icon;
  final bool secondary;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: secondary
            ? colorScheme.secondaryContainer
            : colorScheme.primaryContainer,
        shape: BoxShape.circle,
      ),
      child: Icon(
        icon,
        color: secondary ? colorScheme.secondary : colorScheme.primary,
        size: secondary ? 28 : 32,
      ),
    );
  }
}

/// A dialog with one name field that starts as [initialName], headed by [icon]
/// and [title], with Cancel and a confirm button ([confirmIcon], [confirmLabel]).
/// Confirming closes the dialog first, then calls [onSubmit] with the dialog's
/// context and the trimmed name, which may be empty: refusing that is up to
/// [onSubmit].
Future<void> showNameDialog(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String label,
  required String initialName,
  required IconData confirmIcon,
  required String confirmLabel,
  required void Function(BuildContext dialogContext, String name) onSubmit,
}) {
  var name = initialName;
  return showDialog<void>(
    context: context,
    builder: (context) {
      final colorScheme = Theme.of(context).colorScheme;
      return AlertDialog(
        icon: Icon(icon, color: colorScheme.primary, size: 32),
        title: Text(
          title,
          style: TextStyle(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: TextFormField(
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: Icon(
              FluentIcons.text_field_20_regular,
              color: colorScheme.onSurfaceVariant,
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: colorScheme.surfaceContainerLow,
          ),
          initialValue: name,
          autofocus: true,
          onChanged: (value) => name = value,
        ),
        actions: [
          const DialogCancel(style: DialogCancelStyle.mutedText),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(context);
              onSubmit(context, name.trim());
            },
            icon: Icon(confirmIcon),
            label: Text(confirmLabel),
          ),
        ],
      );
    },
  );
}
