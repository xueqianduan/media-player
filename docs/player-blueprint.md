# myplayer 功能蓝图与技术架构

> 定位：Android 为主的本地音视频播放器（音乐 + 视频双模式），单机、离线优先、无账号。
> 目标：不是"能播就行"的 Demo，而是打开就能日常用的完整播放器。

优先级说明：**P0** = 没有就不算播放器；**P1** = 决定"完善度"；**P2** = 差异化加分项。

---

## 一、能力地图（六大模块）

### 1. 播放内核

| 功能 | 说明 | 优先级 |
|---|---|---|
| 统一播放抽象 | `PlaybackEngine` 接口，音频/视频两套实现，UI 只依赖接口 | P0 |
| 队列管理 | 顺序 / 单曲循环 / 列表循环 / 随机；队列拖拽重排、下一首插入 | P0 |
| 断点续播 | 按文件记忆播放位置（音频 3 秒、视频 10 秒落库） | P0 |
| 播放历史 | 时间线记录，可"继续播放" | P0 |
| 错误容错 | 文件损坏/被删时自动跳过并提示，不崩队列 | P0 |
| 倍速播放 | 0.5x–3.0x，变调保持（pitch 不随速度走） | P1 |
| 睡眠定时器 | 定时暂停 / 播完当前曲 / 音量淡出 | P1 |
| 快进步长可配 | 10s / 30s / 60s，可改为"跳上一首/下一首" | P1 |
| 交叉淡入淡出 | 切歌 300–800ms 淡入淡出，避免爆音 | P2 |
| 无缝衔接 | gapless，专辑连播无间隙 | P2 |
| A-B 循环 | 片段循环，练琴/学语言场景 | P2 |

### 2. 媒体库

| 功能 | 说明 | 优先级 |
|---|---|---|
| 媒体扫描 | 通过 MediaStore 扫描（**不要**遍历文件系统） | P0 |
| 增量扫描 | 只处理新增/修改；支持排除目录（如微信语音）、最短时长过滤 | P1 |
| 元数据与封面 | 内嵌封面 → 同目录 `cover.jpg` → 在线兜底 → 渐变占位 | P0 |
| 四种归类 | 专辑 / 艺术家 / 文件夹 / 流派 | P0 |
| 搜索 | 标题、专辑、艺术家模糊匹配 + **拼音首字母**（中文刚需） | P1 |
| 收藏 / 最近 / 最常播放 | 三个自动歌单 | P0 |
| 播放列表 CRUD | 新建、重命名、拖动排序、删除；m3u 导入导出 | P1 |
| 歌词 | 内嵌 LRC → 同名 `.lrc` 外挂 → 在线搜索 | P0 |
| 歌词体验 | 逐行滚动、点击跳转、当前行放大、双语对照 | P0 |
| 逐字歌词 | 增强 LRC / KRC，卡拉 OK 高亮 | P2 |
| 标签编辑 | 改 ID3、批量重命名、封面替换 | P2 |
| 视频库 | 网格视图 + 缩略图 + 按时长/日期/文件夹分组 | P1 |
| 网络串流 | http / m3u8 / 局域网地址 | P2 |

### 3. 系统集成（Android 的分数主要在这里）

| 功能 | 说明 | 优先级 |
|---|---|---|
| 后台播放 | `audio_service` 前台服务 | P0 |
| 通知栏控制 | 大图样式、播放/暂停/上下曲/进度条 | P0 |
| 锁屏与线控 | 锁屏封面、蓝牙耳机、有线耳机按键（单击/双击） | P0 |
| 音频焦点 | 来电、其他 App 播放时暂停/降音量，结束后恢复 | P0 |
| 拔耳机自动暂停 | `audio_session` 的 becomingNoisy | P0 |
| 权限与电池引导 | 通知权限、忽略电池优化（防后台被杀） | P1 |
| 车载模式 | 大按钮简化界面 | P2 |
| 桌面歌词悬浮窗 | 需要 `SYSTEM_ALERT_WINDOW` 悬浮窗权限 | P2 |
| 桌面小组件 | AppWidget 显示当前曲目 | P2 |
| 输出设备切换 | 蓝牙 / 扬声器 / USB | P2 |

### 4. 视频能力

