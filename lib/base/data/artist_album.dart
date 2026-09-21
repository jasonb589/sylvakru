import 'package:lpinyin/lpinyin.dart';
import 'dart:async';


import 'package:sylvakru/base/app.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sylvakru/base/data/library.dart';
import 'package:sylvakru/base/data/setting.dart';
import 'package:sylvakru/base/services/picture_service.dart';
import 'package:sylvakru/base/my_audio_metadata.dart';
import 'package:sylvakru/base/utils/metadata_utils.dart';
import 'package:sylvakru/base/services/stream_client.dart';
import 'package:sylvakru/layer/layers_manager.dart';

final artistAlbumManager = ArtistAlbumManager();

class ArtistAlbumManager {
  List<Artist> artistList = [];
  Map<String, Artist> artistMap = {};
  /// Artists the server reported in [loadArtists], keyed by name.
  ///
  /// A server artist knows its id, cover art, album count and biography but
  /// carries no songs; the locally classified artist owns the songs but none of
  /// that metadata. Both describe the same artist, so they are merged by name
  /// instead of being kept as two entries (see [_mergeServerArtists]).
  final Map<String, Artist> _serverArtists = {};

  List<Album> albumList = [];
  // streamSoure will has duplicate name album
  Map<String, Album> albumMap = {};
  final updateNotifier = ValueNotifier(0);

  /// The newest albums, capped at [recentlyAddedLimit]. These are what the
  /// compact "recently added" modules on the home screens render.
  List<Album> recentlyAddedAlbumList = [];

  /// The same albums without the cap, for the full "recently added" page.
  List<Album> recentlyAddedAlbumAll = [];

  final recentlyAddedNotifier = ValueNotifier(0);

  /// How many albums the "recently added" module shows at most.
  static const int recentlyAddedLimit = 20;

  /// Set once [classify] has finished, so the artists/albums layers know
  /// whether they are still waiting for the first pass.
  bool done = false;

  ArtistAlbumManager() {
    artistsIsAscendingNotifier.addListener(() {
      sortArtists();
      updateNotifier.value++;
    });
    albumsIsAscendingNotifier.addListener(() {
      sortAlbums();
      updateNotifier.value++;
    });
  }

  List<ArtistAlbumBase> getArtistAlbumList(bool isArtist) {
    return isArtist ? artistList : albumList;
  }

  ValueNotifier<bool> getRandomizeNotifier(bool isArtist) {
    return isArtist ? artistsRandomizeNotifier : albumsRandomizeNotifier;
  }

  ValueNotifier<bool> getIsAscendingNotifier(bool isArtist) {
    return isArtist ? artistsIsAscendingNotifier : albumsIsAscendingNotifier;
  }

  ValueNotifier<bool> getUseLargePictureNotifier(bool isArtist) {
    return isArtist
        ? artistsUseLargePictureNotifier
        : albumsUseLargePictureNotifier;
  }

  /// Rebuilds the artist/album lists from the library.
  ///
  /// This runs again after every reload/sync, so it rebuilds from scratch:
  /// appending to the previous pass duplicated every song, and an artist's song
  /// list grew on each call (1 -> 4 -> ...). The objects are therefore replaced
  /// rather than reused, which is why the reload that triggers this also drops
  /// the artist/album detail layers.
  void classify() async {
    artistList.clear();
    artistMap.clear();
    albumList.clear();
    albumMap.clear();

    for (final song in library.songList) {
      _processSong(song);
    }

    sortArtists();
    sortAlbums();

    for (final album in albumList) {
      album.sort();
    }

    for (final artist in artistList) {
      artist.combineAlbums();
    }

    // the artist objects that carried the server metadata were replaced above,
    // so the merge has to be re-applied
    _mergeServerArtists();
    sortArtists();

    updateRecentlyAddedFromAlbums();
    done = true;
    updateNotifier.value++;
  }

  /// The albums that have ever been added, newest added first.
  ///
  /// Stream sources only know the albums they have already fetched, so this
  /// list is filled by [loadRecentlyAdded].
  List<Album> get recentlyAddedAlbums {
    final sorted = albumList.where((album) => album.addedTime != null).toList()
      ..sort((a, b) => b.addedTime!.compareTo(a.addedTime!));
    return sorted;
  }

  /// Rebuilds the "recently added" lists from the local album list.
  ///
  /// Only meaningful for non-stream sources, where every album already knows
  /// when its files were last modified.
  void updateRecentlyAddedFromAlbums() {
    final sorted = recentlyAddedAlbums;
    recentlyAddedAlbumAll = sorted;
    recentlyAddedAlbumList = sorted.take(recentlyAddedLimit).toList();
    recentlyAddedNotifier.value++;
  }

