import 'package:material_ui/material_ui.dart';
import 'package:sylvakru/base/app.dart';
import 'package:sylvakru/base/design/app_tokens.dart';
import 'package:sylvakru/base/services/picture_service.dart';
import 'package:sylvakru/base/utils/contrast_color_generator.dart';
import 'package:sylvakru/layer/lyrics_page_layer.dart';

final colorManager = ColorManager();

MyPicture? backgroundPicture;
Color backgroundCoverArtColor = Colors.grey;
Color currentCoverArtColor = Colors.grey;

bool useCurrentSongForBg = true;

ContrastColorTextTheme contrastColorTheme = ContrastColorGenerator.generate(
  currentCoverArtColor,
);

final lightHoverFocusColorNotifier = ValueNotifier(false);

void updateHoverFocusColor() {
  if ((displayLyricsPage && lyricsPageThemeNotifier.value == .vivid) ||
      viewModeNotifier.value == .mini) {
    double r = currentCoverArtColor.r;
    double g = currentCoverArtColor.g;
    double b = currentCoverArtColor.b;
    final luminance = 0.299 * r + 0.587 * g + 0.114 * b;

    lightHoverFocusColorNotifier.value = luminance < 0.5;
  } else {
    lightHoverFocusColorNotifier.value = mainPageThemeNotifier.value == .dark;
  }
}

final MyColor pageBackgroundColor = MyColor(
  vividModeValue: Color.fromARGB(100, 245, 245, 245),
  lightModeValue: Colors.grey.shade100,
  darkModeValue: Color.fromARGB(255, 50, 50, 50),
);

final MyColor iconColor = MyColor(
  vividModeValue: Colors.black,
  lightModeValue: Colors.black,
  darkModeValue: Colors.grey.shade400,
);

final MyColor textColor = MyColor(
  vividModeValue: Colors.grey.shade900,
  lightModeValue: Colors.grey.shade900,
  darkModeValue: Colors.grey.shade400,
);

final MyColor highlightTextColor = MyColor(
  vividModeValue: Colors.black,
  lightModeValue: Colors.black,
  darkModeValue: Color.fromARGB(255, 230, 230, 230),
);

final MyColor switchColor = MyColor(
  vividModeValue: Colors.black87,
  lightModeValue: Colors.black87,
  darkModeValue: Color.fromARGB(221, 0, 0, 0),
);

final MyColor glassColor = MyColor(
  vividModeValue: Color.fromARGB(75, 255, 255, 255),
  lightModeValue: Color.fromARGB(128, 255, 255, 255),
  darkModeValue: Color.fromARGB(128, 30, 30, 30),
);

final MyColor panelColor = MyColor(
  vividModeValue: Color.fromARGB(100, 245, 245, 245),
  lightModeValue: Colors.white,
  darkModeValue: Color.fromARGB(255, 50, 50, 50),
);

final MyColor sidebarColor = MyColor(
  vividModeValue: Color.fromARGB(100, 238, 238, 238),
  lightModeValue: Colors.grey.shade50,
  darkModeValue: Color.fromARGB(255, 55, 55, 55),
);

final MyColor bottomColor = MyColor(
  vividModeValue: Color.fromARGB(100, 250, 250, 250),
  lightModeValue: Colors.grey.shade100,
  darkModeValue: Color.fromARGB(255, 60, 60, 60),
);

final MyColor searchFieldColor = MyColor(
  getVividValue: () {
    final tmpColor =
        backgroundPicture?.lowerLuminance ?? backgroundCoverArtColor;
    return tmpColor.withAlpha(75);
  },
  lightModeValue: Colors.grey.shade200,
  darkModeValue: Colors.grey.shade700,
);

final MyColor buttonColor = MyColor(
  getVividValue: () {
    final tmpColor =
        backgroundPicture?.lowerLuminance ?? backgroundCoverArtColor;
    return tmpColor.withAlpha(75);
  },
  lightModeValue: Colors.grey.shade200,
  darkModeValue: Colors.grey.shade700,
);

