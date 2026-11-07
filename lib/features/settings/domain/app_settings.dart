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
  fit('适应屏幕'),
  cover('填充'),
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
    );
  }
}
