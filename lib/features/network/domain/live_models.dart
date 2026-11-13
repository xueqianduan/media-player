/// 网络模块（B 站直播）的领域模型。
///
/// 只保存「用户的选择」（直播间信息、组合、收藏），播放地址在每次播放前
/// 重新向接口获取，避免把容易失效的直链长期留在本地。
library;

/// 直播间 / 主播的搜索结果。
class LiveRoom {
  const LiveRoom({
    required this.roomId,
    required this.uid,
    required this.name,
    this.title = '',
    this.live = false,
    this.coverUrl = '',
    this.avatarUrl = '',
    this.isUp = false,
  });

  /// 真实房间号（长号）。
  final int roomId;

  /// 主播 UID。
  final int uid;

  /// 主播昵称。
  final String name;

  /// 直播间标题。
  final String title;

  /// 是否正在直播（搜索时的快照，播放前会重新校验）。
  final bool live;

  /// 直播间封面。
  final String coverUrl;

  /// 主播头像。与封面分开保存，避免把直播封面当头像。
  final String avatarUrl;

  /// 是否来自「主播」搜索结果（而不是直播间）。
  final bool isUp;

  /// 用于列表副标题：主播 / 直播间。
  String get categoryLabel => isUp ? 'B站 · 主播' : 'B站 · 直播间';

  LiveRoom copyWith({
    String? name,
    String? title,
    bool? live,
    String? coverUrl,
    String? avatarUrl,
  }) {
    return LiveRoom(
      roomId: roomId,
      uid: uid,
      name: name ?? this.name,
      title: title ?? this.title,
      live: live ?? this.live,
      coverUrl: coverUrl ?? this.coverUrl,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      isUp: isUp,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'roomId': roomId,
    'uid': uid,
    'name': name,
    'title': title,
    'live': live,
    'coverUrl': coverUrl,
    'avatarUrl': avatarUrl,
    'isUp': isUp,
  };

  static LiveRoom? fromJson(Object? value) {
    if (value is! Map) return null;
    final Map<String, dynamic> json = Map<String, dynamic>.from(value);
    final int roomId = (json['roomId'] as num?)?.toInt() ?? 0;
    if (roomId <= 0) return null;
    return LiveRoom(
      roomId: roomId,
      uid: (json['uid'] as num?)?.toInt() ?? 0,
      name: json['name'] as String? ?? '未命名直播间',
      title: json['title'] as String? ?? '',
      live: json['live'] as bool? ?? false,
      coverUrl: json['coverUrl'] as String? ?? '',
      // 旧数据没有头像字段：留空由界面用占位图，不把封面当头像。
      avatarUrl: json['avatarUrl'] as String? ?? '',
      isUp: json['isUp'] as bool? ?? false,
    );
  }
}

/// 一次取流返回的播放地址候选。
class LiveStream {
  const LiveStream({
    required this.url,
    required this.format,
    required this.quality,
    required this.headers,
  });

  final String url;
  final String format;
  final int quality;
  final Map<String, String> headers;
}

/// 弹幕来源（独立于声音选择）。
enum DanmakuSource { off, picture, voice }

extension DanmakuSourceX on DanmakuSource {
  String get label {
    switch (this) {
      case DanmakuSource.off:
        return '关闭';
      case DanmakuSource.picture:
        return '画面直播间';
      case DanmakuSource.voice:
        return '声音直播间';
    }
  }

  static DanmakuSource fromName(String? value) {
    for (final DanmakuSource source in DanmakuSource.values) {
      if (source.name == value) return source;
    }
    return DanmakuSource.off;
  }
}

/// 直播画质档位。
class LiveQuality {
  const LiveQuality({required this.qn, required this.label});

  final int qn;
  final String label;

  static String labelOf(int qn) {
    switch (qn) {
      case 30000:
        return '杜比';
      case 20000:
        return '4K';
      case 10000:
        return '原画';
      case 400:
        return '蓝光';
      case 250:
        return '超清';
      case 150:
        return '高清';
      case 80:
        return '流畅';
      default:
        return '清晰度 $qn';
    }
  }

  @override
  bool operator ==(Object other) => other is LiveQuality && other.qn == qn;

  @override
  int get hashCode => qn.hashCode;
}

/// 一次取流结果：候选地址 + 可选画质 + 实际生效画质。
class LivePlaylist {
  const LivePlaylist({
    required this.streams,
    this.qualities = const <LiveQuality>[],
    this.currentQn = 0,
  });