| 功能 | 说明 | 优先级 |
|---|---|---|
| 硬解多格式 | media_kit（libmpv）：MKV/HEVC/AV1 都能吃 | P1 |
| 手势层 | 双击暂停、横向拖进度、左侧亮度、右侧音量、双指缩放 | P1 |
| 字幕 | 外挂 SRT/ASS、内嵌轨切换、字号/颜色/描边/位置可调 | P1 |
| 音轨切换 | 多语言、多声道 | P1 |
| 全屏与方向 | 横屏全屏、方向锁定、沉浸式状态栏 | P1 |
| 画中画 | Android PiP | P2 |
| 截图 / 存 GIF | 一键截图、截取 3 秒动图 | P2 |
| 片头片尾跳过 | 记住上次跳过的位置 | P2 |
| 投屏 | DLNA / Chromecast | P2 |

### 5. 界面与个性化

| 功能 | 说明 | 优先级 |
|---|---|---|
| 迷你播放条 | 常驻底部，点击展开全屏播放页（滑动转场） | P0 |
| 全屏播放页 | 封面 + 歌词双页切换 | P0 |
| 主题 | 深色 / 浅色 / 跟随系统 + Material You 动态取色 | P0 |
| 封面取色 | 用封面主色渲染渐变背景与强调色 | P1 |
| 播放页布局 | 经典 / 黑胶 / 歌词优先 / 磁带 | P2 |
| 动效 | Hero 封面转场、进度条弹性、波形律动 | P1 |
| 多语言 | 中文 / 英文 | P1 |
| 无障碍 | 大字号、语义标签、对比度 | P2 |
| 平板 / 横屏 | 双栏自适应 | P2 |

### 6. 进阶与工程化

| 功能 | 说明 | 优先级 |
|---|---|---|
| 均衡器 | 10 段 EQ + 预设（摇滚/流行/人声/低音） | P2 |
| 音频可视化 | FFT 频谱 / 真实波形 | P2 |
| 播放统计 | 听歌时长、Top 艺人、年度报告 | P2 |
| 备份恢复 | 播放列表 + 进度导出到 WebDAV / 本地 JSON | P2 |
| 崩溃上报 | Sentry / Crashlytics | P1 |
| 结构化日志 | `logger` 分模块输出 | P1 |
| 单元测试 | 队列逻辑、LRC 解析、时长格式化 | P1 |
| CI | GitHub Actions 自动出 APK | P2 |

---

## 二、关键架构决策：双引擎如何统一

音乐和视频是两种完全不同的技术栈，最容易写成一锅粥。核心做法是**抽接口**：

```dart
abstract class PlaybackEngine {
  Stream<Duration> get positionStream;
  Stream<PlayerStatus> get statusStream;   // idle/buffering/playing/paused/completed/error
  Duration? get duration;

  Future<void> load(MediaItem item, {Duration? startAt, bool autoPlay});
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setSpeed(double speed);
  Future<void> setVolume(double volume);
  Future<void> dispose();
}
```

- `JustAudioEngine` → 音乐，配 `audio_service` 打通通知栏/锁屏/线控
- `MediaKitEngine` → 视频，字幕、多音轨、硬解交给 libmpv
- `PlaybackController`（Riverpod Notifier）持有当前引擎，对上层暴露统一的 `queue / currentItem / position / mode / speed`
- 切到视频时，音频引擎暂停并释放通知栏会话；退出视频再交还

**不要**试图用一个包同时干两件事：`video_player` 扛不住字幕和音轨，`just_audio` 不渲染画面。分引擎 + 统一接口是唯一干净的解法。

---

## 三、技术选型

```yaml
dependencies:
  # 播放
  just_audio: ^0.9.40            # 音频引擎
  audio_service: ^0.18.15        # 后台/通知/锁屏/线控
  audio_session: ^0.1.21         # 音频焦点、拔耳机
  media_kit: ^1.1.11             # 视频引擎
  media_kit_video: ^1.2.5
  media_kit_libs_android_video: ^1.3.6

  # 媒体库
  on_audio_query: ^2.9.0         # MediaStore 音频查询
  audio_metadata_reader: ^1.4.2  # 纯 Dart 读标签（放 isolate 跑）
  photo_manager: ^3.2.0          # 视频查询 + 缩略图
  permission_handler: ^11.3.1
  pinyin: ^3.2.0                 # 拼音首字母搜索

  # 数据
  drift: ^2.20.0
  sqlite3_flutter_libs: ^0.5.24
  path_provider: ^2.1.4
  shared_preferences: ^2.3.2

  # 状态与路由
  flutter_riverpod: ^2.5.3
  go_router: ^14.2.7
  freezed_annotation: ^2.4.4
  json_annotation: ^4.9.0

  # UI
  palette_generator: ^0.3.3+4
  dynamic_color: ^1.7.0
  cached_network_image: ^3.4.1
  audio_waveforms: ^1.2.0
  flutter_localizations: {sdk: flutter}
  intl: ^0.19.0

  # 体验
  volume_controller: ^2.0.7
  screen_brightness: ^0.2.2+1
  wakelock_plus: ^1.2.8
  share_plus: ^10.0.2
  logger: ^2.4.0
```

