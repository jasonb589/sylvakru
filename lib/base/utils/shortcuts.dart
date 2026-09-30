import 'package:flutter/services.dart';

/// What a key press asks the player to do.
///
/// The mapping lives here, apart from the handler that runs it, so what each key
/// does can be read - and tested - without a player, a window or a keyboard.
enum ShortcutAction {
  playPause,
  next,
  previous,
  seekBackward,
  seekForward,
  volumeDown,
  volumeUp,
  mute,
  favorite,
  lyricsPage,
  help,
}

/// How far the seek shortcuts move the song.
const Duration shortcutSeekStep = Duration(seconds: 5);

/// How much of the volume the volume shortcuts add or take away, as a fraction.
const double shortcutVolumeStep = 0.05;

/// The volume the app starts at. Used when a mute has to be undone and nothing
/// remembers what the volume was before it.
const double appDefaultVolume = 0.3;

/// One key combination: which key, and whether Ctrl or Shift is held with it.
///
/// Alt is deliberately not part of a binding: Alt combinations belong to the
/// menus, the window and the platform, and the app never claims one.
class ShortcutBinding {
  final LogicalKeyboardKey key;
  final bool control;
  final bool shift;

  const ShortcutBinding(this.key, {this.control = false, this.shift = false});

  @override
  bool operator ==(Object other) =>
      other is ShortcutBinding &&
      other.key == key &&
      other.control == control &&
      other.shift == shift;

  @override
  int get hashCode => Object.hash(key, control, shift);

  @override
  String toString() => encodeShortcut(this);
}

/// The keys that only exist to control playback.
///
/// They are always taken, whatever the bindings say: they are what the buttons
/// on the keyboard itself send, and no keyboard puts a modifier in front of
/// them.
/// Not const: [LogicalKeyboardKey] overrides `==`, which a constant map may not
/// hold as a key.
final Map<LogicalKeyboardKey, ShortcutAction> mediaKeyActions = {
  LogicalKeyboardKey.mediaPlayPause: ShortcutAction.playPause,
  LogicalKeyboardKey.mediaPlay: ShortcutAction.playPause,
  LogicalKeyboardKey.mediaTrackNext: ShortcutAction.next,
  LogicalKeyboardKey.mediaTrackPrevious: ShortcutAction.previous,
};

/// The keys the app answers to before anything is changed by hand.
const Map<ShortcutAction, ShortcutBinding> defaultShortcutBindings = {
  ShortcutAction.playPause: ShortcutBinding(LogicalKeyboardKey.space),
  ShortcutAction.next: ShortcutBinding(
    LogicalKeyboardKey.arrowRight,
    control: true,
  ),
  ShortcutAction.previous: ShortcutBinding(
    LogicalKeyboardKey.arrowLeft,
    control: true,
  ),
  ShortcutAction.seekBackward: ShortcutBinding(
    LogicalKeyboardKey.arrowLeft,
    control: true,
    shift: true,
  ),
  ShortcutAction.seekForward: ShortcutBinding(
    LogicalKeyboardKey.arrowRight,
    control: true,
    shift: true,
  ),
  ShortcutAction.volumeDown: ShortcutBinding(
    LogicalKeyboardKey.arrowDown,
    control: true,
  ),
  ShortcutAction.volumeUp: ShortcutBinding(
    LogicalKeyboardKey.arrowUp,
    control: true,
  ),
  ShortcutAction.mute: ShortcutBinding(LogicalKeyboardKey.keyM, control: true),
  ShortcutAction.favorite: ShortcutBinding(
    LogicalKeyboardKey.keyD,
    control: true,
  ),
  ShortcutAction.lyricsPage: ShortcutBinding(
    LogicalKeyboardKey.keyL,
    control: true,
  ),
  ShortcutAction.help: ShortcutBinding(LogicalKeyboardKey.f1),
};

