import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:sylvakru/base/data/setting.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:sylvakru/base/app.dart';
import 'package:sylvakru/base/data/config.dart';
import 'package:sylvakru/base/services/logger.dart';
import 'package:sylvakru/base/utils/path.dart';

/// A service whose OpenAI-compatible endpoint is well known.
///
/// Picking one fills the address and offers its usual models, so nobody has to
/// look either up; 自定义 leaves both fields to the listener.
class TranslationProviderPreset {
  const TranslationProviderPreset({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.models,
  });

  final String id;
  final String name;
  final String baseUrl;
  final List<String> models;
}

const translationProviders = <TranslationProviderPreset>[
  TranslationProviderPreset(
    id: 'deepseek',
    name: 'DeepSeek',
    baseUrl: 'https://api.deepseek.com/v1',
    models: ['deepseek-chat', 'deepseek-reasoner'],
  ),
  TranslationProviderPreset(
    id: 'zhipu',
    name: '智谱 GLM',
    baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
    models: ['glm-4-flash', 'glm-4-plus'],
  ),
  TranslationProviderPreset(
    id: 'dashscope',
    name: '通义千问',
    baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    models: ['qwen-plus', 'qwen-turbo', 'qwen-max'],
  ),
  TranslationProviderPreset(
    id: 'moonshot',
    name: 'Moonshot',
    baseUrl: 'https://api.moonshot.cn/v1',
    models: ['moonshot-v1-8k'],
  ),
  TranslationProviderPreset(
    id: 'openai',
    name: 'OpenAI',
    baseUrl: 'https://api.openai.com/v1',
    models: ['gpt-4o-mini', 'gpt-4o'],
  ),
  TranslationProviderPreset(
    id: 'ollama',
    name: '本地 Ollama',
    baseUrl: 'http://localhost:11434/v1',
    models: ['qwen2.5', 'llama3.1'],
  ),
  TranslationProviderPreset(id: 'custom', name: '自定义', baseUrl: '', models: []),
];

/// The preset [id] names, or 自定义 when it is unknown or empty.
TranslationProviderPreset translationProviderFor(String id) {
  for (final provider in translationProviders) {
    if (provider.id == id) {
      return provider;
    }
  }
  return translationProviders.last;
}

/// The preset whose address matches [baseUrl], so a picker filled by hand still
/// shows the right service.
TranslationProviderPreset translationProviderForUrl(String baseUrl) {
  String trim(String value) => value.trim().replaceAll(RegExp(r'/+$'), '');
  for (final provider in translationProviders) {
    if (provider.baseUrl.isNotEmpty &&
        trim(provider.baseUrl) == trim(baseUrl)) {
      return provider;
    }
  }
  return translationProviders.last;
}

/// The URL a request goes to.
///
/// [TranslationEndpointStyle.chatCompletions] appends the path to a service
/// root; [TranslationEndpointStyle.exactUrl] takes the address as it is, which
/// is what providers documenting one full URL need.
String translationEndpoint(TranslationSettings settings) {
  final trimmed = settings.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
  switch (settings.endpointStyle) {
    case TranslationEndpointStyle.exactUrl:
      return settings.baseUrl.trim();
    case TranslationEndpointStyle.chatCompletions:
      if (trimmed.endsWith('/chat/completions')) {
        return trimmed;
      }
      return '$trimmed/chat/completions';
  }
}

/// What a translation request needs to know about the chosen service.
///
/// A plain record so the request body and the cache key are pure functions a
/// test can call without a settings file.
class TranslationSettings {
  const TranslationSettings({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    required this.endpointStyle,
    required this.target,
  });

  final String baseUrl;
  final String apiKey;
  final String model;
  final String target;

  /// Whether the address is a service root or the full endpoint.
  final TranslationEndpointStyle endpointStyle;

  /// Whether there is enough here to make a request at all.
  bool get isConfigured =>
      baseUrl.trim().isNotEmpty &&
      model.trim().isNotEmpty &&
      apiKey.trim().isNotEmpty;
}

/// The body for any OpenAI-compatible chat endpoint.
///
/// temperature 0 because a translation is no place for creativity, and the
/// system message asks for the translation alone so the answer can be shown
/// unchanged. Proper nouns are left alone: an artist's name is not translated
/// on a record sleeve.
Map<String, dynamic> buildTranslationRequest({
  required String text,
  required TranslationSettings settings,
}) {
  return {
    'model': settings.model,
    'temperature': 0,
    'messages': [
      {
        'role': 'system',
        'content':
            'You are a translator. Translate the user message into '
            '${settings.target}. Leave proper nouns (artist, album and song '
            'names) as they are, keep the paragraph structure, and reply with '
            'the translation only — no quotes, no notes, no language labels.',
      },
      {'role': 'user', 'content': text},
    ],
  };
}