  /// The server side sort used to ask for the newest albums.
  String get _recentlyAddedSortType {
    switch (sourceType) {
      case .navidrome:
        // getAlbumList2 'newest' is already ordered by creation time, newest
        // first.
        return 'newest';
      case .emby:
        return 'DateCreated';
      default:
        return 'alphabeticalByName';
    }
  }

  Completer<void>? _recentlyAddedCompleter;
  bool _recentlyAddedLoaded = false;

  /// Whether the "recently added" albums have been fetched already.
  bool get recentlyAddedLoaded => _recentlyAddedLoaded;

  /// Loads the albums for the "recently added" module.
  ///
  /// Local and WebDAV libraries are sorted locally, stream sources are asked
  /// for their newest albums instead.
  Future<void> loadRecentlyAdded({bool force = false}) async {
    if (_recentlyAddedLoaded && !force) {
      return;
    }

    final pending = _recentlyAddedCompleter;
    if (pending != null) {
      return pending.future;
    }

    if (isNotStreamSource) {
      // notifies through updateRecentlyAddedFromAlbums
      updateRecentlyAddedFromAlbums();
      _recentlyAddedLoaded = true;
      return;
    }

    final completer = Completer<void>();
    _recentlyAddedCompleter = completer;
    try {
      final albumList = await streamClient?.getAlbumList(
        0,
        type: _recentlyAddedSortType,
        descending: true,
      );
      if (albumList != null) {
        final sorted = albumList.toList();
        // trust the server order unless every album knows its creation time
        if (sorted.every((album) => album.created != null)) {
          sorted.sort((a, b) => b.created!.compareTo(a.created!));
        }
        recentlyAddedAlbumAll = sorted;
        recentlyAddedAlbumList = sorted.take(recentlyAddedLimit).toList();
        // a failed request must not be cached as success, otherwise the module
        // stays empty for the whole session when the server was unreachable
        _recentlyAddedLoaded = true;
        recentlyAddedNotifier.value++;
      }
    } finally {
      _recentlyAddedCompleter = null;
      completer.complete();
    }
  }

  void _processSong(MyAudioMetadata song) {
    final albumName = getAlbum(song);

    Album? album = albumMap[albumName];
    if (album == null) {
      album = Album(albumName);
      albumList.add(album);
      albumMap[albumName] = album;
    }

    if (song.year != null && album.year == null) {
      album.year = song.year;
    }

    album.songList.add(song);

    for (String artistName in getArtists(getArtist(song))) {
      Artist? artist = artistMap[artistName];
      if (artist == null) {
        artist = Artist(artistName);
        artistList.add(artist);
        artistMap[artistName] = artist;
      }
      artist.albumSet.add(album);
    }
  }

  void sortArtists() {
    artistList.sort((a, b) {
      if (artistsIsAscendingNotifier.value) {
        return a.compareName.compareTo(b.compareName);
      } else {
        return b.compareName.compareTo(a.compareName);
      }
    });
  }

  void sortAlbums() {
    albumList.sort((a, b) {
      if (albumsIsAscendingNotifier.value) {
        return a.compareName.compareTo(b.compareName);
      } else {
        return b.compareName.compareTo(a.compareName);
      }
    });
  }

  void updateArtistAlbum() {
    layersManager.clearArtistAlbum();
    clear();
    classify();
  }

  void clear() {
    artistList.clear();
    albumList.clear();
    artistMap.clear();
    albumMap.clear();

    // stream sources have to ask the server again for their newest albums
    _recentlyAddedLoaded = false;
    recentlyAddedAlbumList = [];
    recentlyAddedAlbumAll = [];

    // The lists above are empty now, so a completed completer would make the
    // next loadArtists/loadAlbums return immediately and the artist/album
    // layers would stay empty for the rest of the session.
    artistCompleter = null;
    ablumCompleter = null;
    _serverArtists.clear();

    done = false;

    classify();
  }

  // use completer to avoid loading same data multiple times
  Completer<void>? artistCompleter;
  Completer<int?>? ablumCompleter;

  Future<void> loadArtists() async {
    if (artistCompleter == null) {
      artistCompleter = Completer<void>();
      final tmpArtistList = await streamClient?.getArtistList();
      if (tmpArtistList == null) {
        artistAlbumManager.updateNotifier.value++;
        artistCompleter!.complete();
        return;
      }

      for (final artist in tmpArtistList) {
        _serverArtists[artist.name] = artist;
      }
      _mergeServerArtists();
      sortArtists();
      artistAlbumManager.updateNotifier.value++;
      artistCompleter!.complete();
      return;
    }
    artistAlbumManager.updateNotifier.value++;
    return artistCompleter!.future;
  }