final MyColor dividerColor = MyColor(
  getVividValue: () {
    return backgroundPicture?.lowerLuminance ?? backgroundCoverArtColor;
  },
  lightModeValue: Colors.grey,
  darkModeValue: Colors.grey.shade700,
);

final MyColor selectedItemColor = MyColor(
  getVividValue: () {
    final tmpColor =
        backgroundPicture?.lowerLuminance ?? backgroundCoverArtColor;
    return tmpColor.withAlpha(75);
  },
  lightModeValue: Colors.grey.shade200,
  darkModeValue: Colors.grey.shade700,
);

final MyColor menuColor = MyColor(
  vividModeValue: Colors.white54,
  lightModeValue: Colors.grey.shade50,
  darkModeValue: Colors.grey.shade800,
);

final MyColor seekBarColor = MyColor(
  vividModeValue: Colors.black,
  lightModeValue: Colors.black,
  darkModeValue: Colors.grey.shade400,
);

final MyColor volumeBarColor = MyColor(
  vividModeValue: Colors.black,
  lightModeValue: Colors.black,
  darkModeValue: Colors.grey.shade400,
);

final MyColor lyricsPageBackgroundColor = MyColor(
  vividModeValue: Colors.transparent,
  lightModeValue: Colors.grey.shade200,
  darkModeValue: Color.fromARGB(255, 50, 50, 50),
  pageType: 1,
);

final MyColor lyricsPageForegroundColor = MyColor(
  getVividValue: () {
    return contrastColorTheme.regular;
  },
  lightModeValue: Colors.grey.shade900,
  darkModeValue: Colors.grey.shade300,
  pageType: 1,
);

final MyColor lyricsPageHighlightTextColor = MyColor(
  getVividValue: () {
    return contrastColorTheme.accent;
  },
  lightModeValue: Colors.black,
  darkModeValue: Colors.grey.shade200,
  pageType: 1,
);

final MyColor lyricsPageButtonColor = MyColor(
  getVividValue: () {
    return contrastColorTheme.regular.withAlpha(50);
  },
  lightModeValue: Colors.white70,
  darkModeValue: Colors.grey.shade700,
  pageType: 1,
);

final MyColor lyricsPageDividerColor = MyColor(
  getVividValue: () {
    return contrastColorTheme.regular;
  },
  lightModeValue: Colors.grey,
  darkModeValue: Colors.grey.shade700,
  pageType: 1,
);

final MyColor lyricsPageSelectedItemColor = MyColor(
  getVividValue: () {
    return contrastColorTheme.regular.withAlpha(50);
  },
  lightModeValue: Colors.white,
  darkModeValue: Colors.grey.shade700,
  pageType: 1,
);

final MyColor lyricsPageMenuColor = MyColor(
  vividModeValue: Colors.white10,
  lightModeValue: Colors.grey.shade50,
  darkModeValue: Colors.grey.shade800,
  pageType: 1,
);

final MyColor miniViewForegroundColor = MyColor(
  getVividValue: () {
    return contrastColorTheme.regular;
  },
  pageType: 2,
);

final MyColor miniViewHighlightTextColor = MyColor(
  getVividValue: () {
    return contrastColorTheme.accent;
  },

  pageType: 2,
);

final MyColor miniViewButtonColor = MyColor(
  getVividValue: () {
    return contrastColorTheme.regular.withAlpha(50);
  },
  pageType: 2,
);

final MyColor miniViewDividerColor = MyColor(
  getVividValue: () {
    return contrastColorTheme.regular;
  },
  pageType: 2,
);

final MyColor miniViewSelectedItemColor = MyColor(
  getVividValue: () {
    return contrastColorTheme.regular.withAlpha(50);
  },

  pageType: 2,
);

final MyColor miniViewMenuColor = MyColor(
  vividModeValue: Colors.white10,
  pageType: 2,
);

class ColorManager {
  late final List<MyColor> myMainPageColors;
  late final List<MyColor> myLyricsPageColors;
  late final List<MyColor> myMiniViewColors;

