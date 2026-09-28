import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sylvakru/base/app.dart';
import 'package:sylvakru/base/data/artist_album.dart';
import 'package:sylvakru/base/data/config.dart';
import 'package:sylvakru/base/data/setting.dart';
import 'package:sylvakru/base/services/translation.dart';
import 'package:sylvakru/base/services/logger.dart';
import 'package:sylvakru/base/widgets/artist_metadata.dart';
import 'package:sylvakru/l10n/generated/app_localizations.dart';

/// Translation is best effort by design: it needs a service the listener
/// configured, it must never slow a page down or break it, and it must not ask
/// the same text twice — a biography costs money every time it is sent.
void main() {
  setUpAll(() async {
    appSupportDir = Directory.systemTemp.createTempSync('sylvakru_translate');
    await logger.init();
  });

  setUp(() async {
    await setting.load();
    translationEnabledNotifier.value = true;
    translationBaseUrlNotifier.value = 'https://api.example.test/v1';
    translationModelNotifier.value = 'test-model';
    config.translationApiKey = 'test-key';
    translator.request = null;
    await translator.clearCache();
  });

  tearDown(() {
    translator.request = null;
    translationEnabledNotifier.value = false;
  });

  test('the request body asks for the translation and nothing else', () {
    const settings = TranslationSettings(
      baseUrl: 'https://api.example.test/v1',
      apiKey: 'key',
      model: 'test-model',
      target: '简体中文',
      endpointStyle: TranslationEndpointStyle.chatCompletions,
    );

    final body = buildTranslationRequest(
      text: 'Ejel is a singer.',
      settings: settings,
    );

    expect(body['model'], 'test-model');
    expect(body['temperature'], 0);
    final messages = body['messages'] as List;
    expect(messages.length, 2);
    expect((messages[0] as Map)['content'], contains('简体中文'));
    expect((messages[1] as Map)['content'], 'Ejel is a singer.');
  });

  test('the answer is read out of a chat completion', () {
    expect(
      parseTranslationResponse({
        'choices': [
          {
            'message': {'content': ' 艾杰尔是一名歌手。 '},
          },
        ],
      }),
      '艾杰尔是一名歌手。',
    );
    expect(parseTranslationResponse({'choices': []}), isNull);
    expect(parseTranslationResponse('not a map'), isNull);
  });

  test('nothing is sent while the service is not configured', () async {
    var calls = 0;
    translator.request = (text) async {
      calls++;
      return '译文';
    };
    config.translationApiKey = '';

    expect(await translator.translate('hello'), isNull);
    expect(calls, 0);

    config.translationApiKey = 'test-key';
    translationEnabledNotifier.value = false;
    expect(await translator.translate('hello'), isNull);
    expect(calls, 0);
  });

  test('a translation is remembered instead of asked twice', () async {
    var calls = 0;
    translator.request = (text) async {
      calls++;
      return '译文：$text';
    };

    expect(await translator.translate('hello'), '译文：hello');
    expect(await translator.translate('hello'), '译文：hello');
    expect(calls, 1);

    await translator.clearCache();
    expect(await translator.translate('hello'), '译文：hello');
    expect(calls, 2);
  });

  test('a failing service answers nothing rather than throwing', () async {
    translator.request = (text) async => throw StateError('offline');

    expect(await translator.translate('hello'), isNull);

    translator.request = (text) async => '';
    expect(await translator.translate('hello'), isNull);
  });

  testWidgets('the biography block shows the translation and can go back', (
    tester,
  ) async {
    translator.request = (text) async => '翻译后的简介';
    final artist = Artist('Ejel', id: 'ar-1')
      ..biography = 'A singer from Seoul.';

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: ArtistMetadata(artist: artist)),
      ),
    );
    // The translation is requested from initState; give the future a couple
    // of frames to arrive before looking for it.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    // One more frame for the rebuild the translation asked for.
    await tester.pump();

    // The service is asked once; if this fails the problem is earlier than the
    // rendering, which is what makes the next line worth reading.
    expect(translator.cachedCount, 1);
    expect(find.textContaining('翻译后的简介'), findsOneWidget);

    await tester.tap(find.textContaining('Show original'));
    await tester.pumpAndSettle();

    expect(find.textContaining('A singer from Seoul.'), findsOneWidget);
    expect(find.textContaining('翻译后的简介'), findsNothing);
  });

  test('the address and the format decide the endpoint', () {
    const root = TranslationSettings(
      baseUrl: 'https://api.example.test/v1/',
      apiKey: 'key',
      model: 'test-model',
      target: '简体中文',
      endpointStyle: TranslationEndpointStyle.chatCompletions,
    );
    expect(
      translationEndpoint(root),
      'https://api.example.test/v1/chat/completions',
    );

    const exact = TranslationSettings(
      baseUrl: 'https://api.example.test/anything/here',
      apiKey: 'key',
      model: 'test-model',
      target: '简体中文',
      endpointStyle: TranslationEndpointStyle.exactUrl,
    );
    expect(
      translationEndpoint(exact),
      'https://api.example.test/anything/here',
    );
  });

  test('picking a service brings its address and models with it', () {
    expect(
      translationProviderFor('deepseek').baseUrl,
      'https://api.deepseek.com/v1',
    );
    expect(translationProviderFor('deepseek').models, isNotEmpty);
    expect(translationProviderFor('nonsense').id, 'custom');
    expect(
      translationProviderForUrl('https://api.openai.com/v1/').id,
      'openai',
    );
    expect(translationProviderForUrl('https://my.own.server/v1').id, 'custom');
  });

  test(
    'the connection check really asks, and remembers why it failed',
    () async {
      var calls = 0;
      translator.request = (text) async {
        calls++;
        return '你好。';
      };

      expect(await translator.checkConnection(), '你好。');
      expect(await translator.checkConnection(), '你好。');
      expect(calls, 2);
      expect(translationErrorNotifier.value, isNull);

      translator.request = (text) async => throw StateError('404');
      expect(await translator.checkConnection(), isNull);
      expect(translationErrorNotifier.value, contains('404'));
    },
  );

  test('SiliconFlow is a preset, with the /v1 address its API needs', () {
    final preset = translationProviderFor('siliconflow');

    expect(preset.baseUrl, 'https://api.siliconflow.cn/v1');
    expect(preset.models, contains('deepseek-ai/DeepSeek-V3.2'));
  });

  testWidgets('configuring translation later still translates an open page', (
    tester,
  ) async {
    translationEnabledNotifier.value = false;
    translationBaseUrlNotifier.value = '';
    translationModelNotifier.value = '';
    config.setTranslationApiKey('');
    translator.request = (text) async => '翻译后的简介';

    final artist = Artist('Ejel', id: 'ar-1')
      ..biography = 'A singer from Seoul.';

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: ArtistMetadata(artist: artist)),
      ),
    );
    await tester.pump();

    expect(find.textContaining('翻译后的简介'), findsNothing);
    expect(find.textContaining('A singer from Seoul.'), findsOneWidget);

    translationBaseUrlNotifier.value = 'https://api.example.test/v1';
    translationModelNotifier.value = 'test-model';
    config.setTranslationApiKey('test-key');
    translationEnabledNotifier.value = true;

    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    await tester.pump();

    expect(find.textContaining('翻译后的简介'), findsOneWidget);
  });
}