/// Keys a shortcut may never take: the dialogs, the focus system and the window
/// need them more than a shortcut does.
/// Not const: [LogicalKeyboardKey] overrides `==`, which a constant set may not
/// hold.
final Set<LogicalKeyboardKey> reservedShortcutKeys = {
  LogicalKeyboardKey.escape,
  LogicalKeyboardKey.tab,
  LogicalKeyboardKey.enter,
  LogicalKeyboardKey.numpadEnter,
  LogicalKeyboardKey.backspace,
  LogicalKeyboardKey.delete,
  LogicalKeyboardKey.f11,
  LogicalKeyboardKey.contextMenu,
};

/// Whether [binding] may be assigned by hand.
///
/// Two rules keep the app usable: a plain key (a letter, a digit, an arrow, Tab
/// and the like) would swallow typing and focus movement, so a binding needs
/// Ctrl or Shift - unless it is a key that only exists to control playback
/// (Space and the media keys). The keys the window system relies on are refused
/// outright.
bool isUsableBinding(ShortcutBinding binding) {
  if (reservedShortcutKeys.contains(binding.key)) {
    return false;
  }
  if (binding.control || binding.shift) {
    return true;
  }
  return binding.key == LogicalKeyboardKey.space ||
      mediaKeyActions.containsKey(binding.key);
}

/// The action [key] asks for, or null when the key is not one of ours.
///
/// [typing] must be true while a text field has the caret: a shortcut that
/// swallowed those keystrokes would make the field unusable. Keys carrying Alt
/// are left alone as well - those belong to menus and to the window.
///
/// [bindings] is the table in force, so the caller can pass what the user has
/// set up instead of the defaults.
ShortcutAction? shortcutActionFor({
  required LogicalKeyboardKey key,
  bool control = false,
  bool shift = false,
  bool alt = false,
  bool typing = false,
  Map<ShortcutAction, ShortcutBinding> bindings = defaultShortcutBindings,
}) {
  if (typing || alt) {
    return null;
  }

  final media = mediaKeyActions[key];
  if (media != null) {
    return media;
  }

  for (final entry in bindings.entries) {
    final binding = entry.value;
    if (binding.key == key &&
        binding.control == control &&
        binding.shift == shift) {
      return entry.key;
    }
  }

  return null;
}

/// The volume [step]s away from [current], kept inside 0..1.
double shortcutVolume(double current, double step) =>
    (current + step).clamp(0.0, 1.0);

/// The bindings in force: the defaults with the saved changes on top.
Map<ShortcutAction, ShortcutBinding> effectiveBindings(
  Map<ShortcutAction, ShortcutBinding> overrides,
) => {...defaultShortcutBindings, ...overrides};

/// The action other than [action] that [binding] is assigned to, if any.
ShortcutAction? shortcutHolder(
  Map<ShortcutAction, ShortcutBinding> bindings,
  ShortcutAction action,
  ShortcutBinding binding,
) {
  for (final entry in bindings.entries) {
    if (entry.key != action && entry.value == binding) {
      return entry.key;
    }
  }
  return null;
}

/// Gives [binding] to [action] and returns the changes to save, or null when the
/// binding cannot be used.
///
/// A binding another action already holds is taken over rather than refused: the
/// other action gets the one this one had, so a swap never leaves an action
/// without a key.
///
/// [current] is the table in force, so the saved changes are derived from it
/// rather than maintained alongside it: going back to a default drops the entry,
/// and an entry that no longer differs from its default disappears on its own.
Map<ShortcutAction, ShortcutBinding>? assignShortcut({
  required Map<ShortcutAction, ShortcutBinding> current,
  required ShortcutAction action,
  required ShortcutBinding binding,
}) {
  if (!isUsableBinding(binding)) {
    return null;
  }

  final next = Map<ShortcutAction, ShortcutBinding>.from(current);
  final previous = next[action];
  next[action] = binding;

  final holder = shortcutHolder(next, action, binding);
  if (holder != null) {
    if (previous == null || !isUsableBinding(previous)) {
      return null;
    }
    next[holder] = previous;
  }

  return onlyChangesFromDefault(next);
}