  ColorManager() {
    myMainPageColors = [
      pageBackgroundColor,
      iconColor,
      textColor,
      highlightTextColor,
      switchColor,
      glassColor,
      panelColor,
      sidebarColor,
      bottomColor,
      searchFieldColor,
      buttonColor,
      dividerColor,
      selectedItemColor,
      menuColor,
      seekBarColor,
      volumeBarColor,
    ];

    myLyricsPageColors = [
      lyricsPageBackgroundColor,
      lyricsPageForegroundColor,
      lyricsPageHighlightTextColor,
      lyricsPageDividerColor,
      lyricsPageButtonColor,
      lyricsPageSelectedItemColor,
      lyricsPageMenuColor,
    ];

    if (!isMobile) {
      myMiniViewColors = [
        miniViewForegroundColor,
        miniViewHighlightTextColor,
        miniViewDividerColor,
        miniViewButtonColor,
        miniViewSelectedItemColor,
        miniViewMenuColor,
      ];
    }
  }

  void updateMainPageColors() {
    for (final color in myMainPageColors) {
      color.updateColor();
    }
  }

  void updateLyricsPageColors() {
    for (final color in myLyricsPageColors) {
      color.updateColor();
    }
  }

  void updateMiniViewColors() {
    for (final color in myMiniViewColors) {
      color.updateColor();
    }
  }

  void updateBigPictureRelatedColors(MyPicture? picture) {
    backgroundPicture = picture;
    backgroundCoverArtColor = backgroundPicture?.color ?? Colors.grey;
    searchFieldColor.updateColor();
    buttonColor.updateColor();
    dividerColor.updateColor();
    selectedItemColor.updateColor();
  }

  void updateColors() {
    updateMainPageColors();
    updateLyricsPageColors();
    if (!isMobile) {
      updateMiniViewColors();
    }
  }

  /// The colour painted behind a cover art tile in a list row.
  ///
  /// Opaque grey here put a flat grey slab behind every song that has no
  /// artwork at all; leaving it transparent lets the row's own surface show,
  /// which is what the note icon is meant to sit on.
  Color? getSpecificMainPageCoverArtBaseColorForm(MyPicture? picture) {
    final colour = picture?.color;
    if (mainPageThemeNotifier.value != .vivid) {
      return isMobile ? pageBackgroundColor.value : panelColor.value;
    }
    // `Colors.grey` is the pipeline's own "this artwork has no colour" value;
    // painting it opaque is what turned a missing cover into a grey slab.
    return colour == Colors.grey ? null : colour;
  }

  Color? getSpecificMainPageSearchFieldColorForm(MyPicture? picture) {
    return mainPageThemeNotifier.value == .vivid
        ? picture == null
              ? Colors.grey.withAlpha(75)
              : picture.color?.withAlpha(75)
        : searchFieldColor.value;
  }

  Color getSpecificMainPageCoverArtBaseColor() {
    return mainPageThemeNotifier.value == .vivid
        ? backgroundCoverArtColor
        : isMobile
        ? pageBackgroundColor.value
        : panelColor.value;
  }

  Color getSpecificLyricsPageCoverArtBaseColor() {
    return lyricsPageThemeNotifier.value == .vivid
        ? currentCoverArtColor
        : lyricsPageBackgroundColor.value;
  }

  Color getSpecificBgBaseColor() {
    final colour = viewModeNotifier.value == .mini || displayLyricsPage
        ? currentCoverArtColor
        : backgroundCoverArtColor;
    // The opaque base behind the window's artwork. The colour pipeline hands
    // out `Colors.grey` until a cover colour is known, and that grey base is
    // what showed through wherever the artwork had not arrived yet.
    return colour == Colors.grey ? Colors.grey.shade100 : colour;
  }

