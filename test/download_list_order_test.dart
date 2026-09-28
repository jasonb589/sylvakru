import 'dart:io';

import 'package:audio_tags_lofty/audio_tags_lofty.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sylvakru/base/app.dart';
import 'package:sylvakru/base/my_audio_metadata.dart';
import 'package:sylvakru/base/utils/download_list_order.dart';

/// The centre's list is sorted and grouped in one pure step, so this is where
/// that behaviour is pinned: order inside a section, and which entries are
/// section headings.
void main() {
  setUpAll(() {
    appSupportDir = Directory.systemTemp.createTempSync('sylvakru_order');
  });

  MyAudioMetadata song(
    String id, {
    String? title,
    String? artist,
    String? album,
    int playCount = 0,
    DateTime? lastPlayed,
  }) {
    return MyAudioMetadata(
        AudioMetadata(title: title ?? id),
        id: id,
        playCount: playCount,
        lastPlayed: lastPlayed,
      )
      ..artist = artist
      ..album = album;
  }

  List<String> titlesOf(List<DownloadListEntry> entries) => [
    for (final entry in entries)
      if (!entry.isHeader) entry.song!.id,
  ];

  test('the default order is by title', () {
    final songs = [
      song('b', title: 'Beta'),
      song('a', title: 'Alpha'),
      song('c', title: 'Gamma'),
    ];

    expect(titlesOf(buildDownloadList(songs)), ['a', 'b', 'c']);
  });

  test('artist and album are offered as sort keys', () {
    final songs = [
      song('1', artist: 'Zoe', album: 'Two'),
      song('2', artist: 'Adam', album: 'One'),
    ];

    expect(titlesOf(buildDownloadList(songs, sort: DownloadSort.artist)), [
      '2',
      '1',
    ]);
    expect(titlesOf(buildDownloadList(songs, sort: DownloadSort.album)), [
      '2',
      '1',
    ]);
  });

  test('recently played puts the newest first and the never played last', () {
    final songs = [
      song('never', title: 'Never'),
      song('old', title: 'Old', lastPlayed: DateTime(2026, 1, 1)),
      song('new', title: 'New', lastPlayed: DateTime(2026, 9, 1)),
    ];

    expect(
      titlesOf(buildDownloadList(songs, sort: DownloadSort.recentlyPlayed)),
      ['new', 'old', 'never'],
    );
  });

  test('most played counts first', () {
    final songs = [
      song('few', title: 'Few', playCount: 1),
      song('many', title: 'Many', playCount: 9),
    ];

    expect(titlesOf(buildDownloadList(songs, sort: DownloadSort.mostPlayed)), [
      'many',
      'few',
    ]);
  });

  test('grouping by album keeps sections together and sorted inside', () {
    final songs = [
      song('b2', title: 'Beta', album: 'Second'),
      song('a2', title: 'Alpha', album: 'Second'),
      song('c1', title: 'Gamma', album: 'First'),
    ];

    final entries = buildDownloadList(
      songs,
      sort: DownloadSort.title,
      group: DownloadGroup.album,
    );

    expect(
      [
        for (final entry in entries)
          entry.isHeader ? '##${entry.title}' : entry.song!.id,
      ],
      ['##First', 'c1', '##Second', 'a2', 'b2'],
    );
  });

  test('grouping by artist does the same on the artist key', () {
    final songs = [
      song('1', title: 'One', artist: 'Zoe'),
      song('2', title: 'Two', artist: 'Adam'),
    ];

    final entries = buildDownloadList(songs, group: DownloadGroup.artist);

    expect(
      [
        for (final entry in entries)
          entry.isHeader ? '##${entry.title}' : entry.song!.id,
      ],
      ['##Adam', '2', '##Zoe', '1'],
    );
  });
}
