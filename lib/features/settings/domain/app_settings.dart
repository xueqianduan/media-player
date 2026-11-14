// -------------------------------------------------------------------------
// 功能：设置模型
//
// 主要内容：
// - 主题模式、视图模式等枚举
// - AppSettings 聚合与序列化
// -------------------------------------------------------------------------

import '../../library/domain/models.dart';

/// 主题模式（不依赖 Flutter，便于持久化与测试）。
enum AppThemeMode {
  system('跟随系统'),
  light('浅色模式'),
  dark('深色模式');

  const AppThemeMode(this.label);

  final String label;

  static AppThemeMode parse(String? value) {
    return AppThemeMode.values.firstWhere(
      (AppThemeMode mode) => mode.name == value,
      orElse: () => AppThemeMode.system,
    );
  }
}

/// 播放器画面尺寸。
enum VideoScaleMode {
  original('原始比例'),
  fit('常规'),
  cover('铺满'),
  stretch('拉伸');

  const VideoScaleMode(this.label);

  final String label;

  static VideoScaleMode parse(String? value) {
    return VideoScaleMode.values.firstWhere(
      (VideoScaleMode mode) => mode.name == value,
      orElse: () => VideoScaleMode.fit,
    );
  }
}

/// 应用设置。
class AppSettings {
  const AppSettings({
    this.themeMode = AppThemeMode.system,
    this.defaultSpeed = 1.0,
    this.gesturesEnabled = true,
    this.resumePrompt = true,
    this.keepScreenOn = true,
    this.sortOption = SortOption.dateAdded,
    this.viewMode = ViewMode.list,
    this.playlistRepeatMode = RepeatMode.loopAll,
    this.longPressSpeed = 2.0,
    this.videoScaleMode = VideoScaleMode.fit,
    this.screenshotTipShown = false,
    this.danmakuEnabled = true,
    this.danmakuArea = 0.5,
    this.danmakuOpacity = 0.8,
    this.danmakuFontScale = 1.0,
    this.danmakuSpeed = 1.0,
  });

  /// 播放倍速：0.5x ~ 5.0x。
  static const List<double> speedOptions = <double>[
    0.5,
    0.75,
    1.0,
    1.5,
    2.0,
    2.5,
    3.0,
    3.5,
    4.0,
    4.5,
    5.0,
  ];

  /// 长按画面时的临时倍速，最高支持 5x。
  static const List<double> longPressSpeedOptions = <double>[
    1.5,
    2.0,
    2.5,
    3.0,
    3.5,
    4.0,
    4.5,
    5.0,
  ];

  final AppThemeMode themeMode;
  final double defaultSpeed;
  final bool gesturesEnabled;
  final bool resumePrompt;
  final bool keepScreenOn;
  final SortOption sortOption;
  final ViewMode viewMode;

  /// 播放列表的默认播放模式：列表循环 / 单集循环 / 不循环。
  final RepeatMode playlistRepeatMode;

  /// 长按画面时的临时倍速。
  final double longPressSpeed;

  /// 播放器画面尺寸。
  final VideoScaleMode videoScaleMode;

  /// 是否已经提示过「截图会保存到相册」。
  final bool screenshotTipShown;

  // ===== 直播飘屏弹幕（横屏） =====

  /// 横屏飘屏是否开启。
  final bool danmakuEnabled;

  /// 弹幕显示区域：屏幕高度的 10% / 25% / 50% / 75% / 100%。
  final double danmakuArea;

  /// 弹幕不透明度：0.2 ~ 1.0。
  final double danmakuOpacity;

  /// 字号缩放：0.5 ~ 2.0。
  final double danmakuFontScale;

  /// 速度倍率：0.5 ~ 2.0，越大越快。
  final double danmakuSpeed;

