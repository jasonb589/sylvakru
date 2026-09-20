import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:sylvakru/base/audio_handler.dart';
import 'package:sylvakru/base/services/color_manager.dart';
import 'package:sylvakru/base/services/lyric.dart';
import 'package:sylvakru/base/my_audio_metadata.dart';
import 'package:sylvakru/base/widgets/lyric_list_view.dart';

/// Shows the lyric line that matches the current playback position.
///
/// The bar has no room for a full lyrics view, so this is just the single line
/// being sung right now — the same line the lyrics page highlights. When the
/// song has no timed lyrics it renders [fallback] instead, so a caller can keep
/// showing whatever it displayed before (the album name, for instance).
class LyricsLineBar extends StatefulWidget {
  /// Font size of the lyric line.
  final double fontSize;

  /// Applied when the caller wants a specific colour.
  final Color? color;

  /// Number of lines before ellipsis. One keeps the bar compact.
  final int maxLines;

  /// Alignment of the text.
  final TextAlign textAlign;

  /// Shown when the song has no timed lyrics.
  final Widget? fallback;

  const LyricsLineBar({
    super.key,
    this.fontSize = 12,
    this.color,
    this.maxLines = 1,
    this.textAlign = TextAlign.left,
    this.fallback,
  });

  @override
  State<LyricsLineBar> createState() => _LyricsLineBarState();
}

class _LyricsLineBarState extends State<LyricsLineBar> {
  StreamSubscription<Duration>? positionSub;

  /// The song whose lyrics are currently loaded.
  MyAudioMetadata? song;

  /// The line currently being sung, or null when there is nothing to show.
  String? line;

  /// Latest playback position, kept so the line can be recomputed as soon as
  /// lyrics finish loading instead of waiting for the next tick.
  Duration position = Duration.zero;

  /// Index of the line in the parsed lyrics, so a rebuild only happens when the
  /// line actually changes (position ticks far more often than that).
  int lineIndex = -2;

  @override
  void initState() {
    super.initState();

    currentSongNotifier.addListener(_onSongChanged);
    _onSongChanged();

    positionSub = audioHandler.getPositionStream().listen(_onPosition);
  }

  @override
  void dispose() {
    currentSongNotifier.removeListener(_onSongChanged);
    positionSub?.cancel();
    super.dispose();
  }

  void _onSongChanged() {
    final current = currentSongNotifier.value;
    if (current?.id == song?.id) {
      return;
    }
    song = current;
    lineIndex = -2;
    line = null;
    if (current != null) {
      _loadLyrics(current);
    } else if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadLyrics(MyAudioMetadata current) async {
    await setParsedLyrics(current);
    if (!mounted || song?.id != current.id) {
      return;
    }
    _onPosition(position);
  }

  void _onPosition(Duration newPosition) {
    position = newPosition;

    final parsed = song?.parsedLyrics;
    if (parsed == null || parsed.lines.isEmpty) {
      return;
    }

    final lines = parsed.lines;

    // a song can carry one untimed lyric block; that is not usable here
    if (lines.length == 1 && lines.first.start == Duration.zero) {
      return;
    }

    final adjusted =
        newPosition + Duration(milliseconds: lyricsTimeOffsetNotifier.value);

    var index = -1;
    for (var i = 0; i < lines.length; i++) {
      if (adjusted < lines[i].start) {
        break;
      }
      index = i;
    }

    if (index == lineIndex) {
      return;
    }
    lineIndex = index;

    final text = index < 0 ? null : lines[index].text.trim();
    final next = (text == null || text.isEmpty) ? null : text;

    if (mounted && next != line) {
      setState(() {
        line = next;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = line;
    if (text == null) {
      return widget.fallback ?? const SizedBox.shrink();
    }

    return Text(
      text,
      maxLines: widget.maxLines,
      overflow: TextOverflow.ellipsis,
      textAlign: widget.textAlign,
      style: TextStyle(
        fontSize: widget.fontSize,
        color: widget.color ?? iconColor.value.withValues(alpha: 0.75),
      ),
    );
  }
}
