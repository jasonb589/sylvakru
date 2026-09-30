import 'package:sylvakru/base/my_audio_metadata.dart';

/// Songs that look like the same recording, so the library can be tidied up.
///
/// Nothing here removes anything: a library can hold the same song twice on
/// purpose - a live take beside the studio one, a remaster, a different cover -
/// and only the user can tell which copy they meant to keep.
class DuplicateGroup {
  /// The songs in the group, shortest first (songs of unknown length last).
  final List<MyAudioMetadata> songs;

  const DuplicateGroup(this.songs);

  /// The song the group is named after.
  MyAudioMetadata get song => songs.first;
}

/// How far two lengths may differ and still count as the same recording.
///
/// Rips of one track rarely agree to the millisecond, and a second or two of
/// leading or trailing silence is normal.
const Duration duplicateTolerance = Duration(seconds: 2);

/// The songs that share a title and an artist and are of about the same length.
///
/// Songs without a title are left out: there is nothing to compare them by, and
/// every untagged file would otherwise look like a duplicate of every other.
/// Songs whose length is unknown are only grouped with each other, so a missing
/// duration cannot pull two different recordings together.
List<DuplicateGroup> findDuplicateSongs(
  List<MyAudioMetadata> songs, {
  Duration tolerance = duplicateTolerance,
}) {
  final byName = <String, List<MyAudioMetadata>>{};
  for (final song in songs) {
    final key = _nameKey(song);
    if (key == null) {
      continue;
    }
    byName.putIfAbsent(key, () => []).add(song);
  }

  final groups = <DuplicateGroup>[];
  for (final bucket in byName.values) {
    if (bucket.length < 2) {
      continue;
    }

    final known = bucket.where((song) => song.duration != null).toList()
      ..sort((a, b) => a.duration!.compareTo(b.duration!));

    // Walk the lengths in order and keep a cluster while it stays within
    // [tolerance] of its own shortest member, so 100s and 101s stay together
    // and a 103s take starts a cluster of its own.
    var cluster = <MyAudioMetadata>[];
    for (final song in known) {
      if (cluster.isEmpty || _within(song, cluster.first, tolerance)) {
        cluster.add(song);
      } else {
        if (cluster.length > 1) {
          groups.add(DuplicateGroup(cluster));
        }
        cluster = [song];
      }
    }
    if (cluster.length > 1) {
      groups.add(DuplicateGroup(cluster));
    }

    final unknown = bucket.where((song) => song.duration == null).toList();
    if (unknown.length > 1) {
      groups.add(DuplicateGroup(unknown));
    }
  }

  groups.sort((a, b) {
    final byTitle = _sortTitle(a.song).compareTo(_sortTitle(b.song));
    if (byTitle != 0) {
      return byTitle;
    }
    return (a.song.duration ?? Duration.zero).compareTo(
      b.song.duration ?? Duration.zero,
    );
  });

  return groups;
}

bool _within(
  MyAudioMetadata song,
  MyAudioMetadata anchor,
  Duration tolerance,
) => (song.duration! - anchor.duration!).abs() <= tolerance;

String _sortTitle(MyAudioMetadata song) => (song.title ?? '').toLowerCase();

/// The name two songs have to share to be compared at all, or null when the
/// song has no title to compare.
///
/// Case, padding and punctuation are folded away: "Know Better" and "know
/// better " are one song, not two.
String? _nameKey(MyAudioMetadata song) {
  final title = _fold(song.title);
  if (title.isEmpty) {
    return null;
  }
  return '$title|${_fold(song.artist)}';
}

/// Characters that never tell one recording from another.
final _noise = RegExp(r'''[\s\u3000\-_.,"'!?()\[\]]+''');

String _fold(String? value) =>
    value == null ? '' : value.toLowerCase().replaceAll(_noise, '');

/// Somewhere the song's bytes live, if anywhere: its own file, the copy the
/// user downloaded, or the playback cache. Null when all the library knows is
/// how to stream it.
String? songPath(MyAudioMetadata song) {
  for (final candidate in [song.path, song.downloadPath, song.cachePath]) {
    if (candidate != null && candidate.isNotEmpty) {
      return candidate;
    }
  }
  return null;
}
