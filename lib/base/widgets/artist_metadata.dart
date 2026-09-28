import 'package:material_ui/material_ui.dart';
import 'package:sylvakru/base/data/artist_album.dart';
import 'package:sylvakru/l10n/generated/app_localizations.dart';
import 'package:sylvakru/base/utils/genre_names.dart';
import 'package:sylvakru/base/services/translation.dart';
import 'package:sylvakru/base/data/config.dart';
import 'package:sylvakru/base/data/setting.dart';

/// The metadata block shown on an artist page.
///
/// Album count, year range and genres are derived locally (every source
/// already provides them); the biography is server side and only arrives for
/// stream sources, so it is simply omitted when absent.
class ArtistMetadata extends StatefulWidget {
  final Artist artist;

  /// How many lines of biography to show before collapsing.
  final int collapsedLines;

  const ArtistMetadata({
    super.key,
    required this.artist,
    this.collapsedLines = 3,
  });

  @override
  State<ArtistMetadata> createState() => _ArtistMetadataState();
}

class _ArtistMetadataState extends State<ArtistMetadata> {
  bool _expanded = false;

  /// The translated biography, once the service answered.
  String? _translated;

  /// Which of the two the listener is reading.
  bool _showOriginal = false;

  @override
  void initState() {
    super.initState();
    // An artist whose songs are already in the library never had its server
    // metadata requested, because that request used to ride along with the song
    // load. This block is where every artist view shows the biography, so it is
    // where the request belongs.
    widget.artist.loadInfo().then((_) => _translateBiography());
    translationEnabledNotifier.addListener(_onTranslationSettingsChanged);
    translationBaseUrlNotifier.addListener(_onTranslationSettingsChanged);
    translationModelNotifier.addListener(_onTranslationSettingsChanged);
    config.translationApiKeyNotifier.addListener(_onTranslationSettingsChanged);
  }

  @override
  void dispose() {
    translationEnabledNotifier.removeListener(_onTranslationSettingsChanged);
    translationBaseUrlNotifier.removeListener(_onTranslationSettingsChanged);
    translationModelNotifier.removeListener(_onTranslationSettingsChanged);
    config.translationApiKeyNotifier.removeListener(
      _onTranslationSettingsChanged,
    );
    super.dispose();
  }

  /// Re-runs the translation when the service settings change.
  ///
  /// Without this, a page opened before translation was configured kept showing
  /// the original text: it only ever asked once, when it was first built.
  void _onTranslationSettingsChanged() {
    final biography = widget.artist.biography?.trim();
    if (biography == null || biography.isEmpty) {
      return;
    }
    if (!translator.isEnabled) {
      if (_translated != null) {
        setState(() {
          _translated = null;
          _showOriginal = false;
        });
      }
      return;
    }
    _translateBiography();
  }

  /// Asks the configured service for a translation of the biography.
  ///
  /// Best effort: while the request is in flight the page shows the original,
  /// and if no translation ever arrives the page keeps showing it.
  Future<void> _translateBiography() async {
    final biography = widget.artist.biography?.trim();
    if (biography == null || biography.isEmpty) {
      return;
    }
    final translated = await translator.translate(biography);
    if (!mounted || translated == null) {
      return;
    }
    setState(() {
      _translated = translated;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return ListenableBuilder(
      listenable: widget.artist.changeNotifier,
      builder: (context, _) {
        final artist = widget.artist;
        final facts = <String>[
          if (artist.albumCount > 0) l10n.albumCount(artist.albumCount),
          if (artist.yearRange != null) artist.yearRange!,
          if (artist.genres.isNotEmpty) genreNamesLabel(artist.genres.take(3)),
        ];
        final biography = artist.biography?.trim();

        if (facts.isEmpty && (biography == null || biography.isEmpty)) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (facts.isNotEmpty)
                Text(
                  facts.join(' · '),
                  style: TextStyle(fontSize: 12),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              if (biography != null && biography.isNotEmpty) ...[
                if (facts.isNotEmpty) const SizedBox(height: 6),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    setState(() {
                      _expanded = !_expanded;
                    });
                  },
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Text(
                      _showOriginal || _translated == null
                          ? biography
                          : _translated!,
                      style: TextStyle(fontSize: 12, height: 1.4),
                      maxLines: _expanded ? null : widget.collapsedLines,
                      overflow: _expanded
                          ? TextOverflow.visible
                          : TextOverflow.ellipsis,
                    ),
                  ),
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    setState(() {
                      _expanded = !_expanded;
                    });
                  },
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        _expanded ? l10n.showLess : l10n.showMore,
                        style: TextStyle(fontSize: 12, fontWeight: .bold),
                      ),
                    ),
                  ),
                ),
                if (_translated != null)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      setState(() {
                        _showOriginal = !_showOriginal;
                      });
                    },
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          _showOriginal
                              ? l10n.translationShowTranslated
                              : l10n.translationShowOriginal,
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}
