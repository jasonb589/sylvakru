import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:sylvakru/base/data/playlist.dart';
import 'package:sylvakru/base/data/artist_album.dart';
import 'package:sylvakru/base/my_audio_metadata.dart';

StreamClient? streamClient;

abstract class StreamClient {
  final String baseUrl;
  final String username;
  final String password;

  @protected
  late final Dio dio;

  StreamClient({
    required this.baseUrl,
    required this.username,
    required this.password,
  });

  @protected
  List<Map<String, dynamic>>? normalize(dynamic data) {
    if (data == null) {
      return null;
    }
    return (data as List).cast();
  }

  Future<bool> ping();

  Future<int> getSongCount() async {
    return 0;
  }


  /// Searches the server for songs matching [query].
  ///
  /// Server-side search is what the song list's search box uses, so it works
  /// across the whole library rather than only what has been loaded.
  Future<List<MyAudioMetadata>?> searchSongs(
    String query,
    int size,
    int offset,
  );
  Future<List<MyAudioMetadata>?> getSongs(int size, int offset);

  Future<List<Artist>?> getArtistList();

  Future<List<Album>?> getArtistAlbumList(String id);

  Future<List<MyAudioMetadata>?> getArtistSongs(String id);

  /// Extra metadata for one artist (biography, album count, artist photo).
  ///
  /// Sources without such data return null; the caller keeps whatever it has.
  /// This is what lets the artist page show a Last.fm portrait instead of the
  /// first album's square cover.
  Future<Artist?> getArtistInfo(Artist artist) async => null;

  Future<List<Album>?> getAlbumList(
    int offset, {
    String type,
    bool descending = false,
  });

  Future<Album?> getAlbum(String id);

  Future<List<MyAudioMetadata>?> getAlbumSongs(String id);

  // The play queue is persisted locally now (see audio_handler's
  // _savePlayQueueState), so it is no longer stored as a server playlist.

  Future<List<MyAudioMetadata>?> getStarredSongs();

  Future<bool> updateStarredSongs(List<String> songIds);

  Future<List<Playlist>?> getPlaylists();

  Future<String?> createPlaylist(String name);

  Future<bool> deletePlaylist(String playlistId);

  Future<List<MyAudioMetadata>?> getPlaylistSongs(String playlistId);

  Future<bool> updatePlaylistSongs(String playlistId, List<String> songIds);

  String getStreamUrl(String id);

  Map<String, String>? get headers => null;

  Future<Uint8List?> getPictureBytes(String songId);

  Future<String> getLyricsById(String songId);

  Future<bool> downloadSong(String songId, String savePath);

  Future<bool> scrobble(String songId);
}
