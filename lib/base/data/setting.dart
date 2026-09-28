import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:sylvakru/base/audio_handler.dart';
import 'package:sylvakru/base/services/color_manager.dart';
import 'package:sylvakru/base/services/interaction.dart';
import 'package:sylvakru/base/widgets/lyric_list_view.dart';
import 'package:sylvakru/base/app.dart';
import 'package:sylvakru/base/utils/path.dart';
import 'package:sylvakru/base/widgets/manage_music_folders.dart';
import 'package:sylvakru/portrait_view/portrait_view.dart';

final artistsIsListViewNotifier = ValueNotifier(true);
final artistsIsAscendingNotifier = ValueNotifier(true);
final artistsUseLargePictureNotifier = ValueNotifier(false);
final artistsRandomizeNotifier = ValueNotifier(false);

final albumsIsAscendingNotifier = ValueNotifier(true);
final albumsUseLargePictureNotifier = ValueNotifier(false);
final albumsRandomizeNotifier = ValueNotifier(false);

final playlistsUseLargePictureNotifier = ValueNotifier(true);

final exitOnCloseNotifier = ValueNotifier(false);

/// Upper bound for user-managed offline music, in MB. 0 means "no limit".
/// The persisted key remains `cacheLimitMb` for settings migration compatibility.
final offlineMusicLimitMbNotifier = ValueNotifier<int>(0);

/// How downloads are named inside the downloads folder.
///
/// The name is derived from the song rather than stored, so switching the
/// setting renames files instead of losing track of what is downloaded.
final downloadNamingNotifier = ValueNotifier<DownloadNaming>(
  DownloadNaming.hash,
);

/// Whether a finished download gets the library's tags written onto it, so the
/// file still makes sense in a player that never heard of this app.
final writeDownloadTagsNotifier = ValueNotifier<bool>(true);

/// Below this much free space the reminder shows up, in MB.
///
/// Zero turns it off. It is a reminder and nothing more: a download the
/// listener asked for is never blocked by a line they drew themselves.
final diskSpaceWarnMbNotifier = ValueNotifier<int>(1024);

/// The values the reminder picker offers.
const diskSpaceWarnOptionsMb = [0, 512, 1024, 2048, 5120, 10240];

/// How the address is turned into a request URL.
///
/// Providers document one of two shapes: a service root that the client
/// appends `/chat/completions` to, or the full endpoint in one string. Both
/// are accepted; this says which one the address is.
final translationEndpointStyleNotifier =
    ValueNotifier<TranslationEndpointStyle>(
      TranslationEndpointStyle.chatCompletions,
    );

/// The service the listener picked, remembered so the panel can show it again.
/// Only the id: the address and the model stay separate settings they can edit.
final translationProviderNotifier = ValueNotifier<String>('');

/// How an OpenAI-compatible endpoint is addressed.
enum TranslationEndpointStyle {
  /// The address is a service root; `/chat/completions` is appended.
  chatCompletions,

  /// The address is the complete request URL, used unchanged.
  exactUrl,
}

/// Translation of the text a server sends — today the artist biography.
///
/// Off by default: switching it on sends that text to a service the listener
/// chooses, which is a decision to make deliberately rather than to discover.
final translationEnabledNotifier = ValueNotifier<bool>(false);
final translationBaseUrlNotifier = ValueNotifier<String>('');
final translationModelNotifier = ValueNotifier<String>('');
final translationTargetNotifier = ValueNotifier<String>('简体中文');

/// Set once the pass that moves playback cache out of the downloads folder has
/// run, so a file the listener never downloaded cannot be mistaken for theirs.
bool downloadSplitRepaired = false;

/// Playback speed for the whole client; 1.0 is untouched. The player is asked
/// for this on every track change, so a speed set once survives the next song.
final playbackRateNotifier = ValueNotifier<double>(1.0);

/// The speeds the picker offers. Clamping to this range keeps a corrupt setting
/// file from asking the player for something it cannot do.
const playbackRateOptions = <double>[0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 2.5, 3];

double clampPlaybackRate(double rate) =>
    rate.clamp(playbackRateOptions.first, playbackRateOptions.last).toDouble();

final setting = Setting();

const offlineMusicLimitOptionsMb = [0, 1024, 2048, 5120, 10240];

class Setting {
  /// Resolved from [appSupportDir] on every access: loading twice has to be
  /// harmless (a second run, or a test that points the app somewhere else),
  /// which a `late final` field cannot promise.
  File get file => File("${appSupportDir.path}/setting.json");

