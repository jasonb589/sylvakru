import 'package:material_ui/material_ui.dart';
import 'package:sylvakru/base/services/color_manager.dart';
import 'package:sylvakru/base/services/interaction.dart';

/// One choice in a [MySelectField].
class MySelectOption<T> {
  const MySelectOption({
    required this.value,
    required this.label,
    this.description,
  });

  final T value;
  final String label;
  final String? description;
}

/// A labelled chooser: the label above a rounded field that shows the current
/// value and a chevron, and the list behind it.
///
/// Used where the app knows which values make sense — an interface format, a
/// model, a provider. Asking for free text there means the listener has to
/// spell something the app could simply offer, and a typo looks like a broken
/// feature rather than a wrong setting.
class MySelectField<T> extends StatelessWidget {
  const MySelectField({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.description,
  });

  final String label;
  final T value;
  final List<MySelectOption<T>> options;
  final ValueChanged<T> onChanged;

  /// One line under the field, for what the choice actually does.
  final String? description;

  String get _currentLabel {
    for (final option in options) {
      if (option.value == value) {
        return option.label;
      }
    }
    return options.isEmpty ? '' : options.first.label;
  }

  Future<void> _pick(BuildContext context) async {
    final chosen = await showAnimationDialog<T>(
      context: context,
      child: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final option in options)
              ListTile(
                leading: Icon(
                  option.value == value
                      ? Icons.check_circle_rounded
                      : Icons.circle_outlined,
                ),
                title: Text(option.label),
                subtitle: option.description == null
                    ? null
                    : Text(option.description!),
                onTap: () => Navigator.of(context).pop(option.value),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (chosen != null) {
      onChanged(chosen);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textColor = colorManager.getSpecificTextColor();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 6, bottom: 6),
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: textColor.withAlpha(200)),
            ),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: () => _pick(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                border: Border.all(color: textColor.withAlpha(60)),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _currentLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 15, color: textColor),
                    ),
                  ),
                  Icon(Icons.expand_more_rounded, color: textColor),
                ],
              ),
            ),
          ),
          if (description != null)
            Padding(
              padding: const EdgeInsets.only(left: 6, top: 6),
              child: Text(
                description!,
                style: TextStyle(fontSize: 12, color: textColor.withAlpha(160)),
              ),
            ),
        ],
      ),
    );
  }
}
