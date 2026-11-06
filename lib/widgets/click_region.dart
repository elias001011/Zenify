import 'package:material_ui/material_ui.dart';

/// The hand cursor over [child], for a tappable area that is not a button
/// (a [GestureDetector]). Flutter's own buttons keep the arrow on desktop, so
/// the theme gives them the hand; this does the same for what it cannot reach.
class ClickRegion extends StatelessWidget {
  const ClickRegion({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      MouseRegion(cursor: SystemMouseCursors.click, child: child);
}
