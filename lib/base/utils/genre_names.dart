/// Chinese names for the genres servers and files actually report.
///
/// A fixed table rather than a translation service: the vocabulary is small,
/// the mapping is stable, and it costs nothing — including for a local library
/// that has no network at all. Anything not in the table is shown as it came,
/// so an unusual tag is never replaced by a wrong guess.
const _genreNames = <String, String>{
  'acoustic': '原声器乐',
  'alternative': '另类',
  'alternative metal': '另类金属',
  'alternative rock': '另类摇滚',
  'ambient': '氛围',
  'anime': '动画',
  'ballad': '抒情',
  'blues': '蓝调',
  'cantopop': '粤语流行',
  'chinese folk': '中国民谣',
  'chinese rock': '中国摇滚',
  'city pop': '城市流行',
  'classical': '古典',
  'contemporary folk': '当代民谣',
  'country': '乡村',
  'country pop': '乡村流行',
  'dance': '舞曲',
  'disco': '迪斯科',
  'drum and bass': '鼓打贝斯',
  'dubstep': '回响贝斯',
  'edm': '电子舞曲',
  'electronic': '电子',
  'experimental': '实验',
  'folk': '民谣',
  'folk rock': '民谣摇滚',
  'funk': '放克',
  'gospel': '福音',
  'grunge': '垃圾摇滚',
  'guofeng': '国风',
  'hard rock': '硬摇滚',
  'heavy metal': '重金属',
  'hip hop': '嘻哈',
  'hip-hop': '嘻哈',
  'house': '浩室',
  'idol': '偶像',
  'indie pop': '独立流行',
  'indie rock': '独立摇滚',
  'instrumental': '器乐',
  'j-pop': '日本流行',
  'jazz': '爵士',
  'k-pop': '韩国流行',
  'karaoke': '卡拉OK',
  'latin': '拉丁',
  'lo-fi': '低保真',
  'mandopop': '华语流行',
  'metal': '金属',
  'musical': '音乐剧',
  'new age': '新世纪',
  'opera': '歌剧',
  'pop': '流行',
  'pop punk': '流行朋克',
  'pop rock': '流行摇滚',
  'post-rock': '后摇滚',
  'psychedelic': '迷幻',
  'punk': '朋克',
  'r&b': '节奏布鲁斯',
  'rap': '说唱',
  'reggae': '雷鬼',
  'rnb': '节奏布鲁斯',
  'rock': '摇滚',
  'shoegaze': '盯鞋',
  'soul': '灵魂乐',
  'soundtrack': '原声',
  'synth-pop': '合成器流行',
  'synthpop': '合成器流行',
  'techno': '铁克诺',
  'trance': '迷幻舞曲',
  'trip hop': '神游舞曲',
  'trot': '韩国演歌',
  'visual kei': '视觉系',
  'vocal': '人声',
  'vocaloid': '虚拟歌手',
  'world': '世界音乐',
};

/// Chinese name for one genre tag, or the tag itself when it is not in the
/// table (which includes everything already written in Chinese).
String genreLabel(String genre) {
  final trimmed = genre.trim();
  if (trimmed.isEmpty) {
    return trimmed;
  }
  return _genreNames[trimmed.toLowerCase()] ?? trimmed;
}

/// Splits one tag into the genres it may hold: servers write "Rock/Pop" or
/// "Rock, Pop" in a single field.
List<String> splitGenreTag(String tag) {
  return tag
      .split(RegExp(r'\s*[/,;|]\s*'))
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList();
}

/// A whole genre list (or one multi-genre tag) as one display string.
///
/// Duplicates collapse: "Rock/Pop" and "Pop" on two songs of the same artist
/// should read as two genres, not three.
String genreNamesLabel(Iterable<String> genres, {String separator = ' / '}) {
  final labels = <String>[];
  for (final genre in genres) {
    for (final part in splitGenreTag(genre)) {
      final label = genreLabel(part);
      if (label.isNotEmpty && !labels.contains(label)) {
        labels.add(label);
      }
    }
  }
  return labels.join(separator);
}
