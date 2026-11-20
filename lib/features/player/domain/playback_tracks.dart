// -------------------------------------------------------------------------
// 功能：播放轨道模型
//
// 主要内容：
// - 内嵌字幕轨道信息
// - 字幕选择模式（自动 / 关闭 / 指定轨道）
// - 播放器展示用的字幕状态快照
// -------------------------------------------------------------------------

/// 字幕当前的选择方式。
enum SubtitleSelectionMode { auto, off, track }

/// 字幕选择：自动策略、关闭，或指定一条当前文件内的轨道。
class SubtitleSelection {
  const SubtitleSelection.auto()
    : mode = SubtitleSelectionMode.auto,
      trackId = null;

  const SubtitleSelection.off()
    : mode = SubtitleSelectionMode.off,
      trackId = null;

  const SubtitleSelection.track(String id)
    : mode = SubtitleSelectionMode.track,
      trackId = id;

  final SubtitleSelectionMode mode;
  final String? trackId;

  @override
  bool operator ==(Object other) {
    return other is SubtitleSelection &&
        other.mode == mode &&
        other.trackId == trackId;
  }

  @override
  int get hashCode => Object.hash(mode, trackId);
}

/// 当前视频里的一条内嵌字幕轨。
///
/// [id] 是文件内的原始轨道 ID，名称和语言只用于展示。
class SubtitleTrackInfo {
  const SubtitleTrackInfo({
    required this.id,
    required this.title,
    required this.language,
    required this.codec,
    required this.isDefault,
    required this.isImage,
  });

  final String id;
  final String? title;
  final String? language;
  final String? codec;
  final bool isDefault;
  final bool isImage;

  /// 图片型字幕无法通过 Flutter 文本层显示。
  bool get supportsTextRendering {
    if (isImage) return false;
    final String value = (codec ?? '').toLowerCase();
    return !const <String>{
      'hdmv_pgs_subtitle',
      'pgssub',
      'dvd_subtitle',
      'dvb_subtitle',
      'dvb_teletext',
      'xsub',
    }.contains(value);
  }

  /// 语言标签；无法识别时返回原始语言码。
  String? get languageLabel {
    final String? value = language?.trim();
    if (value == null || value.isEmpty) return null;
    final String key = value.toLowerCase();
    return _languageNames[key] ?? value;
  }

  /// 列表主标题：优先文件内标题，其次语言，最后用序号兜底。
  String displayTitle(int index) {
    final String? value = title?.trim();
    if (value != null && value.isNotEmpty) return value;
    return languageLabel ?? '字幕 ${index + 1}';
  }

  static const Map<String, String> _languageNames = <String, String>{
    'zh': '中文',
    'chi': '中文',
    'zho': '中文',
    'zh-cn': '简体中文',
    'zh-hans': '简体中文',
    'zh-sg': '简体中文',
    'zh-tw': '繁体中文',
    'zh-hk': '繁体中文',
    'zh-hant': '繁体中文',
    'en': '英语',
    'eng': '英语',
    'ja': '日语',
    'jpn': '日语',
    'ko': '韩语',
    'kor': '韩语',
    'fr': '法语',
    'fre': '法语',
    'fra': '法语',
    'de': '德语',
    'ger': '德语',
    'deu': '德语',
    'es': '西班牙语',
    'spa': '西班牙语',
    'ru': '俄语',
    'rus': '俄语',
  };
}

/// 字幕面板使用的不可变状态快照。
class PlaybackSubtitles {
  const PlaybackSubtitles({
    required this.tracks,
    required this.selection,
    required this.loading,
  });

  const PlaybackSubtitles.loading()
    : tracks = const <SubtitleTrackInfo>[],
      selection = const SubtitleSelection.auto(),
      loading = true;

  final List<SubtitleTrackInfo> tracks;
  final SubtitleSelection selection;
  final bool loading;

  bool get hasTracks => tracks.isNotEmpty;
}
