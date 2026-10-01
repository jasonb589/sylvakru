import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sylvakru/big_picture_view/big_picture_view.dart';
import 'package:sylvakru/l10n/generated/app_localizations.dart';

/// The big picture tabs are one list read three ways: the panel behind the tab,
/// the label on it, and what the bottom bar's "…" button offers there.
///
/// They were three lists instead, kept in step by hand, and the "…" action was
/// left behind when For You was inserted second: it still answered the numbering
/// from before that, so For You offered the whole library's song menu, Songs
/// offered the artist sort, Artists the album sort, Albums had no button at all
/// and Folders had one that did nothing. The length checks below are what makes
/// "insert a tab and forget one of the three" impossible again.
void main() {
  test('every tab has a panel of its own', () {
    expect(bigPicturePanels.length, BigPictureTab.values.length);
    expect(
      bigPicturePanels.length,
      BigPictureTab.values.length,
      reason: 'the panels and the tabs have to be the same list',
    );
  });

  test('every tab has a label of its own', () {
    final l10n = lookupAppLocalizations(const Locale('en'));
    final labels = [for (final tab in BigPictureTab.values) tab.label(l10n)];
    expect(labels.length, BigPictureTab.values.length);
    expect(labels, everyElement(isNotEmpty));
  });

  group('bigPictureMenuFor', () {
    test('a panel that is one list offers that list', () {
      expect(
        bigPictureMenuFor(BigPictureTab.songs, .local),
        BigPictureMenu.songs,
      );
      expect(
        bigPictureMenuFor(BigPictureTab.artists, .local),
        BigPictureMenu.artists,
      );
      expect(
        bigPictureMenuFor(BigPictureTab.albums, .local),
        BigPictureMenu.albums,
      );
    });

    test('the panels that gather their own offer nothing', () {
      for (final tab in [
        BigPictureTab.home,
        BigPictureTab.forYou,
        BigPictureTab.folders,
        BigPictureTab.recentlyAdded,
        BigPictureTab.playlists,
        BigPictureTab.settings,
      ]) {
        expect(
          bigPictureMenuFor(tab, .local),
          BigPictureMenu.none,
          reason: '$tab has no one list to act on',
        );
      }
    });

    test('a library with a play history offers it', () {
      expect(
        bigPictureMenuFor(BigPictureTab.frequently, .local),
        BigPictureMenu.frequently,
      );
      expect(
        bigPictureMenuFor(BigPictureTab.recently, .local),
        BigPictureMenu.recently,
      );
    });

    test('a stream source has no play history to offer', () {
      expect(
        bigPictureMenuFor(BigPictureTab.frequently, .navidrome),
        BigPictureMenu.none,
      );
      expect(
        bigPictureMenuFor(BigPictureTab.recently, .navidrome),
        BigPictureMenu.none,
      );
      // The lists that do exist there are unaffected by it.
      expect(
        bigPictureMenuFor(BigPictureTab.songs, .navidrome),
        BigPictureMenu.songs,
      );
    });
  });
}
