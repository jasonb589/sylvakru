import 'dart:math';
import 'dart:ui';

import 'package:sylvakru/base/design/app_tokens.dart';
import 'package:sylvakru/base/services/lyric.dart';

/// The arithmetic behind the lyrics animation, kept out of the widgets: which
/// line is being sung, how far the fill has swept across it, and when the list
/// has to start moving. Every one of them is a pure function of the position
/// the player reports, so all of it is checkable without a player or a page.
///
/// Nothing here invents data: the fill works from the timestamps the parser
/// already produced, and a line without word timings fills across the span it
/// already has — the start of the next line.

/// The index of the line being sung at [position], or -1 before the first one.
///
/// A line that shares its timestamp with another — a translation line, or a
/// repeated line — resolves to the first of them, which is what the translation
/// lines rely on.
int lyricIndexAt(List<LyricLine> lines, Duration position) {
  var current = -1;
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (position < line.start) {
      break;
    }
    if (current == -1 || line.start > lines[current].start) {
      current = i;
    }
  }
  return current;
}

/// Where each of [line]'s tokens starts inside [LyricLine.text].
///
/// Hidden timestamps carry no text and are dropped by the parser, so the tokens
/// normally spell the line out exactly; looking each one up in turn keeps the
/// offsets right even when a space between two words belongs to no token.
List<int> lyricTokenOffsets(LyricLine line) {
  final offsets = <int>[];
  var cursor = 0;
  for (final token in line.tokens) {
    final at = token.text.isEmpty
        ? cursor
        : line.text.indexOf(token.text, cursor);
    final offset = at >= 0 ? at : cursor;
    offsets.add(offset);
    cursor = offset + token.text.length;
  }
  return offsets;
}

/// How far the fill has swept across a line: the characters already sung, plus
/// the fraction of the one the fill is in the middle of.
class LyricFill {
  final int characters;
  final double fraction;

  const LyricFill(this.characters, this.fraction);

  static const LyricFill empty = LyricFill(0, 0);

  @override
  bool operator ==(Object other) =>
      other is LyricFill &&
      other.characters == characters &&
      other.fraction == fraction;

  @override
  int get hashCode => Object.hash(characters, fraction);

  @override
  String toString() => 'LyricFill($characters, $fraction)';
}

/// The fill for [line] at [position].
///
/// Word timings drive it when the source has them. Without them — a plain LRC
/// has one token per line — the token fills from its own start to its end,
/// which the parser set to the next line's start, so even a line without word
/// timings sweeps with the voice instead of switching on.
LyricFill lyricFillFor(LyricLine line, Duration position) {
  if (line.text.isEmpty || line.tokens.isEmpty) {
    return LyricFill.empty;
  }

  final offsets = lyricTokenOffsets(line);
  for (var i = 0; i < line.tokens.length; i++) {
    final token = line.tokens[i];
    if (position < token.start) {
      // Everything before this token has been sung; spaces in front of it have
      // not, and they are not the voice's, so they stay as they are.
      return LyricFill(offsets[i], 0);
    }
    final end = token.end;
    if (end == null || position < end) {
      final spanMs = end == null ? 0 : (end - token.start).inMilliseconds;
      final progress = spanMs <= 0
          ? 1.0
          : (position - token.start).inMilliseconds / spanMs;
      final swept = offsets[i] + token.text.length * progress.clamp(0.0, 1.0);
      return LyricFill(swept.floor(), swept - swept.floor());
    }
  }
  return LyricFill(line.text.length, 0);
}

/// How many lines away [index] is, or the far end when nothing is current.
int lyricDistance(int index, int current) {
  if (current < 0) {
    return AppLyrics.lineOpacities.length - 1;
  }
  return (index - current).abs();
}

/// The opacity of a line [distance] lines from the one being sung.
///
/// The distance is fractional while the change animates, so a line taking over
/// from another crosses the steps instead of jumping between them.
double lyricLineOpacity(double distance) {
  final steps = AppLyrics.lineOpacities;
  if (distance <= 0) {
    return steps.first;
  }
  final upper = min(distance, (steps.length - 1).toDouble());
  final lower = upper.floor();
  final next = min(lower + 1, steps.length - 1);
  return steps[lower] + (steps[next] - steps[lower]) * (upper - lower);
}

/// The scale of a line [distance] lines from the one being sung: only the
/// current line is larger, and it settles back by the next line.
double lyricLineScale(double distance) {
  final near = distance.clamp(0.0, 1.0);
  return 1 + (AppLyrics.currentScale - 1) * (1 - near);
}

/// The weight of a line [distance] lines from the one being sung.
///
/// Two steps lighter is enough to read as "not this one" beside the current
/// line, and it keeps the difference visible on fonts that ship more than one
/// weight.
FontWeight lyricLineWeight(FontWeight base, double distance) {
  final lighter = FontWeight.values.firstWhere(
    (weight) => weight.value >= base.value - 200,
    orElse: () => FontWeight.values.first,
  );
  return FontWeight.lerp(lighter, base, 1 - distance.clamp(0.0, 1.0))!;
}

/// How long the list should take to travel [lines] lines.
int lyricScrollMs(int lines) {
  final distance = lines.clamp(0, 32);
  return (AppLyrics.scrollBaseMs + AppLyrics.scrollPerLineMs * distance).clamp(
    AppLyrics.scrollMinMs,
    AppLyrics.scrollMaxMs,
  );
}

/// Whether a scroll towards a line starting at [nextStart] has to begin now for
/// it to land as that line is sung.
///
/// This is the difference between the list chasing the song and the list being
/// there when the song arrives.
bool lyricScrollDue({
  required Duration position,
  required Duration nextStart,
  required int durationMs,
}) {
  return position >= nextStart - Duration(milliseconds: durationMs);
}

/// The position the fill is drawn at.
///
/// [smoothed] is the last reported position plus the time since it arrived,
/// which keeps the wipe moving between reports. A gap larger than
/// [AppLyrics.seekSnapMs] is a seek rather than drift, so the reported position
/// wins outright; within that, the fill may lead the voice by at most
/// [AppLyrics.interpolationLeadMs] so it never runs ahead of it.
Duration lyricDrawPosition({
  required Duration reported,
  required Duration smoothed,
}) {
  final drift = smoothed - reported;
  if (drift.abs() > Duration(milliseconds: AppLyrics.seekSnapMs)) {
    return reported;
  }
  final lead = Duration(milliseconds: AppLyrics.interpolationLeadMs);
  return drift > lead ? reported + lead : smoothed;
}
