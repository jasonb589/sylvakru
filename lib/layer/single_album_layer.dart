import 'package:material_ui/material_ui.dart';
import 'package:sylvakru/base/data/artist_album.dart';
import 'package:sylvakru/base/widgets/song_list.dart';

class SingleAlbumLayer extends StatelessWidget {
  final Album album;

  /// Which root layer the album was opened from, so "back" returns there.
  final String rootLabel;

  /// Set when opened from the home layer, which renders a slightly different
  /// header.
  final bool isHomeDetaile;

  const SingleAlbumLayer({
    super.key,
    required this.album,
    this.rootLabel = 'albums',
    this.isHomeDetaile = false,
  });

  @override
  Widget build(BuildContext context) {
    return SongList(
      album: album,
      isRoot: false,
      albumRootLabel: rootLabel,
      isHomeDetail: isHomeDetaile,
    );
  }
}
