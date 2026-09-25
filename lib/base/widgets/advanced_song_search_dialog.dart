import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sylvakru/base/utils/advanced_song_search.dart';
import 'package:sylvakru/l10n/generated/app_localizations.dart';

class AdvancedSongSearchDialog extends StatefulWidget {
  final SongSearchCriteria criteria;
  final bool editQuery;

  const AdvancedSongSearchDialog({
    super.key,
    required this.criteria,
    this.editQuery = false,
  });
  @override
  State<AdvancedSongSearchDialog> createState() =>
      _AdvancedSongSearchDialogState();
}
class _AdvancedSongSearchDialogState extends State<AdvancedSongSearchDialog> {
  final _formKey = GlobalKey<FormState>();
  final Set<SongSearchField> _fields = {};
  late final TextEditingController _queryController;
  late bool _exactMatch;
  late final TextEditingController _minYearController;
  late final TextEditingController _maxYearController;
  late final TextEditingController _minDurationController;
  late final TextEditingController _maxDurationController;
  late final TextEditingController _minBitrateController;
  late final TextEditingController _maxBitrateController;

  @override
  void initState() {
    super.initState();
    _fields.addAll(widget.criteria.fields);
    _exactMatch = widget.criteria.exactMatch;
    _queryController = _controller(widget.criteria.query);
    _minYearController = _controller(widget.criteria.minYear);
    _maxYearController = _controller(widget.criteria.maxYear);
    _minDurationController =
        _controller(widget.criteria.minDurationSeconds);
    _maxDurationController =
        _controller(widget.criteria.maxDurationSeconds);
    _minBitrateController = _controller(widget.criteria.minBitrateKbps);
    _maxBitrateController = _controller(widget.criteria.maxBitrateKbps);
  }

  TextEditingController _controller(int? value) =>
      TextEditingController(text: value?.toString() ?? '');

  @override
  void dispose() {
    _queryController.dispose();
    _minYearController.dispose();
    _maxYearController.dispose();
    _minDurationController.dispose();
    _maxDurationController.dispose();
    _minBitrateController.dispose();
    _maxBitrateController.dispose();
    super.dispose();
  }

  int? _value(TextEditingController controller) =>
      int.tryParse(controller.text.trim());

  String? _validateRange(
    AppLocalizations l10n,
    TextEditingController minimum,
    TextEditingController maximum,
  ) {
    final min = _value(minimum);
    final max = _value(maximum);
    if ((minimum.text.trim().isNotEmpty && min == null) ||
        (maximum.text.trim().isNotEmpty && max == null) ||
        (min != null && max != null && min > max)) {
      return l10n.invalidRange;
    }
    return null;
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    Navigator.pop(
      context,
      SongSearchCriteria(
        query: widget.editQuery
            ? _queryController.text.trim()
            : widget.criteria.query,
        fields: _fields,
        exactMatch: _exactMatch,
        minYear: _value(_minYearController),
        maxYear: _value(_maxYearController),
        minDurationSeconds: _value(_minDurationController),
        maxDurationSeconds: _value(_maxDurationController),
        minBitrateKbps: _value(_minBitrateController),
        maxBitrateKbps: _value(_maxBitrateController),
      ),
    );
  }

  Widget _queryField(AppLocalizations l10n) {
    if (!widget.editQuery) {
      return const SizedBox.shrink();
    }
    return TextFormField(
      controller: _queryController,
      decoration: InputDecoration(labelText: l10n.smartPlaylistQuery),
    );
  }

  Widget _rangeRow(
    AppLocalizations l10n,
    String label,
    TextEditingController minimum,
    TextEditingController maximum,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 12, top: 8),
          child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: minimum,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(labelText: l10n.minimum),
                validator: (_) => _validateRange(l10n, minimum, maximum),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: maximum,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(labelText: l10n.maximum),
                validator: (_) => _validateRange(l10n, minimum, maximum),
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textColor = Theme.of(context).colorScheme.onSurface;
    final fieldLabels = <SongSearchField, String>{
      SongSearchField.title: l10n.title,
      SongSearchField.artist: l10n.artist,
      SongSearchField.album: l10n.album,
      SongSearchField.albumArtist: l10n.albumArtist,
      SongSearchField.genre: l10n.genre,
    };

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 460,
        maxHeight: MediaQuery.sizeOf(context).height * 0.8,
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.advancedSearch,
                style: TextStyle(
                  color: textColor,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _queryField(l10n),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(l10n.searchIn),
                      ),
                      Wrap(
                        spacing: 4,
                        runSpacing: 0,
                        children: [
                          for (final entry in fieldLabels.entries)
                            FilterChip(
                              label: Text(entry.value),
                              selected: _fields.contains(entry.key),
                              onSelected: (selected) {
                                setState(() {
                                  if (selected) {
                                    _fields.add(entry.key);
                                  } else {
                                    _fields.remove(entry.key);
                                  }
                                });
                              },
                            ),
                        ],
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(l10n.exactMatch),
                        value: _exactMatch,
                        onChanged: (value) => setState(() {
                          _exactMatch = value ?? false;
                        }),
                      ),
                      _rangeRow(
                        l10n,
                        l10n.yearRange,
                        _minYearController,
                        _maxYearController,
                      ),
                      _rangeRow(
                        l10n,
                        l10n.durationRangeSeconds,
                        _minDurationController,
                        _maxDurationController,
                      ),
                      _rangeRow(
                        l10n,
                        l10n.bitrateRangeKbps,
                        _minBitrateController,
                        _maxBitrateController,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(
                      context,
                      SongSearchCriteria(),
                    ),
                    child: Text(l10n.reset),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _submit,
                    child: Text(l10n.applyFilters),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
