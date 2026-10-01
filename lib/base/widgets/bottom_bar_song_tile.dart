import 'package:material_ui/material_ui.dart';
import 'package:smooth_corner/smooth_corner.dart';
import 'package:sylvakru/base/design/app_tokens.dart';
import 'package:sylvakru/base/design/interaction_overlay.dart';
import 'package:sylvakru/base/design/marquee_text.dart';
import 'package:sylvakru/base/my_audio_metadata.dart';
import 'package:sylvakru/base/utils/metadata_utils.dart';
import 'package:sylvakru/base/widgets/cover_art_widget.dart';
import 'package:sylvakru/base/widgets/lyrics_line_bar.dart';

/// The song the bottom bar shows on the left: cover, title, one line under it.
///
/// The bar hands the tile a fixed height and the tile has to hold to it - the
/// cover centred, every line inside. It did not: a title that has to travel
/// reported the whole height it was offered as its own, and the list tile
/// below it then placed the second line under the tile's bottom edge and
/// centred the cover for a tile that was never drawn, which is the cover the
/// window cut in half.
///
/// The tile is its own widget so that this can be measured - in a test, against
/// a bar, instead of in a screenshot.
class BottomBarSongTile extends StatelessWidget {
  /// Size of the cover thumbnail, and the square the title lines up with.
  static const double coverSize = 50;

  /// Font size of the line under the title.
  static const double subtitleFontSize = 13;

  const BottomBarSongTile({
    super.key,
    required this.song,
    this.onTap,
    this.subtitle,
  });

  /// The song to show. Nothing is drawn but an empty tile when it is null.
  final MyAudioMetadata? song;

  /// Opens the playback screen. Without it the tile does nothing.
  final VoidCallback? onTap;

  /// The single line under the title, when the caller has one of its own.
  ///
  /// Otherwise the tile shows the lyric line being sung with artist - album
  /// behind it. A test passes a plain line here so the tile needs no player.
  final Widget? subtitle;

  @override
  Widget build(BuildContext context) {
    final currentSong = song;

    return Theme(
      data: AppOverlay.none(context, keepFocus: true),
      child: Material(
        color: Colors.transparent,
        shape: SmoothRectangleBorder(
          smoothness: 1,
          borderRadius: .all(.circular(AppRadius.row)),
        ),
        clipBehavior: .antiAlias,
        child: ListenableBuilder(
          listenable: Listenable.merge([currentSong?.updateNotifier]),
          builder: (context, _) {
            return ListTile(
              // The tile's own density, not the platform's. A packed list row
              // - the desktop default, -2, so 8 px shorter - allows a leading
              // widget 48 px, which is where the 50 px cover was being squashed
              // into 50 x 48. The bottom bar is not a list and its tile is
              // 75 px tall on every platform; this keeps the cover a square and
              // the lines beside it in one place.
              visualDensity: VisualDensity.standard,
              leading: Hero(
                tag: 'cover',
                child: CoverArtWidget(
                  size: coverSize,
                  borderRadius: AppRadius.coverRow,
                  elevation: AppElevation.control,
                  picture: currentSong?.picture,
                  useResize: false,
                ),
              ),
              title: MarqueeText(text: getTitle(currentSong)),
              subtitle: subtitle ?? _subtitleFor(currentSong),
              onTap: onTap,
            );
          },
        ),
      ),
    );
  }

  /// The line under the title when the caller does not supply one.
  static Widget? _subtitleFor(MyAudioMetadata? song) {
    if (song == null) {
      return null;
    }

    return LyricsLineBar(
      fontSize: subtitleFontSize,
      maxLines: 1,
      // no timed lyrics: keep showing artist - album
      fallback: artistAlbumLine(song),
    );
  }

  /// Artist - album on one line: what the tile shows when the song has no
  /// timed lyrics to follow. Next to the tile so a test can measure it with the
  /// exact line the bar draws.
  static Widget artistAlbumLine(MyAudioMetadata song) {
    return Row(
      children: [
        // Plain text on purpose: the tile opens the playback screen, and the
        // artist link lives there (ArtistAlbumLine). This name used to open the
        // artist page, which meant the bar jumped past the screen it is there
        // to open.
        Flexible(
          child: Text(
            getArtist(song),
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: subtitleFontSize),
          ),
        ),
        Flexible(
          child: Text(
            " - ${getAlbum(song)}",
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: subtitleFontSize),
          ),
        ),
      ],
    );
  }
}