  Future<void> load() async {
    initFile(file, false);

    final json = await readJsonMapFile(file);

    artistsIsListViewNotifier.value =
        json['artistsIsList'] as bool? ?? artistsIsListViewNotifier.value;

    artistsIsAscendingNotifier.value =
        json['artistsIsAscend'] as bool? ?? artistsIsAscendingNotifier.value;

    artistsUseLargePictureNotifier.value =
        json['artistsUseLargePicture'] as bool? ??
        artistsUseLargePictureNotifier.value;

    albumsIsAscendingNotifier.value =
        json['albumsIsAscend'] as bool? ?? albumsIsAscendingNotifier.value;

    albumsUseLargePictureNotifier.value =
        json['albumsUseLargePicture'] as bool? ??
        albumsUseLargePictureNotifier.value;

    playlistsUseLargePictureNotifier.value =
        json['playlistsUseLargePicture'] as bool? ??
        playlistsUseLargePictureNotifier.value;

    endDrawerNotifier.value = json['endDrawer'] as bool? ?? false;

    vibrationOnNoitifier.value =
        json['vibrationOn'] as bool? ?? vibrationOnNoitifier.value;

    final languageCode = json['language'] as String? ?? '';

    if (languageCode.isNotEmpty) {
      localeNotifier.value = Locale(languageCode);
    }

    immersiveWideLayoutNotifier.value =
        json['immersiveWideLayout'] as bool? ?? true;

    autoPlayOnStartupNotifier.value =
        json['autoPlayOnStartup'] as bool? ?? false;

    if (isPremiumNotifier.value) {
      fontFamilyNotifier.value = json['fontFamily'] as String?;
    }

    mainPageThemeNotifier.value = ThemeType.values.firstWhere(
      (e) => e.name == json['mainPageTheme'],
      orElse: () => ThemeType.vivid,
    );

    if (!isPremiumNotifier.value && mainPageThemeNotifier.value == .vivid) {
      mainPageThemeNotifier.value = .light;
    }

    updateHoverFocusColor();

    lyricsPageThemeNotifier.value = ThemeType.values.firstWhere(
      (e) => e.name == json['lyricsPageTheme'],
      orElse: () => ThemeType.vivid,
    );

    lyricsFontSizeOffsetNotifier.value =
        json['lyricsFontSizeOffset'] as double? ??
        lyricsFontSizeOffsetNotifier.value;

    exitOnCloseNotifier.value =
        json['exitOnClose'] as bool? ?? exitOnCloseNotifier.value;

    recursiveScanNotifier.value = json['recursiveScan'] as bool? ?? false;

    offlineMusicLimitMbNotifier.value =
        (json['cacheLimitMb'] as num?)?.toInt() ??
        offlineMusicLimitMbNotifier.value;

    playbackRateNotifier.value = clampPlaybackRate(
      json['playbackRate'] as double? ?? playbackRateNotifier.value,
    );

    lyricsTimeOffsetNotifier.value =
        (json['lyricsTimeOffsetMs'] as num?)?.toInt() ??
        lyricsTimeOffsetNotifier.value;

    downloadRootDir = json['downloadDir'] as String? ?? downloadRootDir;

    downloadNamingNotifier.value = DownloadNaming.values.firstWhere(
      (naming) => naming.name == json['downloadNaming'],
      orElse: () => DownloadNaming.hash,
    );

    writeDownloadTagsNotifier.value =
        json['writeDownloadTags'] as bool? ?? writeDownloadTagsNotifier.value;

    diskSpaceWarnMbNotifier.value =
        (json['diskSpaceWarnMb'] as num?)?.toInt() ??
        diskSpaceWarnMbNotifier.value;

    translationEnabledNotifier.value =
        json['translationEnabled'] as bool? ?? translationEnabledNotifier.value;

    translationBaseUrlNotifier.value =
        json['translationBaseUrl'] as String? ??
        translationBaseUrlNotifier.value;

    translationModelNotifier.value =
        json['translationModel'] as String? ?? translationModelNotifier.value;

    translationTargetNotifier.value =
        json['translationTarget'] as String? ?? translationTargetNotifier.value;

    downloadSplitRepaired =
        json['downloadSplitRepaired'] as bool? ?? downloadSplitRepaired;
  }

  void save() {
    file.writeAsStringSync(
      jsonEncode({
        'artistsIsList': artistsIsListViewNotifier.value,
        'artistsIsAscend': artistsIsAscendingNotifier.value,
        'artistsUseLargePicture': artistsUseLargePictureNotifier.value,

        'albumsIsAscend': albumsIsAscendingNotifier.value,
        'albumsUseLargePicture': albumsUseLargePictureNotifier.value,

        'playlistsUseLargePicture': playlistsUseLargePictureNotifier.value,

        'endDrawer': endDrawerNotifier.value,

        'vibrationOn': vibrationOnNoitifier.value,
        'language': localeNotifier.value?.languageCode,

        'immersiveWideLayout': immersiveWideLayoutNotifier.value,
        'autoPlayOnStartup': autoPlayOnStartupNotifier.value,

        'fontFamily': fontFamilyNotifier.value,

        'mainPageTheme': mainPageThemeNotifier.value.name,
        'lyricsPageTheme': lyricsPageThemeNotifier.value.name,
        'lyricsFontSizeOffset': lyricsFontSizeOffsetNotifier.value,
        'exitOnClose': exitOnCloseNotifier.value,

        'recursiveScan': recursiveScanNotifier.value,
        'cacheLimitMb': offlineMusicLimitMbNotifier.value,
        'playbackRate': playbackRateNotifier.value,
        'lyricsTimeOffsetMs': lyricsTimeOffsetNotifier.value,
        'downloadDir': downloadRootDir,
        'downloadSplitRepaired': downloadSplitRepaired,
        'downloadNaming': downloadNamingNotifier.value.name,
        'writeDownloadTags': writeDownloadTagsNotifier.value,
        'diskSpaceWarnMb': diskSpaceWarnMbNotifier.value,
        'translationEnabled': translationEnabledNotifier.value,
        'translationBaseUrl': translationBaseUrlNotifier.value,
        'translationModel': translationModelNotifier.value,
        'translationTarget': translationTargetNotifier.value,
      }),
    );
  }
}