  /// Folds the server's artist metadata into the locally classified artists.
  ///
  /// The two describe one artist but own different fields, so they are matched
  /// by name: the local entry keeps its songs and takes the server's id, cover
  /// art, album count and biography. Appending the server entry instead (the
  /// old behaviour) put a *second* artist of the same name into [artistList]
  /// and let it overwrite [artistMap], so opening that artist showed an empty
  /// page: the server object has no songs and nothing ever filled them.
  ///
  /// An artist the server knows but the library holds no song for is added
  /// as-is, so it still appears in the artists list.
  void _mergeServerArtists() {
    for (final entry in _serverArtists.entries) {
      final server = entry.value;
      final existing = artistMap[entry.key];
      if (existing == null) {
        artistList.add(server);
        artistMap[entry.key] = server;
      } else if (!identical(existing, server)) {
        existing.adoptServerMetadata(server);
      }
    }
  }

  // null: error; 0: end
  Future<int?> loadAlbums() async {
    if (ablumCompleter == null) {
      ablumCompleter = Completer<int?>();
      final albumList = await streamClient?.getAlbumList(
        artistAlbumManager.albumList.length,
      );
      if (albumList == null) {
        artistAlbumManager.updateNotifier.value++;
        ablumCompleter!.complete(null);
        ablumCompleter = null;
        return null;
      }

      artistAlbumManager.albumList.addAll(albumList);
      sortAlbums();
      artistAlbumManager.updateNotifier.value++;

      ablumCompleter!.complete(albumList.length);
      ablumCompleter = null;
      return albumList.length;
    }
    return ablumCompleter!.future;
  }
}

abstract class ArtistAlbumBase {
  String? id;
  final String name;
  late final String compareName;

  final List<MyAudioMetadata> songList = [];

  final bool isArtist;

  /// Picture for stream sources, which know their own cover art. Local/WebDAV
  /// libraries have no such id and derive it from the first song instead.
  MyPicture? _picture;

  /// The cover to render for this artist/album.
  ///
  /// Stream sources identify cover art by the server's coverArtId, but an
  /// album/artist built from the local song list (see [_processSong]) carries
  /// none, so its id is empty and the row would render blank. Falling back to
  /// the first song's cover keeps those entries showing real artwork.
  MyPicture get picture {
    final own = _picture;
    if (own != null && own.id.isNotEmpty) {
      return own;
    }
    if (songList.isNotEmpty) {
      return songList.first.picture;
    }
    // Neither a server cover id nor any song to borrow one from. Derive a
    // stable id from the name and cache it, so repeated reads return the same
    // picture (Hero tags and changeNotifier listeners depend on that).
    return _picture = MyPicture.form(name);
  }

  ArtistAlbumBase({required this.name, required this.isArtist, this.id, String? coverArtId}) {
    id ??= name;
    compareName = PinyinHelper.getPinyinE(name);
    if (isStreamSource) {
      _picture = MyPicture.form(coverArtId ?? '');
    }
  }

  bool get isEmpty => songList.isEmpty;


  /// Fills this entry from its source (server or local library).
  Future<void> load();
  int get totalCount => songList.length;
}

class Artist extends ArtistAlbumBase {
  Artist(
    String name, {
    super.id,
    super.coverArtId,
    this.biography,
    this.serverAlbumCount,
  }) : super(name: name, isArtist: true);

  Set<Album> albumSet = {};


  List<Album> albumList = [];

  /// Short description supplied by the server (Navidrome/Emby). Local and
  /// WebDAV libraries have no such data, so this stays null there.
  String? biography;

  /// Points this artist's picture at an absolute [url] supplied by the server's
  /// metadata provider, and starts downloading it.
  void useImageUrl(String url) => picture.useImageUrl(url);

  /// Album count reported by the server, used only until [albumList] is filled.
  int? serverAlbumCount;

  /// Whether [load] already asked the server for [biography].
  bool biographyLoaded = false;


  /// Guards [load] so the server is only asked once per artist.
  Completer<void>? completer;
  final changeNotifier = ValueNotifier(0);

  /// How many albums this artist has, preferring the loaded album list.
  int get albumCount =>
      albumList.isNotEmpty ? albumList.length : (serverAlbumCount ?? 0);

  /// The distinct genres across this artist's songs, in first-seen order.
  List<String> get genres {
    final seen = <String>{};
    for (final song in songList) {
      final genre = song.genre;
      if (genre == null || genre.trim().isEmpty) {
        continue;
      }
      // a tag may hold several genres, e.g. "Rock/Pop"
      for (final part in genre.split(RegExp(r'[/;]'))) {
        final name = part.trim();
        if (name.isNotEmpty) {
          seen.add(name);
        }
      }
    }
    return seen.toList();
  }

  /// The active years of this artist, e.g. "1998 - 2011" or "2005".
  ///
  /// Derived from the album years, which every source already provides.
  String? get yearRange {
    final years = albumList
        .map((album) => album.year)
        .whereType<int>()
        .toList()
      ..sort();
    if (years.isEmpty) {
      return null;
    }
    final first = years.first;
    final last = years.last;
    return first == last ? '$first' : '$first - $last';
  }

