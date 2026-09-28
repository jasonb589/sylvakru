import 'package:sylvakru/base/my_audio_metadata.dart';
import 'package:sylvakru/base/utils/metadata_utils.dart';

/// How the download centre orders what it lists.
enum DownloadSort { title, artist, album, recentlyPlayed, mostPlayed }

/// Whether the centre splits its list into sections, and by what.
enum DownloadGroup { none, album, artist }

/// One line of the centre's list: a section header, or a song.
class DownloadListEntry {
  const DownloadListEntry.header(this.title) : song = null;
  const DownloadListEntry.song(this.song) : title = null;

  final String? title;
  final MyAudioMetadata? song;

  bool get isHeader => title != null;
}

/// Sorts and groups the songs the download centre shows.
///
/// Pure so the ordering can be tested without a page. When grouping is on the
/// group key leads the sort — sections have to be contiguous, and the chosen
/// order then decides inside each one. Every comparison ends in the pinyin sort
/// key so rows never shuffle between rebuilds.
List<DownloadListEntry> buildDownloadList(
  List<MyAudioMetadata> songs, {
  DownloadSort sort = DownloadSort.title,
  DownloadGroup group = DownloadGroup.none,
}) {
  String groupKeyOf(MyAudioMetadata song) =>
      group == DownloadGroup.album ? getAlbum(song) : getArtist(song);

  final sorted = [...songs]
    ..sort((a, b) {
      if (group != DownloadGroup.none) {
        final byGroup = groupKeyOf(
          a,
        ).toLowerCase().compareTo(groupKeyOf(b).toLowerCase());
        if (byGroup != 0) {
          return byGroup;
        }
      }
      return _compare(sort, a, b);
    });

  if (group == DownloadGroup.none) {
    return [for (final song in sorted) DownloadListEntry.song(song)];
  }

  final entries = <DownloadListEntry>[];
  String? current;
  for (final song in sorted) {
    final name = groupKeyOf(song);
    if (name != current) {
      current = name;
      entries.add(DownloadListEntry.header(name));
    }
    entries.add(DownloadListEntry.song(song));
  }
  return entries;
}

int _compare(DownloadSort sort, MyAudioMetadata a, MyAudioMetadata b) {
  switch (sort) {
    case DownloadSort.title:
      return _byText(a, b, getTitle);
    case DownloadSort.artist:
      return _byText(a, b, getArtist);
    case DownloadSort.album:
      return _byText(a, b, getAlbum);
    case DownloadSort.recentlyPlayed:
      final left = a.lastPlayed?.millisecondsSinceEpoch ?? 0;
      final right = b.lastPlayed?.millisecondsSinceEpoch ?? 0;
      if (left != right) {
        return right.compareTo(left);
      }
      return a.compareTitle.compareTo(b.compareTitle);
    case DownloadSort.mostPlayed:
      if (a.playCount != b.playCount) {
        return b.playCount.compareTo(a.playCount);
      }
      return a.compareTitle.compareTo(b.compareTitle);
  }
}

int _byText(
  MyAudioMetadata a,
  MyAudioMetadata b,
  String Function(MyAudioMetadata?) key,
) {
  final result = key(a).toLowerCase().compareTo(key(b).toLowerCase());
  return result != 0 ? result : a.compareTitle.compareTo(b.compareTitle);
}
