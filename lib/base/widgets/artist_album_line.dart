import 'package:material_ui/material_ui.dart';
import 'package:sylvakru/base/my_audio_metadata.dart';
import 'package:sylvakru/base/services/interaction.dart';
import 'package:sylvakru/base/utils/metadata_utils.dart';

/// "Artist - Album" on the playback screens, where tapping the artist opens the
/// artist page.
///
/// The two halves are separate on purpose: a tap meant for the album must not
/// land on the artist instead. Both ellipsize rather than scroll - two marquees
/// on one line would travel against each other, and the title above this line
/// already carries the marquee.
///
/// The bottom bar deliberately does not use this widget. There the whole row
/// opens the playback screen, and the artist name inside it is plain text that
/// goes nowhere: the way into an artist page is from the playback screen, not
/// from the bar that gets you there.
class ArtistAlbumLine extends StatelessWidget {
  final MyAudioMetadata? song;
  final TextStyle style;
  final TextAlign textAlign;

  const ArtistAlbumLine({
    super.key,
    required this.song,
    required this.style,
    this.textAlign = TextAlign.start,
  });

  @override
  Widget build(BuildContext context) {
    final track = song;
    final artist = getArtist(track);
    final album = getAlbum(track);

    Widget text(String value) => Text(
      value,
      style: style,
      textAlign: textAlign,
      overflow: TextOverflow.ellipsis,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: track == null
              ? text(artist)
              : GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => goToArtist(track, context),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: text(artist),
                  ),
                ),
        ),
        Flexible(child: text(' - $album')),
      ],
    );
  }
}