  void combineAlbums() {
    albumSet.removeWhere((album) => album.isEmpty);
    albumList = albumSet.toList();
    albumList.sort((a, b) {
      int aYear = a.year ?? 9999;
      int bYear = b.year ?? 9999;
      final yearCompre = aYear.compareTo(bYear);
      if (yearCompre != 0) {
        return yearCompre;
      }
      return a.compareName.compareTo(b.compareName);
    });

    for (final album in albumList) {
      songList.addAll(album.artist2SongList[name]!);
    }
  }

  /// Takes the identifying metadata from a server entry of the same name.
  ///
  /// The server id is what the artist endpoints need, and its cover art is a
  /// real artist image instead of the first album's square cover.
  void adoptServerMetadata(Artist server) {
    final serverId = server.id;
    if (serverId != null && serverId.isNotEmpty) {
      id = serverId;
    }

    final serverPicture = server._picture;
    if (serverPicture != null && serverPicture.id.isNotEmpty) {
      _picture = serverPicture;
    }

    final serverBiography = server.biography;
    if (serverBiography != null && serverBiography.isNotEmpty) {
      biography = serverBiography;
      biographyLoaded = true;
    }

    serverAlbumCount ??= server.serverAlbumCount;
  }

  @override
  Future<void> load() async {
    if (completer == null) {
      completer = Completer<void>();

      // the biography lives behind a separate endpoint; start it now so it
      // arrives while the albums below are still loading
      final biographyFuture = biographyLoaded
          ? null
          : streamClient?.getArtistInfo(this);

      if (sourceType == .navidrome || sourceType == .feiniu) {
        final albums = await streamClient?.getArtistAlbumList(id!);
        if (albums != null) {
          albumList.addAll(albums);
          for (final album in albumList) {
            await album.load();
            if (sourceType == .navidrome) {
              songList.addAll(album.songList);
            }
            changeNotifier.value++;
          }
        }
        if (sourceType == .feiniu) {
          songList.addAll(await streamClient?.getArtistSongs(id!) ?? []);
          changeNotifier.value++;
        }
      } else {
        songList.addAll(await streamClient?.getArtistSongs(id!) ?? []);
        changeNotifier.value++;
      }

      if (biographyFuture != null) {
        try {
          await biographyFuture;
        } catch (_) {
          // a missing biography must not break the artist page
        }
        // only remember the attempt once it succeeded, so an offline start
        // does not permanently lose the biography
        biographyLoaded = biography != null;
        changeNotifier.value++;
      }

      completer!.complete();
      return;
    }
  }
}

class Album extends ArtistAlbumBase {
  Album(String name, {super.id, super.coverArtId, this.year, this.created})
    : super(name: name, isArtist: false);

  /// This album's songs grouped by artist name, filled by [sort].
  Map<String, List<MyAudioMetadata>> artist2SongList = {};
  int? year;

  /// Creation time reported by the server, only available for stream sources.

  /// Guards [load] so the server is only asked once per album.
  Completer<void>? completer;
  DateTime? created;

  DateTime? _addedTime;
  bool _addedTimeReady = false;

  /// When this album entered the library.
  ///
  /// Local and WebDAV libraries have no creation time, so the newest file
  /// modification time among the album's songs is used instead. The result is
  /// cached because it is read while sorting the whole album list.
  DateTime? get addedTime {
    if (_addedTimeReady) {
      return _addedTime;
    }
    _addedTimeReady = true;

    if (created != null) {
      return _addedTime = created;
    }

    DateTime? latest;
    for (final song in songList) {
      final modified = song.modified;
      if (modified != null && (latest == null || modified.isAfter(latest))) {
        latest = modified;
      }
    }
    return _addedTime = latest;
  }

  int _sort(MyAudioMetadata a, MyAudioMetadata b) {
    final discA = a.disc ?? 9999;
    final discB = b.disc ?? 9999;

    final discCompare = discA.compareTo(discB);
    if (discCompare != 0) return discCompare;

    final trackA = a.track ?? 9999;
    final trackB = b.track ?? 9999;

    return trackA.compareTo(trackB);
  }

  void sort() {
    songList.sort((a, b) => _sort(a, b));
    for (final song in songList) {
      for (String artistName in getArtists(getArtist(song))) {
        final tmp = artist2SongList.putIfAbsent(artistName, () => []);
        tmp.add(song);
      }
    }
  }

  @override
  Future<void> load() async {
    if (completer == null) {
      // ensure load one time
      completer = Completer<void>();
      songList.addAll(await streamClient?.getAlbumSongs(id!) ?? []);
      completer!.complete();
      return;
    }
    return completer!.future;
  }
}
