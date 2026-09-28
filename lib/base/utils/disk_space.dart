/// Helpers behind the disk-space reminder.
///
/// Dart has no API for the free space of a volume, so the figure is asked of
/// the platform. What comes back is parsed and judged here, away from the
/// channel, because a platform that cannot answer has to be an ordinary case
/// rather than an error.
library;

/// The free bytes out of `df -P -k` output, or null when there is no figure.
///
/// The capacity column is the one field that always ends in `%`, and the
/// available column sits right before it: reading that pair instead of fixed
/// positions means a device name or a mount point containing a space cannot
/// shift the answer.
int? parseDfFreeBytes(String output) {
  for (final line in output.split('\n').reversed) {
    final fields = line.trim().split(RegExp(r'\s+'));
    if (fields.length < 6) {
      continue;
    }
    final capacity = fields.indexWhere((field) => field.endsWith('%'));
    if (capacity < 2) {
      continue;
    }
    final blocks = int.tryParse(fields[capacity - 1]);
    if (blocks == null) {
      continue;
    }
    // `-k` asks for 1024-byte blocks.
    return blocks * 1024;
  }
  return null;
}

/// Whether [freeBytes] is under the line the listener drew.
///
/// An unknown figure never warns: a platform that cannot answer would
/// otherwise raise a reminder nobody can clear. A threshold of zero turns the
/// reminder off.
bool isDiskSpaceLow({required int? freeBytes, required int thresholdMb}) {
  if (freeBytes == null || thresholdMb <= 0) {
    return false;
  }
  return freeBytes < thresholdMb * 1024 * 1024;
}