  final List<LiveStream> streams;
  final List<LiveQuality> qualities;
  final int currentQn;
}

/// 直播进度：用户主动回拖的落后时长 + 可回退窗口。
///
/// 直播时缓存会一直领先播放位置，那不是「落后」，进度条应当保持满格。
/// 这里只记录用户拖动产生的落后量：behind = 0 表示正在看直播。
class LiveProgress {
  const LiveProgress({
    this.position = Duration.zero,
    this.behind = Duration.zero,
    this.liveEdge = Duration.zero,
    this.window = const Duration(seconds: 40),
  });

  /// 当前播放位置（相对本路流起点），用于换算拖动目标。
  final Duration position;

  /// 用户主动回拖造成的落后时长，0 表示在直播边缘。
  final Duration behind;

  /// 缓存末尾的绝对时间，用于「回到直播」定位。
  final Duration liveEdge;

  /// 可回退的最大窗口。
  final Duration window;

  bool get available =>
      liveEdge > const Duration(seconds: 1) && window > Duration.zero;

  /// 进度条比例：直播时恒为 1。
  double get fraction {
    if (!available || atLive) return 1;
    final double value = 1 - behind.inMilliseconds / window.inMilliseconds;
    return value.clamp(0.0, 1.0);
  }

  /// 3 秒以内视为直播。
  bool get atLive => !available || behind <= const Duration(seconds: 3);

  /// 落后时长。
  Duration get lag => behind;

  /// 把滑块比例换算成绝对跳转位置。
  Duration targetFor(double value) {
    final int requestedMs =
        ((1 - value.clamp(0.0, 1.0)) * window.inMilliseconds).round();
    final Duration requested = Duration(milliseconds: requestedMs);
    final Duration delta = behind - requested;
    final Duration target = position + delta;
    return target.isNegative ? Duration.zero : target;
  }
}

/// 双路观赛组合：画面来源 + 可选声音来源 + 弹幕来源。
class LivePreset {
  const LivePreset({
    this.picture,
    this.voice,
    this.danmaku = DanmakuSource.off,
  });

  final LiveRoom? picture;
  final LiveRoom? voice;
  final DanmakuSource danmaku;

  bool get isEmpty => picture == null;

  LivePreset copyWith({
    LiveRoom? picture,
    LiveRoom? voice,
    bool clearVoice = false,
    DanmakuSource? danmaku,
  }) {
    return LivePreset(
      picture: picture ?? this.picture,
      voice: clearVoice ? null : (voice ?? this.voice),
      danmaku: danmaku ?? this.danmaku,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'picture': picture?.toJson(),
    'voice': voice?.toJson(),
    'danmaku': danmaku.name,
  };

  static LivePreset fromJson(Object? value) {
    if (value is! Map) return const LivePreset();
    final Map<String, dynamic> json = Map<String, dynamic>.from(value);
    // 旧组合没有弹幕字段，按关闭处理。
    return LivePreset(
      picture: LiveRoom.fromJson(json['picture']),
      voice: LiveRoom.fromJson(json['voice']),
      danmaku: DanmakuSourceX.fromName(json['danmaku'] as String?),
    );
  }
}

/// 收藏的直播组合：画面 + 可选声音 + 弹幕来源。
class SavedLivePreset {
  const SavedLivePreset({
    required this.id,
    required this.preset,
    required this.savedAt,
  });

  final String id;
  final LivePreset preset;
  final DateTime savedAt;

  /// 去重键：同一对房间 + 同一弹幕来源只保留一条。
  String get key => keyOf(preset);

  static String keyOf(LivePreset preset) =>
      '${preset.picture?.roomId ?? 0}|'
      '${preset.voice?.roomId ?? 0}|'
      '${preset.danmaku.name}';

  String get title {
    final String picture = preset.picture?.name ?? '未知直播间';
    final String? voice = preset.voice?.name;
    return voice == null ? picture : '$picture · $voice';
  }

  String get subtitle {
    final String picture = '画面 ${preset.picture?.roomId ?? 0}';
    final String voice = preset.voice == null
        ? '原声'
        : '声音 ${preset.voice!.roomId}';
    return '$picture · $voice · 弹幕 ${preset.danmaku.label}';
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'preset': preset.toJson(),
    'savedAt': savedAt.toIso8601String(),
  };

  static SavedLivePreset? fromJson(Object? value) {
    if (value is! Map) return null;
    final Map<String, dynamic> json = Map<String, dynamic>.from(value);
    final LivePreset preset = LivePreset.fromJson(json['preset']);
    if (preset.picture == null) return null;
    return SavedLivePreset(
      id: '${json['id'] ?? DateTime.now().microsecondsSinceEpoch}',
      preset: preset,
      savedAt: DateTime.tryParse('${json['savedAt']}') ?? DateTime.now(),
    );
  }
}

/// 收藏的直播间。
class LiveFavorite {
  const LiveFavorite({required this.room, required this.savedAt});

