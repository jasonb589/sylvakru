import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sylvakru/base/app.dart';
import 'package:sylvakru/base/services/emby_client.dart';
import 'package:sylvakru/base/services/feiniu_client.dart';
import 'package:sylvakru/base/services/logger.dart';
import 'package:sylvakru/base/services/navidrome_client.dart';
import 'package:sylvakru/base/services/stream_client.dart';
import 'package:sylvakru/base/services/webdav_client.dart';
import 'package:sylvakru/base/utils/path.dart';
import 'package:sylvakru/layer/premium_layer.dart';

final config = Config();

class Config {
  late final File file;

  String? navidromeBaseUrl;
  String? navidromeUsername;
  String? navidromePassword;

  String? embyBaseUrl;
  String? embyUsername;
  String? embyPassword;

  String? feiniuBaseUrl;
  String? feiniuUsername;
  String? feiniuPassword;
  String? feiniuToken;

  static const _secureStorage = FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );

  Future<void> load() async {
    if (kReleaseMode && Platform.isIOS) {
      final isPremiumTmp = await _trySecureRead('isPremium');
      if (isPremiumTmp != 'true') {
        isPremiumNotifier.value = false;
        final now = DateTime.now();
        try {
          final trialBeginMs = await _secureStorage.read(key: 'trialBeginMs');
          if (trialBeginMs == null) {
            if (await _trySecureWrite(
              'trialBeginMs',
              now.millisecondsSinceEpoch.toString(),
            )) {
              trialRemainingMinNotifier.value = 4320; // 3 days
            }
          } else {
            final trialBeginTime = DateTime.fromMillisecondsSinceEpoch(
              int.tryParse(trialBeginMs) ?? 0,
            );
            final diff = now.difference(trialBeginTime);
            if (diff.inMinutes < 4320) {
              trialRemainingMinNotifier.value = 4320 - diff.inMinutes;
            }
          }
          if (trialRemainingMinNotifier.value > 0) {
            isPremiumNotifier.value = true;
            Timer.periodic(Duration(minutes: 1), (timer) {
              if (trialRemainingMinNotifier.value <= 0) {
                timer.cancel();
                return;
              }
              trialRemainingMinNotifier.value--;
            });
          }
        } catch (e) {
          logger.output(e.toString());
        }
      }

      if (!isPremiumNotifier.value) {
        viewModeNotifier.value = .normal;
      }
    }

    file = File("${appSupportDir.path}/config.json");
    if (!(file.existsSync())) {
      return;
    }

    final map = await readJsonMapFile(file);

    Map<String, dynamic>? asConfigMap(dynamic value) {
      if (value is Map<String, dynamic>) {
        return value;
      }
      if (value is Map) {
        return value.map((key, value) => MapEntry(key.toString(), value));
      }
      return null;
    }
    final webdavMap = asConfigMap(map['webdav']);
    if (webdavMap != null &&
        webdavMap['baseUrl'] is String &&
        webdavMap['username'] is String) {
      String? securePassword = await _trySecureRead('webdav_password');
      securePassword ??= webdavMap['password'] is String
          ? webdavMap['password'] as String
          : '';
      webdavClient = WebDavClient(
        baseUrl: webdavMap['baseUrl'] as String,
        username: webdavMap['username'] as String,
        password: securePassword,
      );
    }

    final navidromeMap = asConfigMap(map['navidrome']);
    if (navidromeMap != null &&
        navidromeMap['baseUrl'] is String &&
        navidromeMap['username'] is String) {
      navidromeBaseUrl = navidromeMap['baseUrl'] as String;
      navidromeUsername = navidromeMap['username'] as String;
      navidromePassword = await _trySecureRead('navidrome_password');
      navidromePassword ??= navidromeMap['password'] is String
          ? navidromeMap['password'] as String
          : '';
    }

    final embyMap = asConfigMap(map['emby']);
    if (embyMap != null &&
        embyMap['baseUrl'] is String &&
        embyMap['username'] is String) {
      embyBaseUrl = embyMap['baseUrl'] as String;
      embyUsername = embyMap['username'] as String;
      embyPassword = await _trySecureRead('emby_password');
      embyPassword ??= embyMap['password'] is String
          ? embyMap['password'] as String
          : '';
    }

    final feiniuMap = asConfigMap(map['feiniu']);
    if (feiniuMap != null &&
        feiniuMap['baseUrl'] is String &&
        feiniuMap['username'] is String) {
      feiniuBaseUrl = feiniuMap['baseUrl'] as String;
      feiniuUsername = feiniuMap['username'] as String;
      feiniuPassword = await _trySecureRead('feiniu_password');
      feiniuPassword ??= feiniuMap['password'] is String
          ? feiniuMap['password'] as String
          : '';

      feiniuToken = null;
      if (feiniuMap['nasLogin'] == true) {
        feiniuToken = feiniuMap['token'] is String
            ? feiniuMap['token'] as String
            : await _trySecureRead('feiniu_token');
      }
    }

    final configuredSourceType = map['sourceType'];
    final tmpSourceType = configuredSourceType is String
        ? configuredSourceType
        : null;
    if (tmpSourceType != null) {
      sourceType = SourceType.values.firstWhere(
        (e) => e.name == tmpSourceType,
        orElse: () => .local,
      );
    } else {
      if (webdavClient != null) {
        sourceType = .webdav;
      } else if (navidromeMap != null) {
        sourceType = .navidrome;
      } else if (embyMap != null) {
        sourceType = .emby;
      } else if (feiniuMap != null) {
        sourceType = .feiniu;
      }
    }

    if ((sourceType == .webdav && webdavClient == null) ||
        (sourceType == .navidrome && navidromeBaseUrl == null) ||
        (sourceType == .emby && embyBaseUrl == null) ||
        (sourceType == .feiniu && feiniuBaseUrl == null)) {
      sourceType = .local;
    }

    isStreamSource =
        sourceType == .navidrome ||
        sourceType == .emby ||
        sourceType == .feiniu;
    isNotStreamSource = !isStreamSource;

    if (sourceType == .navidrome && navidromeMap != null) {
      streamClient = NavidromeClient(
        baseUrl: navidromeBaseUrl!,
        username: navidromeUsername!,
        password: navidromePassword!,
      );
    } else if (sourceType == .emby && embyMap != null) {
      streamClient = EmbyClient(
        baseUrl: embyBaseUrl!,
        username: embyUsername!,
        password: embyPassword!,
      );
    } else if (sourceType == .feiniu && feiniuMap != null) {
      streamClient = FeiniuClient(
        baseUrl: feiniuBaseUrl!,
        username: feiniuUsername!,
        password: feiniuPassword!,
        token: feiniuToken,
      );
    }

    if (_hasPlainTextCredential(map)) {
      await save();
    }
  }

  Future<void> savePremium() async {
    await _trySecureWrite('isPremium', 'true');
  }

  Future<void> save() async {
    // Secure storage (keyring/Keychain) can fail to write - e.g. no Secret
    // Service running on some Linux setups - and previously that failure was
    // silently ignored while the plaintext password was still stripped from
    // config.json, permanently losing the credential on the next load. Keep
    // the plaintext as a fallback in that one field until a write actually
    // succeeds, instead of losing it outright.
    bool webdavSecured = true;
    bool navidromeSecured = true;
    bool embySecured = true;
    bool feiniuSecured = true;
    bool feiniuTokenSecured = true;

    if (webdavClient != null) {
      webdavSecured = await _trySecureWrite(
        'webdav_password',
        webdavClient!.password,
      );
    }

    if (navidromePassword != null) {
      navidromeSecured = await _trySecureWrite(
        'navidrome_password',
        navidromePassword!,
      );
    }

    if (embyPassword != null) {
      embySecured = await _trySecureWrite('emby_password', embyPassword!);
    }

    if (feiniuPassword != null) {
      feiniuSecured = await _trySecureWrite('feiniu_password', feiniuPassword!);
    }
    if (feiniuToken != null && feiniuBaseUrl != null) {
      feiniuTokenSecured = await _trySecureWrite('feiniu_token', feiniuToken!);
    } else {
      try {
        await _secureStorage.delete(key: 'feiniu_token');
      } catch (e) {
        logger.output(
          'Failed to delete "feiniu_token" from secure storage: $e',
        );
      }
    }

    await file.writeAsString(
      jsonEncode({
        'sourceType': sourceType.name,

        if (webdavClient != null)
          'webdav': {
            'baseUrl': webdavClient!.baseUrl,
            'username': webdavClient!.username,
            if (!webdavSecured) 'password': webdavClient!.password,
          },

        if (navidromeBaseUrl != null)
          'navidrome': {
            'baseUrl': navidromeBaseUrl,
            'username': navidromeUsername,
            if (!navidromeSecured) 'password': navidromePassword,
          },

        if (embyBaseUrl != null)
          'emby': {
            'baseUrl': embyBaseUrl,
            'username': embyUsername,
            if (!embySecured) 'password': embyPassword,
          },

        if (feiniuBaseUrl != null)
          'feiniu': {
            'baseUrl': feiniuBaseUrl,
            'username': feiniuUsername,
            if (!feiniuSecured) 'password': feiniuPassword,
            if (feiniuToken != null) 'nasLogin': true,
            if (feiniuToken != null && !feiniuTokenSecured)
              'token': feiniuToken,
          },
      }),
    );
  }

  Future<String?> _trySecureRead(String key) async {
    try {
      return await _secureStorage.read(key: key);
    } catch (e) {
      logger.output('Failed to read "$key" from secure storage: $e');
      return null;
    }
  }

  Future<bool> _trySecureWrite(String key, String value) async {
    try {
      await _secureStorage.write(key: key, value: value);
      return true;
    } catch (e) {
      logger.output('Failed to write "$key" to secure storage: $e');
      return false;
    }
  }

  bool _hasPlainTextCredential(Map<String, dynamic> map) {
    for (var key in ['webdav', 'navidrome', 'emby', 'feiniu']) {
      final sourceConfig = map[key];
      if (sourceConfig is Map && sourceConfig['password'] != null) {
        return true;
      }
    }
    final feiniuConfig = map['feiniu'];
    return feiniuConfig is Map && feiniuConfig['token'] != null;
  }
}
