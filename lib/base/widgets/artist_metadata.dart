import 'package:material_ui/material_ui.dart';
import 'package:sylvakru/base/data/artist_album.dart';
import 'package:sylvakru/l10n/generated/app_localizations.dart';

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
          if (artist.genres.isNotEmpty) artist.genres.take(3).join(' / '),
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
                      biography,
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
              ],
            ],
          ),
        );
      },
    );
  }
}