  final LiveRoom room;
  final DateTime savedAt;

  LiveFavorite copyWith({LiveRoom? room}) =>
      LiveFavorite(room: room ?? this.room, savedAt: savedAt);

  Map<String, dynamic> toJson() => <String, dynamic>{
    'room': room.toJson(),
    'savedAt': savedAt.toIso8601String(),
  };

  static LiveFavorite? fromJson(Object? value) {
    if (value is! Map) return null;
    final Map<String, dynamic> json = Map<String, dynamic>.from(value);
    final LiveRoom? room = LiveRoom.fromJson(json['room']);
    if (room == null) return null;
    return LiveFavorite(
      room: room,
      savedAt: DateTime.tryParse('${json['savedAt']}') ?? DateTime.now(),
    );
  }
}

/// 网络视频（视频 tab）保存的直链。
class NetworkVideo {
  const NetworkVideo({
    required this.id,
    required this.name,
    required this.url,
    required this.savedAt,
  });

  final String id;
  final String name;
  final String url;
  final DateTime savedAt;

  String get format {
    final String base = url.split('?').first;
    final int dot = base.lastIndexOf('.');
    if (dot < 0 || dot == base.length - 1) return '视频';
    return base.substring(dot + 1).toLowerCase();
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'url': url,
    'savedAt': savedAt.toIso8601String(),
  };

  static NetworkVideo? fromJson(Object? value) {
    if (value is! Map) return null;
    final Map<String, dynamic> json = Map<String, dynamic>.from(value);
    final String url = json['url'] as String? ?? '';
    if (url.isEmpty) return null;
    return NetworkVideo(
      id: json['id'] as String? ?? url,
      name: json['name'] as String? ?? '网络视频',
      url: url,
      savedAt: DateTime.tryParse('${json['savedAt']}') ?? DateTime.now(),
    );
  }
}

/// 网络模块的持久化状态。
class NetworkState {
  const NetworkState({
    this.favorites = const <LiveFavorite>[],
    this.preset = const LivePreset(),
    this.savedPresets = const <SavedLivePreset>[],
    this.videos = const <NetworkVideo>[],
  });

  final List<LiveFavorite> favorites;
  final LivePreset preset;

  /// 用户主动收藏的直播组合。
  final List<SavedLivePreset> savedPresets;
  final List<NetworkVideo> videos;

  bool isFavorite(int roomId) =>
      favorites.any((LiveFavorite item) => item.room.roomId == roomId);

  NetworkState copyWith({
    List<LiveFavorite>? favorites,
    LivePreset? preset,
    List<SavedLivePreset>? savedPresets,
    List<NetworkVideo>? videos,
  }) {
    return NetworkState(
      favorites: favorites ?? this.favorites,
      preset: preset ?? this.preset,
      savedPresets: savedPresets ?? this.savedPresets,
      videos: videos ?? this.videos,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'favorites': favorites.map((LiveFavorite item) => item.toJson()).toList(),
    'preset': preset.toJson(),
    'savedPresets': savedPresets
        .map((SavedLivePreset item) => item.toJson())
        .toList(),
    'videos': videos.map((NetworkVideo item) => item.toJson()).toList(),
  };

  static NetworkState fromJson(Object? value) {
    if (value is! Map) return const NetworkState();
    final Map<String, dynamic> json = Map<String, dynamic>.from(value);

    List<LiveFavorite> favorites = <LiveFavorite>[];
    final Object? favoriteRows = json['favorites'];
    if (favoriteRows is List) {
      favorites = favoriteRows
          .map(LiveFavorite.fromJson)
          .whereType<LiveFavorite>()
          .toList();
    }

    final List<NetworkVideo> videos = <NetworkVideo>[];
    final Object? videoRows = json['videos'];
    if (videoRows is List) {
      for (final Object? row in videoRows) {
        final NetworkVideo? video = NetworkVideo.fromJson(row);
        if (video != null) videos.add(video);
      }
    }

    final List<SavedLivePreset> savedPresets = <SavedLivePreset>[];
    final Object? presetRows = json['savedPresets'];
    if (presetRows is List) {
      for (final Object? row in presetRows) {
        final SavedLivePreset? item = SavedLivePreset.fromJson(row);
        if (item != null) savedPresets.add(item);
      }
    }

    return NetworkState(
      favorites: favorites,
      preset: LivePreset.fromJson(json['preset']),
      savedPresets: savedPresets,
      videos: videos,
    );
  }
}