选型理由速记：
- **Drift 而非 Isar**：类型安全、SQL 可查、支持复杂排序分页，歌量大时更稳。
- **Riverpod 而非 Bloc**：播放器状态是"多源流式聚合"，Riverpod 的 `StreamProvider` 组合更省代码。
- **media_kit 而非 video_player**：字幕、多音轨、HEVC/AV1 全是刚需，官方包做不到。

---

## 四、目录结构

```
lib/
├── main.dart
├── app/
│   ├── app.dart                 # MaterialApp + 主题 + 本地化
│   ├── router.dart              # go_router 配置
│   └── theme/                   # 配色、文字、组件样式
├── core/
│   ├── constants.dart
│   ├── extensions/              # Duration、String、BuildContext 扩展
│   ├── utils/                   # 时长格式化、文件大小、拼音工具
│   └── errors/
├── data/
│   ├── db/                      # Drift 表定义 + DAO
│   ├── models/                  # DTO + freezed 实体
│   ├── media_store/             # MediaStore 查询与扫描
│   └── repositories/            # LibraryRepo / PlaylistRepo / HistoryRepo
├── domain/
│   ├── entities/                # MediaItem / Playlist / LyricLine
│   ├── repositories/            # 抽象接口
│   └── services/                # 歌词解析、搜索索引
├── services/
│   ├── playback/                # PlaybackEngine 接口 + 两套实现 + Controller
│   ├── audio_service/           # AudioHandler 实现
│   └── scanner/                 # 扫描任务调度
└── features/
    ├── home/                    # 首页（最近播放 + 推荐歌单）
    ├── library/                 # 专辑/艺术家/文件夹/流派
    ├── player/                  # 迷你条 + 全屏播放页 + 队列页
    ├── video/                   # 视频列表 + 播放器 + 手势层
    ├── playlist/
    ├── search/
    └── settings/
```

规则：**features 之间不互相 import**，公共能力下沉到 services / domain；所有 DB 与平台调用只能出现在 data / services 层。

---

## 五、数据模型

```
tracks
  id TEXT PK          path TEXT UNIQUE
  title / artist / album / album_id / genre
  duration_ms INT     size_bytes INT     mime_type TEXT
  track_no INT        year INT           bitrate INT
  cover_path TEXT     has_embedded_cover BOOL
  date_added INT      last_modified INT
  is_favorite BOOL     play_count INT    last_played_at INT
  resume_position_ms INT

videos
  id TEXT PK          path TEXT UNIQUE
  title / folder / duration_ms / width / height / fps
  thumbnail_path TEXT  date_added INT
  subtitle_tracks TEXT (json)  audio_tracks TEXT (json)
  resume_position_ms INT   play_count INT

playlists
  id TEXT PK   name TEXT   cover_path TEXT
  created_at INT   sort_order INT   is_system BOOL

playlist_items
  id TEXT PK   playlist_id FK   track_id FK   position INT

play_history
  id TEXT PK   media_id FK   media_type INT
  played_at INT   position_ms INT   completed BOOL

lyrics_cache
  media_id TEXT PK   offset_ms INT   source TEXT   content TEXT

app_settings
  key TEXT PK   value TEXT      # 主题、倍速、快进步长等
```

要点：
- 路径唯一约束 + `last_modified` 做增量扫描判断
- `resume_position_ms` 直接挂在媒体表上，比单独表更省一次 join
- 系统歌单（收藏/最近/最常）用 `is_system` 标记，不参与用户编辑

---

## 六、开发路线图

