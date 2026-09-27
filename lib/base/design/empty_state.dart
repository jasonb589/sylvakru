import 'package:material_ui/material_ui.dart';
import 'package:sylvakru/base/services/color_manager.dart';

/// Placeholder for a list that has nothing to show.
///
/// An empty list used to render as a blank area, which reads as a list that
/// failed to load rather than one that is genuinely empty. Saying so costs one
/// line and removes the doubt.
///
/// [subtitle] says how the list gets filled, and [action] offers the first
/// step, for the lists the listener can fill themselves.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colour = colorManager.getSpecificTextColor();

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: colour.withValues(alpha: 0.35)),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: colour.withValues(alpha: 0.65),
                ),
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Text(
                  subtitle!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: colour.withValues(alpha: 0.45),
                  ),
                ),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 14), action!],
          ],
        ),
      ),
    );
  }
}