/// Pulls the answer out of a chat completion, or null when the shape is not
/// what was asked for.
String? parseTranslationResponse(dynamic data) {
  try {
    final content = data['choices'][0]['message']['content'];
    if (content is! String) {
      return null;
    }
    final text = content.trim();
    return text.isEmpty ? null : text;
  } catch (error) {
    return null;
  }
}

/// Translates text through the service the listener configured, remembering
/// every answer.
///
/// The app ships no translation of its own: it points at an OpenAI-compatible
/// endpoint the listener already has (DeepSeek, Qwen, GLM, OpenAI, a local
/// Ollama). Everything is best effort — no key, a dead endpoint or a slow
/// answer all end in "show the original", never in a broken page.
class Translator {
  /// Replaced only by tests: the real path needs a network.
  Future<String?> Function(String text)? request;

  final Map<String, String> _cache = {};
  final Map<String, Future<String?>> _inFlight = {};
  bool _cacheLoaded = false;
  File? _file;

  File get _cacheFile =>
      _file ??= File('${appSupportDir.path}/translations.json');

  /// The current settings, read from the app's own notifiers.
  TranslationSettings get settings => TranslationSettings(
    baseUrl: translationBaseUrlNotifier.value,
    apiKey: config.translationApiKey ?? '',
    model: translationModelNotifier.value,
    target: translationTargetNotifier.value,
    endpointStyle: translationEndpointStyleNotifier.value,
  );

  bool get isEnabled =>
      translationEnabledNotifier.value && settings.isConfigured;

  /// Number of remembered translations, for the settings panel.
  int get cachedCount => _cache.length;

  /// The translation of [text], or null when there is nothing to show or
  /// nothing answered.
  Future<String?> translate(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || !isEnabled) {
      return null;
    }

    final current = settings;
    final key = _cacheKey(trimmed, current);
    await _loadCache();

    final cached = _cache[key];
    if (cached != null) {
      return cached;
    }

    final running = _inFlight[key];
    if (running != null) {
      return running;
    }

    final future = _askAndRemember(key, trimmed, current);
    _inFlight[key] = future;
    try {
      return await future;
    } finally {
      _inFlight.remove(key);
    }
  }

  /// Forgets every remembered translation; the next page asks again.
  Future<void> clearCache() async {
    _cache.clear();
    _inFlight.clear();
    _cacheLoaded = true;
    final file = _cacheFile;
    try {
      if (file.existsSync()) {
        await file.delete();
      }
    } catch (error) {
      logger.output('Failed to clear the translation cache: $error');
    }
  }

  Future<String?> _askAndRemember(
    String key,
    String text,
    TranslationSettings current,
  ) async {
    try {
      final answer = request != null
          ? await request!(text)
          : await _askService(text, current);
      if (answer == null || answer.trim().isEmpty) {
        return null;
      }
      final translation = answer.trim();
      _cache[key] = translation;
      // Not awaited: the translation is ready, and writing the cache file is
      // housekeeping that must not hold up the page.
      unawaited(_saveCache());
      return translation;
    } catch (error) {
      logger.output('Translation failed: $error');
      return null;
    }
  }

  Future<String?> _askService(String text, TranslationSettings current) async {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 60),
      ),
    );

    final response = await dio.post(
      translationEndpoint(current),
      data: buildTranslationRequest(text: text, settings: current),
      options: Options(
        headers: {
          'Authorization': 'Bearer ${current.apiKey}',
          'Content-Type': 'application/json',
        },
      ),
    );

    return parseTranslationResponse(response.data);
  }

  String _cacheKey(String text, TranslationSettings current) {
    return md5
        .convert(utf8.encode('${current.target}|${current.model}|$text'))
        .toString();
  }

  Future<void> _loadCache() async {
    if (_cacheLoaded) {
      return;
    }
    _cacheLoaded = true;
    final file = _cacheFile;
    try {
      if (!file.existsSync()) {
        return;
      }
      final map = await readJsonMapFile(file);
      for (final entry in map.entries) {
        final value = entry.value;
        if (value is String) {
          _cache[entry.key] = value;
        }
      }
    } catch (error) {
      logger.output('Failed to read the translation cache: $error');
    }
  }

  Future<void> _saveCache() async {
    final file = _cacheFile;
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(_cache));
    } catch (error) {
      logger.output('Failed to write the translation cache: $error');
    }
  }
}

final translator = Translator();
