import 'package:material_ui/material_ui.dart';
import 'package:sylvakru/base/audio_handler.dart';
import 'package:sylvakru/base/services/color_manager.dart';
import 'package:sylvakru/l10n/generated/app_localizations.dart';
import 'package:sylvakru/base/services/keyboard.dart';

class MySearchField extends StatefulWidget {
  final String hintText;

  final TextEditingController textController;

  final void Function()? onSearchTextChanged;

  final void Function()? onAdvancedSearch;

  final bool useCurrentSong;

  final bool hasAdvancedSearch;
  const MySearchField({
    super.key,
    required this.hintText,
    required this.textController,
    this.onSearchTextChanged,
    this.onAdvancedSearch,
    this.hasAdvancedSearch = false,
    this.useCurrentSong = true,
  });

  @override
  State<StatefulWidget> createState() => _MySearchFieldState();
}

class _MySearchFieldState extends State<MySearchField> {
  final focusNode = FocusNode();
  final isSearchNotifier = ValueNotifier(false);

  @override
  void initState() {
    focusNode.addListener(() {
      isTyping = focusNode.hasFocus;
    });
    super.initState();
  }

  @override
  void dispose() {
    focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isSearchNotifier,
      builder: (context, value, child) {
        if (!value) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: () {
                  isSearchNotifier.value = true;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    focusNode.requestFocus();
                  });
                },
                icon: const Icon(Icons.search),
              ),
              if (widget.onAdvancedSearch != null)
                IconButton(
                  tooltip: AppLocalizations.of(context).advancedSearch,
                  onPressed: widget.onAdvancedSearch,
                  icon: Icon(
                    Icons.tune_rounded,
                    color: widget.hasAdvancedSearch
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                ),
            ],
          );
        }
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(50, 0, 0, 0),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 30,
                    child: ListenableBuilder(
                      listenable: Listenable.merge([
                        widget.useCurrentSong ? currentSongNotifier : null,
                      ]),
                      builder: (context, _) {
                        return TextField(
                          focusNode: focusNode,
                          controller: widget.textController,
                          onTapOutside: (event) => focusNode.unfocus(),
                          decoration: InputDecoration(
                            hint: Text(
                              widget.hintText,
                              style: TextStyle(color: textColor.value),
                            ),
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: IconButton(
                              onPressed: () {
                                isSearchNotifier.value = false;
                                widget.textController.clear();
                                FocusScope.of(context).unfocus();
                                widget.onSearchTextChanged?.call();
                              },
                              icon: const Icon(Icons.clear),
                              padding: EdgeInsets.zero,
                            ),
                            filled: true,
                            fillColor: colorManager
                                .getSpecificMainPageSearchFieldColorForm(
                                  widget.useCurrentSong
                                      ? currentSongNotifier.value?.picture
                                      : backgroundPicture,
                                ),
                            contentPadding: EdgeInsets.zero,
                            isDense: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(15),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          onChanged: (_) =>
                              widget.onSearchTextChanged?.call(),
                        );
                      },
                    ),
                  ),
                ),
                if (widget.onAdvancedSearch != null)
                  IconButton(
                    tooltip: AppLocalizations.of(context).advancedSearch,
                    onPressed: widget.onAdvancedSearch,
                    icon: Icon(
                      Icons.tune_rounded,
                      color: widget.hasAdvancedSearch
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
