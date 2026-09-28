import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sylvakru/base/app.dart';
import 'package:sylvakru/base/utils/path.dart';

/// The download folder the listener picks has to be honoured without losing
/// the per-source split: two libraries must never share one folder, and an
/// empty setting has to behave like "not set" rather than putting files at the
/// root of the drive.
void main() {
  setUpAll(() {
    appSupportDir = Directory.systemTemp.createTempSync('sylvakru_dl');
  });

  tearDown(() {
    downloadRootDir = null;
  });

  test('without a picked folder the app uses its own per-source folder', () {
    downloadRootDir = null;
    expect(
      getDownloadsPath(SourceType.local),
      p.join(appSupportDir.path, 'local', 'downloads'),
    );
  });

  test('a picked folder is used as the root, still split per source', () {
    downloadRootDir = r'D:\Music';
    expect(
      getDownloadsPath(SourceType.navidrome),
      p.join(r'D:\Music', 'navidrome'),
    );
    expect(getDownloadsPath(SourceType.local), p.join(r'D:\Music', 'local'));
  });

  test('an empty setting falls back to the app folder', () {
    downloadRootDir = '';
    expect(
      getDownloadsPath(SourceType.feiniu),
      p.join(appSupportDir.path, 'feiniu', 'downloads'),
    );
  });
}