/// Keeps only what differs from the defaults.
///
/// The file stays short and readable, and a later change to a default still
/// reaches everyone who never touched that key.
Map<ShortcutAction, ShortcutBinding> onlyChangesFromDefault(
  Map<ShortcutAction, ShortcutBinding> bindings,
) {
  final overrides = <ShortcutAction, ShortcutBinding>{};
  for (final entry in bindings.entries) {
    if (defaultShortcutBindings[entry.key] != entry.value) {
      overrides[entry.key] = entry.value;
    }
  }
  return overrides;
}

/// The stored form of [overrides], ready for the settings file.
Map<String, String> encodeShortcutOverrides(
  Map<ShortcutAction, ShortcutBinding> overrides,
) => {
  for (final entry in overrides.entries)
    entry.key.name: encodeShortcut(entry.value),
};

/// Reads back what [encodeShortcutOverrides] wrote.
///
/// Anything this build cannot use is left out: an action in a newer file, a key
/// that no longer exists, or a combination the panel would refuse. A change of
/// defaults therefore never leaves an action without a key.
Map<ShortcutAction, ShortcutBinding> decodeShortcutOverrides(Object? json) {
  if (json is! Map) {
    return {};
  }

  final overrides = <ShortcutAction, ShortcutBinding>{};
  for (final entry in json.entries) {
    ShortcutAction? action;
    for (final candidate in ShortcutAction.values) {
      if (candidate.name == entry.key) {
        action = candidate;
        break;
      }
    }
    if (action == null || entry.value is! String) {
      continue;
    }

    final binding = decodeShortcut(entry.value as String);
    if (binding == null || !isUsableBinding(binding)) {
      continue;
    }
    if (defaultShortcutBindings[action] == binding) {
      continue;
    }
    overrides[action] = binding;
  }

  return overrides;
}

/// The stored form of one binding: the modifiers, then the key's id.
String encodeShortcut(ShortcutBinding binding) =>
    '${binding.control ? 'c' : ''}${binding.shift ? 's' : ''}${binding.key.keyId}';

/// Reads back [encodeShortcut], or null when the text is not a binding this
/// build understands.
ShortcutBinding? decodeShortcut(String encoded) {
  final match = RegExp(r'^(c?)(s?)(\d+)$').firstMatch(encoded);
  if (match == null) {
    return null;
  }
  final id = int.tryParse(match.group(3)!);
  if (id == null) {
    return null;
  }
  final key = LogicalKeyboardKey(id);
  // A key nothing has a name for cannot be shown in the panel, so it is treated
  // as unknown rather than kept as a mystery binding.
  if (shortcutKeyText(key) == unknownKeyText) {
    return null;
  }
  return ShortcutBinding(
    key,
    control: match.group(1) == 'c',
    shift: match.group(2) == 's',
  );
}

/// Shown when a key has no name to print.
const String unknownKeyText = '?';

/// How the panel writes a whole combination: "Ctrl + Shift + ←".
String bindingText(ShortcutBinding binding) {
  final parts = [
    if (binding.control) 'Ctrl',
    if (binding.shift) 'Shift',
    shortcutKeyText(binding.key),
  ];
  return parts.join(' + ');
}

/// What a single key is called in the panel.
///
/// The arrows and the media keys get their symbols: those read better than the
/// names the platform hands out.
String shortcutKeyText(LogicalKeyboardKey key) {
  switch (key) {
    case LogicalKeyboardKey.arrowLeft:
      return '←';
    case LogicalKeyboardKey.arrowRight:
      return '→';
    case LogicalKeyboardKey.arrowUp:
      return '↑';
    case LogicalKeyboardKey.arrowDown:
      return '↓';
    case LogicalKeyboardKey.space:
      return 'Space';
    case LogicalKeyboardKey.f1:
      return 'F1';
    case LogicalKeyboardKey.mediaPlayPause:
      return '⏯';
    case LogicalKeyboardKey.mediaTrackNext:
      return '⏭';
    case LogicalKeyboardKey.mediaTrackPrevious:
      return '⏮';
  }
  final label = key.keyLabel;
  return label.isEmpty ? unknownKeyText : label;
}

/// True while the shortcuts panel is waiting for a key to be pressed.
///
/// The handler must do nothing at all then: without this, pressing Ctrl+→ to
/// rebind something would also change the song.
bool isCapturingShortcut = false;