  /// The opaque colour behind everything the app paints.
  ///
  /// The window itself is not guaranteed to be opaque: on Windows a transparent
  /// window background colour becomes an accent-transparentgradient, so every
  /// translucent pixel in the scene composites against the desktop. The client
  /// paints this base under each full-size surface instead of relying on the
  /// window's own backdrop - one cover cross-fade mid-flight was enough for the
  /// window behind the player to show through.
  Color getWindowBackplateColor() {
    if (mainPageThemeNotifier.value == .dark) {
      return const Color(0xFF323232);
    }
    // The vivid backdrop is the cover colour over a neutral base, so matching
    // that composite keeps a surface without artwork looking the same as one
    // whose artwork is still fading in.
    return Color.alphaBlend(
      backgroundCoverArtColor.withValues(alpha: AppBlur.backdropAlpha / 255),
      Colors.grey.shade100,
    );
  }

  Color getSpecificBgColor() {
    return viewModeNotifier.value == .mini
        ? Colors.transparent
        : displayLyricsPage
        ? lyricsPageBackgroundColor.value
        : isMobile
        ? pageBackgroundColor.value
        : panelColor.value;
  }

  Color getSpecificTextColor() {
    return viewModeNotifier.value == .mini
        ? miniViewForegroundColor.value
        : displayLyricsPage
        ? lyricsPageForegroundColor.value
        : textColor.value;
  }

  Color getSpecificHighlightTextColor() {
    return viewModeNotifier.value == .mini
        ? miniViewHighlightTextColor.value
        : displayLyricsPage
        ? lyricsPageHighlightTextColor.value
        : highlightTextColor.value;
  }

  Color getSpecificIconColor() {
    return viewModeNotifier.value == .mini
        ? miniViewForegroundColor.value
        : displayLyricsPage
        ? lyricsPageForegroundColor.value
        : iconColor.value;
  }

  Color getSpecificButtonColor() {
    return viewModeNotifier.value == .mini
        ? miniViewButtonColor.value
        : displayLyricsPage
        ? lyricsPageButtonColor.value
        : buttonColor.value;
  }

  Color getSpecificDividerColor() {
    return viewModeNotifier.value == .mini
        ? miniViewDividerColor.value
        : displayLyricsPage
        ? lyricsPageDividerColor.value
        : dividerColor.value;
  }

  Color getSpecificSelectedItemColor() {
    return viewModeNotifier.value == .mini
        ? miniViewSelectedItemColor.value
        : displayLyricsPage
        ? lyricsPageSelectedItemColor.value
        : selectedItemColor.value;
  }

  Color getSpecificMenuColor() {
    if (viewModeNotifier.value == .mini) {
      return miniViewMenuColor.value;
    }
    return displayLyricsPage ? lyricsPageMenuColor.value : menuColor.value;
  }
}

class MyColor {
  // fixed
  final Color? vividModeValue;
  // dynamic
  final Color Function()? getVividValue;
  final Color lightModeValue;
  final Color darkModeValue;

  // main: 0, lyrics: 1, mini mode: 2
  final int pageType;

  ValueNotifier<Color> valueNotifier = ValueNotifier(Colors.transparent);

  MyColor({
    this.vividModeValue,
    this.getVividValue,
    this.lightModeValue = Colors.transparent,
    this.darkModeValue = Colors.transparent,
    this.pageType = 0,
  });

  void updateColor() {
    // The mini view always sits on cover derived artwork, so its controls have
    // to contrast with that artwork rather than follow the page theme. Its
    // colours define no light or dark value, so falling through to them left
    // every mini view control with a null colour under those themes.
    if (pageType == 2) {
      valueNotifier.value = vividModeValue ?? getVividValue!.call();
      return;
    }

    final themeType = pageType == 0
        ? mainPageThemeNotifier.value
        : lyricsPageThemeNotifier.value;
    switch (themeType) {
      case .vivid:
        valueNotifier.value = vividModeValue ?? getVividValue!.call();
        break;
      case .light:
        valueNotifier.value = lightModeValue;
        break;
      default:
        valueNotifier.value = darkModeValue;
    }
  }

  Color get value => valueNotifier.value;
}