  AppSettings copyWith({
    AppThemeMode? themeMode,
    double? defaultSpeed,
    bool? gesturesEnabled,
    bool? resumePrompt,
    bool? keepScreenOn,
    SortOption? sortOption,
    ViewMode? viewMode,
    RepeatMode? playlistRepeatMode,
    double? longPressSpeed,
    VideoScaleMode? videoScaleMode,
    bool? screenshotTipShown,
    bool? danmakuEnabled,
    double? danmakuArea,
    double? danmakuOpacity,
    double? danmakuFontScale,
    double? danmakuSpeed,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      defaultSpeed: defaultSpeed ?? this.defaultSpeed,
      gesturesEnabled: gesturesEnabled ?? this.gesturesEnabled,
      resumePrompt: resumePrompt ?? this.resumePrompt,
      keepScreenOn: keepScreenOn ?? this.keepScreenOn,
      sortOption: sortOption ?? this.sortOption,
      viewMode: viewMode ?? this.viewMode,
      playlistRepeatMode: playlistRepeatMode ?? this.playlistRepeatMode,
      longPressSpeed: longPressSpeed ?? this.longPressSpeed,
      videoScaleMode: videoScaleMode ?? this.videoScaleMode,
      screenshotTipShown: screenshotTipShown ?? this.screenshotTipShown,
      danmakuEnabled: danmakuEnabled ?? this.danmakuEnabled,
      danmakuArea: danmakuArea ?? this.danmakuArea,
      danmakuOpacity: danmakuOpacity ?? this.danmakuOpacity,
      danmakuFontScale: danmakuFontScale ?? this.danmakuFontScale,
      danmakuSpeed: danmakuSpeed ?? this.danmakuSpeed,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'themeMode': themeMode.name,
    'defaultSpeed': defaultSpeed,
    'gesturesEnabled': gesturesEnabled,
    'resumePrompt': resumePrompt,
    'keepScreenOn': keepScreenOn,
    'sortOption': sortOption.name,
    'viewMode': viewMode.name,
    'playlistRepeatMode': playlistRepeatMode.name,
    'longPressSpeed': longPressSpeed,
    'videoScaleMode': videoScaleMode.name,
    'screenshotTipShown': screenshotTipShown,
    'danmakuEnabled': danmakuEnabled,
    'danmakuArea': danmakuArea,
    'danmakuOpacity': danmakuOpacity,
    'danmakuFontScale': danmakuFontScale,
    'danmakuSpeed': danmakuSpeed,
  };

  static AppSettings fromJson(Map<String, dynamic> json) {
    return AppSettings(
      themeMode: AppThemeMode.parse(json['themeMode'] as String?),
      defaultSpeed: (json['defaultSpeed'] as num?)?.toDouble() ?? 1.0,
      gesturesEnabled: json['gesturesEnabled'] as bool? ?? true,
      resumePrompt: json['resumePrompt'] as bool? ?? true,
      keepScreenOn: json['keepScreenOn'] as bool? ?? true,
      sortOption: SortOption.parse(json['sortOption'] as String?),
      viewMode: ViewMode.parse(json['viewMode'] as String?),
      playlistRepeatMode: json['playlistRepeatMode'] == null
          ? RepeatMode.loopAll
          : RepeatMode.values.firstWhere(
              (RepeatMode mode) =>
                  mode.name == json['playlistRepeatMode'] as String,
              orElse: () => RepeatMode.loopAll,
            ),
      longPressSpeed: (json['longPressSpeed'] as num?)?.toDouble() ?? 2.0,
      videoScaleMode: VideoScaleMode.parse(json['videoScaleMode'] as String?),
      screenshotTipShown: json['screenshotTipShown'] as bool? ?? false,
      danmakuEnabled: json['danmakuEnabled'] as bool? ?? true,
      danmakuArea: ((json['danmakuArea'] as num?)?.toDouble() ?? 0.5).clamp(
        0.1,
        1.0,
      ),
      danmakuOpacity: ((json['danmakuOpacity'] as num?)?.toDouble() ?? 0.8)
          .clamp(0.2, 1.0),
      danmakuFontScale: ((json['danmakuFontScale'] as num?)?.toDouble() ?? 1.0)
          .clamp(0.6, 1.6),
      danmakuSpeed: ((json['danmakuSpeed'] as num?)?.toDouble() ?? 1.0).clamp(
        0.5,
        2.0,
      ),
    );
  }
}