| 阶段 | 内容 | 验收标准 |
|---|---|---|
| **0. 地基** | 工程分层、路由、主题、Drift 建表、假数据打通 | 三个页面能跳转，列表数据来自数据库 |
| **1. 能播** | 音频引擎 + 队列 + 迷你条 + 全屏播放页 + 进度拖动 | 选一首能播、能拖、能切歌、退出重进位置还在 |
| **2. 建库** | 权限申请 + MediaStore 扫描 + 四种归类 + 搜索 + 封面 + 歌词 | 1000 首曲库冷启 3 秒内出列表，搜索有响应 |
| **3. 进系统** | audio_service 全套：后台、通知栏、锁屏、耳机、音频焦点 | 息屏播放不断、来电暂停后恢复、拔耳机暂停 |
| **4. 上视频** | media_kit + 手势层 + 字幕 + 横屏全屏 + 进度记忆 | 1080p HEVC 硬解流畅，外挂 ASS 字幕正常渲染 |
| **5. 打磨** | 封面取色、动效、均衡器、统计、备份恢复、多语言 | 冷启 < 1.5s，滑 500 条列表不掉帧，无 OOM |

建议每阶段结束打个 git tag，出 APK 装到真机上跑一天——播放器的问题几乎全是真机才暴露的。

---

## 七、Android 平台坑位清单

### 权限（Manifest）

```xml
<uses-permission android:name="android.permission.READ_MEDIA_AUDIO"/>      <!-- 13+ -->
<uses-permission android:name="android.permission.READ_MEDIA_VIDEO"/>      <!-- 13+ -->
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"
                 android:maxSdkVersion="32"/>                              <!-- 12- -->
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>     <!-- 13+ -->
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK"/>
<uses-permission android:name="android.permission.WAKE_LOCK"/>
```

### 前台服务（Android 14 强制要求 type）

```xml
<service android:name="com.ryanheise.audioservice.AudioService"
         android:foregroundServiceType="mediaPlayback"
         android:exported="true">
  <intent-filter>
    <action android:name="android.media.browse.MediaBrowserService"/>
  </intent-filter>
</service>

<receiver android:name="com.ryanheise.audioservice.MediaButtonReceiver"
          android:exported="true">
  <intent-filter>
    <action android:name="android.intent.action.MEDIA_BUTTON"/>
  </intent-filter>
</receiver>
```

`MainActivity` 必须继承 `AudioServiceActivity`：

```kotlin
class MainActivity : AudioServiceActivity()
```

### 高频踩坑

1. **别遍历文件系统**：Android 10+ 分区存储，`Directory.list()` 拿不到音乐目录。只能走 MediaStore 或 SAF。
2. **别在主 isolate 解析标签**：1000 个文件同步读 ID3 会卡死启动，用 `Isolate.run()` 分批（每批 50 个）回调进度。
3. **封面 OOM**：列表里的封面必须 `cacheWidth`，否则 3000×3000 的图铺满 60 行直接爆内存。
4. **通知栏图标必须是纯白剪影**，彩色图标在通知栏会变成白方块。
5. **后台被杀**：引导用户关闭电池优化，否则熄屏几分钟服务就被系统回收（国产 ROM 尤其狠）。
6. **`audio_service` 的 `MediaItem.id` 必须唯一且稳定**，用文件路径 hash，不要用列表索引。
7. **视频手势与系统手势冲突**：左右边缘 20dp 内不要拦截横滑，否则返回手势失效。

---

## 八、性能红线

| 指标 | 目标 |
|---|---|
| 冷启动到首页可交互 | < 1.5s |
| 库扫描 1000 首 | < 6s（后台，带进度条） |
| 列表滚动帧率 | 稳定 60fps（用 `itemExtent` + 复用） |
| 内存峰值（含封面缓存） | < 250MB |
| 后台播放耗电 | 1 小时 < 3% |
| 通知栏响应延迟 | < 100ms |

---

## 九、可以砍掉的（避免贪多）

- 在线音乐源 / 版权曲库搜索 → 法务与维护成本高，单机播放器不需要
- 社交、评论、云歌单 → 需要后端，偏离"本地播放器"定位
- 大量皮肤主题 → 维护成本高，做 2–3 个高质量布局足够
- 复杂推荐算法 → 本地数据量撑不起来，用"最近/最常"就够

保持单机、离线、无账号，是这个项目最容易做扎实的路线。
