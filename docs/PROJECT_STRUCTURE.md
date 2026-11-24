# LumiPlayer 工程目录结构说明

> 统计时间：2026-11-24　版本 `1.2.0+9`
>
> 范围：工程根目录概览 + `lib/` 完整明细（91 个 Dart 文件，28,262 行）+ 测试与原生桥接
>
> 本文回答：每个目录是干什么的、里面有哪些文件、每个文件负责什么。
>
> 不展开 `.dart_tool/`、`build/`、`.gradle/` 等生成目录和平台模板文件。

---

## 1. 工程根目录

```text
myplayer/
├── lib/                         Flutter 业务代码
├── android/                     Android 工程与原生桥接
│   └── app/src/main/
│       ├── AndroidManifest.xml
│       ├── kotlin/com/example/myplayer/
│       │   ├── MainActivity.kt
│       │   └── transfer/        TLS / 文件流 / MethodChannel
│       └── res/raw/             transfer_identity.p12
├── assets/icon/                 应用图标源文件与成品
├── docs/                        架构、需求、协议、预览图、工作记录
├── integration_test/            端到端流程测试
├── test/                        单元 / Widget / 预览测试
├── tool/                        开发与图标生成脚本
├── ios/ macos/ linux/ windows/  Flutter 平台工程
├── web/                         Web 平台工程
├── .github/workflows/           CI
├── pubspec.yaml                 依赖与版本号
└── README.md                    功能概览与构建说明
```

| 目录 | 作用 | 主要内容 |
| --- | --- | --- |
| `lib/` | 全部 Dart 业务代码 | 4 层架构；详见下文 |
| `android/` | Android 容器 | `MainActivity`、B 站 Cookie 通道、SAF 选择器、文件传输原生实现 |
| `assets/icon/` | 品牌资源 | `app_icon.png`、`app_icon_source.jpg` |
| `docs/` | 项目文档 | 架构、目录、需求、实施方案、协议、预览图、工作记录 |
| `test/` | 自动化测试 | 单元、Widget、预览、测试假件 |
| `integration_test/` | 端到端测试 | `app_flow_test.dart` |
| `tool/` | 本地工具 | `dev.sh`、`generate_icons.py` |
| `.github/workflows/` | CI | `flutter-ci.yml` |
| 各平台目录 | Flutter 宿主工程 | 除原生通道外基本沿用模板 |

---

## 2. `lib/` 目录树

```text
lib/
├── main.dart                       应用入口
├── app/                            应用级装配
│   ├── app.dart
│   ├── bootstrap.dart
│   ├── providers.dart
│   └── router.dart
├── core/                           跨模块基础设施
│   ├── database/local_database.dart
│   ├── theme/app_theme.dart
│   ├── utils/formatters.dart
│   └── widgets/
│       ├── ui_kit.dart
│       └── dialogs.dart
└── features/                       业务模块
    ├── library/                    本地视频库
    │   ├── domain/models.dart
    │   ├── data/                   扫描 / 导入 / 探测 / 解析 / 缩略图 / 仓储
    │   ├── application/library_controller.dart
    │   └── presentation/           首页、列表、搜索、动作 + widgets/
    ├── player/                     本地播放器
    │   ├── domain/                 引擎接口、会话、队列、字幕与音轨
    │   ├── data/media_kit_engine.dart
    │   └── presentation/player_page.dart
    ├── network/                    B 站直播与网络视频
    │   ├── domain/                 直播与弹幕模型
    │   ├── data/                   接口、登录、WBI、弹幕、双路会话
    │   ├── application/            网络状态、B 站账号
    │   └── presentation/           网络页、搜索、登录、播放器 + widgets/
    ├── transfer/                   局域网文件传输
    │   ├── domain/                 文件/记录模型、会话状态
    │   ├── data/                   平台桥接、历史仓储
    │   ├── application/            记录控制器、当前会话控制器
    │   └── presentation/           首页、选文件、亮码、扫码、任务、历史
    ├── settings/                   设置
    ├── category/                   分类管理与详情
    ├── playlist/                   播放列表管理与详情
    ├── favorites/                  收藏页
    ├── history/                    最近播放
    ├── profile/                    「我的」
    ├── shell/                      底部导航壳
    └── magnet/                     磁力占位页（已无导航入口）
```

---

## 3. 分层约定

`features/<模块>/` 内部按四层组织，缺层就不建目录：

| 层 | 目录 | 能做什么 | 不能做什么 |
| --- | --- | --- | --- |
| 领域 | `domain/` | 纯 Dart 实体、枚举、状态、序列化 | 不 import Flutter，不发请求，不读文件 |
| 数据 | `data/` | 接口请求、文件读写、持久化、平台能力 | 不持有 UI 状态 |
| 应用 | `application/` | Riverpod `Notifier`，编排 data → 暴露给 UI | 不写 Widget |
| 表现 | `presentation/` | 页面、组件、交互 | 不直接碰数据库/网络 |

依赖方向单向：`presentation → application → data → domain`。

例外：`player` 没有 `application/`，由 `PlaybackSession` 直接协调引擎；只有页面的模块复用 `library` 或 `network` 的控制器，不单独建仓储。

---

## 4. `lib/` 规模

| 位置 | 文件数 | 行数 | 说明 |
| --- | ---: | ---: | --- |
| `main.dart` | 1 | 13 | 应用入口 |
| `app/` | 4 | 428 | 启动、路由、全局 Provider |
| `core/` | 5 | 999 | 数据库、主题、工具、通用组件 |
| `library/` | 17 | 5,456 | 本地视频库（最大单模块） |
| `network/` | 30 | 10,606 | B 站直播与网络视频（文件最多） |
| `player/` | 6 | 3,957 | 播放引擎、会话、轨道、播放页 |
| `transfer/` | 13 | 3,300 | 文件传输完整链路 |
| `settings/` | 6 | 1,530 | 设置 |
| `playlist/` | 2 | 553 | 播放列表 |
| `category/` | 2 | 312 | 分类 |
| `favorites/` | 1 | 207 | 收藏 |
| `history/` | 1 | 312 | 最近播放 |
| `profile/` | 1 | 328 | 我的 |
| `shell/` | 1 | 159 | 导航壳 |
| `magnet/` | 1 | 102 | 磁力占位 |
| **合计** | **91** | **28,262** | — |

### 4.1 `lib/` 顶层

| 文件 | 行数 | 作用 |
| --- | ---: | --- |
| `main.dart` | 13 | 初始化插件与数据库，挂载 `ProviderScope` 和 `LumiPlayerApp` |

---

## 5. `lib/app/` —— 应用级装配

| 文件 | 行数 | 作用 | 关键内容 |
| --- | ---: | --- | --- |
| `app.dart` | 56 | 根组件 | `LumiPlayerApp`、`MaterialApp.router`、中文本地化、全局字号缩放 |
| `bootstrap.dart` | 64 | 启动初始化 | 打开数据库、初始化 `media_kit`、启动异常兜底 |
| `providers.dart` | 65 | 全局 Provider | 数据库、初始媒体库、初始设置、扫描器 |
| `router.dart` | 243 | 路由表 | `/`、`/videos`、`/network/*`、`/transfer/*`、播放器及参数兜底 |

---

## 6. `lib/core/` —— 跨模块基础设施

### 6.1 `core/database/`

| 文件 | 行数 | 作用 | 关键内容 |
| --- | ---: | --- | --- |
| `local_database.dart` | 160 | 单 JSON 持久化 | `schemaVersion`（当前 2）、`migrate()`、`readTable()` / `writeTable()`、`flush()` |

### 6.2 `core/theme/`

| 文件 | 行数 | 作用 | 关键内容 |
| --- | ---: | --- | --- |
| `app_theme.dart` | 173 | 主题 | `AppColors`、`AppTheme.light()/dark()`、`context.textPrimary` 等取色扩展 |

### 6.3 `core/utils/`

| 文件 | 行数 | 作用 | 关键内容 |
| --- | ---: | --- | --- |
| `formatters.dart` | 69 | 展示格式化 | `formatDuration`、`formatBytes`、`formatDateTime`、`formatRelativeTime`、`formatResolution` |

### 6.4 `core/widgets/`

| 文件 | 行数 | 作用 | 关键内容 |
| --- | ---: | --- | --- |
| `ui_kit.dart` | 455 | 通用组件库 | `PageHeader`、`SectionHeader`、`AppCard`、`EmptyState`、`SoftIconBadge`、`AppIconButton`、`SheetHeader`、`SheetActionTile` |
| `dialogs.dart` | 142 | 通用对话框 | `showConfirmDialog`、`showTextInputDialog` |

---

## 7. `lib/features/` —— 模块总览

| 模块 | 职责 | domain | data | application | presentation |
| --- | --- | :---: | :---: | :---: | :---: |
| `library` | 扫描、文件夹、搜索、播放动作、多选 | ✅ | ✅ | ✅ | ✅ |
| `player` | 引擎、会话、字幕、音轨、手势、队列 | ✅ | ✅ | — | ✅ |
| `network` | B 站直播、双路观赛、弹幕、网络视频 | ✅ | ✅ | ✅ | ✅ |
| `transfer` | 选文件、亮码、扫码、收发、历史 | ✅ | ✅ | ✅ | ✅ |
| `settings` | 播放、外观、存储、隐私 | ✅ | ✅ | ✅ | ✅ |
| `category` | 分类管理与详情 | — | — | — | ✅ |
| `playlist` | 播放列表管理与详情 | — | — | — | ✅ |
| `favorites` | 收藏与收藏夹筛选 | — | — | — | ✅ |
| `history` | 最近播放 | — | — | — | ✅ |
| `profile` | 「我的」 | — | — | — | ✅ |
| `shell` | 底部导航壳 | — | — | — | ✅ |
| `magnet` | 磁力占位页 | — | — | — | ✅ |

---

## 8. `library` —— 本地视频库

### 8.1 `library/domain/`

| 文件 | 行数 | 作用 | 关键内容 |
| --- | ---: | --- | --- |
| `models.dart` | 813 | 全部领域模型与聚合状态 | `MediaItem`、`SourceFolder`、`Category`、`Playlist`、`PlaybackProgress`、`FavoriteFolder`、`LibraryState`；`SortOption` / `ViewMode` / `RepeatMode` / `MediaPermission` |

### 8.2 `library/data/`

| 文件 | 行数 | 作用 | 关键内容 |
| --- | ---: | --- | --- |
| `library_repository.dart` | 853 | 所有写操作 | 均返回新 `LibraryState`：扫描合并、收藏、分类、播放列表、进度、移除 |
| `media_scanner.dart` | 252 | 相册权限与视频枚举 | `MediaScanner` 接口、`PhotoManagerMediaScanner`、桌面 `UnsupportedMediaScanner`、`ScanOutcome` |
| `media_import_service.dart` | 159 | 系统文件导入 | `pickAndImport`、`importPicked`（复制到应用私有目录） |
| `media_probe.dart` | 103 | 媒体元数据探测 | `MediaProbe`、`ProbedMedia`（宽高、时长） |
| `media_resolver.dart` | 54 | 播放源解析 | `MediaResolver`：`MediaItem` → 可播放路径/URL |
| `thumbnail_service.dart` | 138 | 缩略图 | 生成与缓存 `ThumbnailService` |

### 8.3 `library/application/`

| 文件 | 行数 | 作用 | 关键内容 |
| --- | ---: | --- | --- |
| `library_controller.dart` | 269 | 媒体库控制器 | `scan()`、`requestPermission()`、`importVideos()`、转发仓储写操作并落盘 |

### 8.4 `library/presentation/`

| 文件 | 行数 | 作用 | 关键内容 |
| --- | ---: | --- | --- |
| `local_page.dart` | 493 | 本地首页 | 权限引导、扫描横幅、快捷操作、文件夹列表 |
| `all_videos_page.dart` | 128 | 全部视频 | 列表/网格、排序、多选 |
| `folder_page.dart` | 131 | 文件夹详情 | 当前文件夹视频、多选 |
| `search_page.dart` | 142 | 本地搜索 | 按标题过滤 |
| `video_actions.dart` | 884 | 视频业务动作 | 播放、单条/批量操作、收藏、分类、播放列表、分享入口 |
| `import_action.dart` | 103 | 导入动作 | 文件选择、进度弹窗、结果提示 |

### 8.5 `library/presentation/widgets/`

| 文件 | 行数 | 作用 | 关键内容 |
| --- | ---: | --- | --- |
| `media_tiles.dart` | 427 | 视频卡片 | `MediaThumbnail`、`MediaListTile`、`MediaGridTile`、多选标记 |
| `media_collection_view.dart` | 225 | 列表/网格容器 | `MediaCollectionView`、`SelectionHeader` |
| `media_selection.dart` | 282 | 多选能力 | `MediaSelectionState`、`SelectionActionBar`、`MediaPageActions` |

---

## 9. `player` —— 本地播放

| 层 | 文件 | 行数 | 作用 | 关键内容 |
| --- | --- | ---: | --- | --- |
| domain | `playback_engine.dart` | 91 | 播放引擎抽象 | `VideoPlaybackEngine`、`PlaybackStatus`、`PlaybackException`；统一字幕与音轨切换 |
| domain | `playback_tracks.dart` | 240 | 轨道领域模型 | `SubtitleTrackInfo`、`AudioTrackInfo`、自动/指定选择、`PlaybackSubtitles`、`PlaybackAudio`；图片字幕判定与语言/声道标签 |
| domain | `playback_session.dart` | 423 | 播放会话 | 进度保存、95% 完成、续播、队列换片；字幕/音轨状态、切换忙态、失败反馈、媒体代次防护 |
| domain | `playback_queue.dart` | 138 | 播放队列 | 上/下一集、跳转、四种循环模式 |
| data | `media_kit_engine.dart` | 457 | `media_kit` 适配 | 打开/定位/倍速/音量、轨道订阅与切换、`VideoSurface`、文本字幕样式、截图 |
| presentation | `player_page.dart` | 2,608 | 播放器页 | 手势、控制层、倍速/队列/更多面板、「字幕与音轨」面板、错误兜底、空引擎占位 |

字幕与音轨的选择互不影响：字幕支持自动/关闭/指定轨，音轨支持自动/指定轨；换片恢复自动，单音轨只读展示。

---

## 10. `network` —— B 站直播与网络视频

### 10.1 `network/domain/`

| 文件 | 行数 | 作用 | 关键内容 |
| --- | ---: | --- | --- |
| `live_models.dart` | 437 | 直播领域模型 | `LiveRoom`、`LiveStream`、`LiveQuality`、`LivePlaylist`、`LivePreset`、`SavedLivePreset`、`LiveFavorite`、`NetworkVideo`、`NetworkState` |
| `danmaku_models.dart` | 80 | 弹幕模型 | `DanmakuMessage`（普通、醒目留言、表情）、`DanmakuStatus` |

### 10.2 `network/data/`

| 文件 | 行数 | 作用 | 关键内容 |
| --- | ---: | --- | --- |
| `bili_live_api.dart` | 647 | 直播接口 | 搜索（`buvid3` 重试）、开播状态、房间详情、取流、发弹幕、官方表情 |
| `bili_session.dart` | 366 | 账号会话 | WebView Cookie 校验、用户资料、`buvid3`、`DedeUserID`、安全存储 |
| `bili_wbi.dart` | 448 | WBI 签名 | `mixinKey`、`wts`、`w_rid`，内置 MD5 |
| `danmaku_client.dart` | 636 | 弹幕客户端 | WBI 鉴权、WebSocket、心跳、超时、deflate 解包、消息解析、指数退避重连 |
| `bili_cookie_bridge.dart` | 54 | Cookie 原生桥 | `lumiplayer/bili_cookie` 读取 / 清理 |
| `live_leg.dart` | 183 | 单路播放 | mpv 缓存、首帧/错误赛跑、单线路生命周期 |
| `dual_live_session.dart` | 508 | 双路会话 | 两轮取流、画面先播 + 解说后台连接、声音切换、同步、画质切换 |
| `network_repository.dart` | 135 | 网络持久化 | 收藏房间、上次组合、收藏组合、网络视频直链 |

### 10.3 `network/application/`

| 文件 | 行数 | 作用 | 关键内容 |
| --- | ---: | --- | --- |
| `network_controller.dart` | 114 | 网络状态 | 收藏增删、组合保存/删除、开播状态刷新 |
| `bili_account_controller.dart` | 87 | 账号状态 | 恢复、刷新、登录落库、退出并清 Cookie |

### 10.4 `network/presentation/`

| 文件 | 行数 | 作用 | 关键内容 |
| --- | ---: | --- | --- |
| `network_page.dart` | 1,527 | 网络首页 | 直播/视频分段、账号卡、双路来源、组合、收藏、添加链接 |
| `live_search_page.dart` | 657 | 直播搜索 | 防抖、竞态保护、房间号直连 |
| `live_player_page.dart` | 1,283 | 直播控制台 | 竖屏信息条、横屏浮层、亮度/音量手势、弹幕状态与发送、250ms 批量刷新 |
| `network_video_page.dart` | 295 | 网络视频 | 直链播放与错误兜底 |
| `bili_login_page.dart` | 314 | B 站登录 | WebView 登录、Cookie 轮询、建立会话 |
| `bili_account_sheet.dart` | 185 | 账号面板 | 资料、刷新、切换、退出、头像 |

### 10.5 `network/presentation/widgets/`

| 文件 | 行数 | 作用 |
| --- | ---: | --- |
| `live_console_header.dart` | 204 | 返回、双源头像、标题、原声/解说、状态 |
| `live_control_overlay.dart` | 242 | 横屏浮层：信息、暂停、刷新、弹幕、同步、画质 |
| `live_portrait_control_bar.dart` | 62 | 竖屏底部：暂停、横屏 |
| `live_quality_panel.dart` | 156 | 右侧画质面板 |
| `live_sync_panel.dart` | 249 | 右侧同步校准面板 |
| `live_side_panel.dart` | 84 | 右侧滑出面板外壳 |
| `live_icon_button.dart` | 48 | 纯图标按钮 |
| `live_source_avatars.dart` | 169 | 双源头像 |
| `live_danmaku_panel.dart` | 574 | 弹幕列表、连接状态、发送栏 |
| `live_emoticon_panel.dart` | 239 | 官方表情面板 |
| `live_danmaku_overlay.dart` | 367 | 横屏飘屏：等像素速度、分轨、防追尾 |
| `live_danmaku_settings_panel.dart` | 256 | 区域、字号、透明度、速度设置 |

> 原生侧：`MainActivity.kt`、`ios/Runner/AppDelegate.swift` 提供 `lumiplayer/bili_cookie` 通道。

---

## 11. `transfer` —— 局域网文件传输

### 11.1 领域与数据

| 层 | 文件 | 行数 | 作用 | 关键内容 |
| --- | --- | ---: | --- | --- |
| domain | `transfer_models.dart` | 251 | 文件与历史模型 | 六类文件、方向、状态、`TransferFile`、`TransferRecord` |
| domain | `transfer_session.dart` | 142 | 当前会话状态 | `TransferPhase`、邀请/二维码字段、逐文件结果、`TransferSessionState` |
| data | `transfer_bridge.dart` | 153 | Flutter ↔ Android | `prepareReceive`、`stopReceive`、`send`、`cancel`、`snapshot`、文件选择/打开、事件流 |
| data | `transfer_repository.dart` | 57 | 历史仓储 | `transfers` 表读写，保留最近 50 条 |

### 11.2 应用层

| 文件 | 行数 | 作用 | 关键内容 |
| --- | ---: | --- | --- |
| `transfer_controller.dart` | 53 | 历史与活动任务 | 记录列表、活动任务判断 |
| `transfer_session_controller.dart` | 304 | 当前传输会话 | 订阅原生事件、维护阶段/邀请/进度、解析相册 URI、写终态历史、取消与重置 |

### 11.3 表现层

| 文件 | 行数 | 作用 | 关键内容 |
| --- | ---: | --- | --- |
| `transfer_home_page.dart` | 478 | 传输首页 | 发送/接收入口、最近三条、记录详情、帮助 |
| `select_files_page.dart` | 965 | 选择文件 | 六类入口、相册/文件夹视图、多选、已选清单、下一步 |
| `transfer_receive_page.dart` | 270 | 接收准备 | 网络检查、TLS 监听、二维码、120 秒换码、离开清理 |
| `transfer_scan_page.dart` | 240 | 扫码发送 | 相机扫码、手动粘贴接收码、去重、连接 |
| `transfer_task_page.dart` | 226 | 传输任务 | 当前文件、总进度、取消、逐文件结果、打开文件 |
| `transfer_records_page.dart` | 131 | 历史记录 | 收发方向筛选、文件结果 |
| `transfer_entry.dart` | 30 | 分享入口 | 视频 `MediaItem` → `TransferFile` → 选择页 |

### 11.4 Android 原生传输

`android/app/src/main/kotlin/com/example/myplayer/transfer/`：

| 文件 | 作用 |
| --- | --- |
| `TransferBridge.kt` | MethodChannel / EventChannel 注册与命令转发 |
| `TransferModels.kt` | 邀请、清单文件、发送文件模型 |
| `TransferProtocol.kt` | `[type][length][payload]` 帧格式、窗口与上限 |
| `TransferSsl.kt` | TLS 1.2/1.3、证书指纹 |
| `TransferServer.kt` | 接收端监听、认证、清单、逐文件写入与 ACK |
| `TransferClient.kt` | 发送端连接、清单、分块发送、等待确认 |
| `TransferStore.kt` | `MediaStore.Downloads` 落盘、重名处理、失败清理 |

`MainActivity.kt` 同时负责 SAF 文件/目录选择和 B 站 Cookie 通道；`res/raw/transfer_identity.p12` 是当前随包 TLS 身份。

---

## 12. `settings` —— 设置

| 层 | 文件 | 行数 | 作用 |
| --- | --- | ---: | --- |
| domain | `app_settings.dart` | 224 | `AppSettings`、主题/画面/速度等枚举与序列化 |
| data | `settings_repository.dart` | 33 | 设置读写 |
| application | `settings_controller.dart` | 149 | `SettingsController` 与 `NavTabController` |
| presentation | `settings_pages.dart` | 591 | 播放、外观、存储设置 |
| presentation | `library_settings_pages.dart` | 250 | 隐藏文件夹、扫描设置 |
| presentation | `info_pages.dart` | 283 | 关于、隐私与权限、帮助 |

---

## 13. 其余单页模块

| 文件 | 行数 | 作用 |
| --- | ---: | --- |
| `category/presentation/categories_page.dart` | 178 | 分类管理 |
| `category/presentation/category_detail_page.dart` | 134 | 分类详情 |
| `playlist/presentation/playlists_page.dart` | 202 | 播放列表管理 |
| `playlist/presentation/playlist_detail_page.dart` | 351 | 播放列表详情与条目操作 |
| `favorites/presentation/favorites_page.dart` | 207 | 收藏页与收藏夹筛选 |
| `history/presentation/recent_page.dart` | 312 | 继续观看与最近播放 |
| `profile/presentation/profile_page.dart` | 328 | 统计、快捷入口、设置分组、版本号 |
| `shell/presentation/home_shell.dart` | 159 | 本地 / 网络 / 传输 / 我的 |
| `magnet/presentation/magnet_page.dart` | 102 | 磁力占位页（无导航入口） |

---

## 14. 测试、CI 与工具

### 14.1 `test/`

| 文件 | 行数 | 作用 |
| --- | ---: | --- |
| `helpers/test_harness.dart` | 209 | 内存数据库 + 固定媒体库测试环境 |
| `unit/formatters_test.dart` | 60 | 格式化函数 |
| `unit/library_models_test.dart` | 177 | 媒体库模型与序列化 |
| `unit/library_repository_test.dart` | 379 | 媒体库写操作与持久化 |
| `unit/local_database_test.dart` | 80 | 数据库迁移与读写 |
| `unit/playback_queue_test.dart` | 159 | 队列与循环模式 |
| `unit/playback_session_test.dart` | 295 | 播放会话、进度、自动连播、关闭释放 |
| `widget/local_pages_test.dart` | 98 | 本地页面 Widget |
| `widget/navigation_test.dart` | 94 | 导航结构 |
| `preview/screens_preview_test.dart` | 156 | 生成 `docs/preview` 截图 |

### 14.2 其他

| 位置 | 作用 |
| --- | --- |
| `integration_test/app_flow_test.dart` | 应用流程端到端测试 |
| `.github/workflows/flutter-ci.yml` | Dart 格式、静态检查、测试、构建 CI |
| `tool/dev.sh` | 本地开发辅助命令 |
| `tool/generate_icons.py` | 从源图生成各平台图标 |

---

## 15. 按改动类型定位

| 想改… | 文件 |
| --- | --- |
| 应用名、主题、语言、字号 | `app/app.dart`、`core/theme/app_theme.dart` |
| 新增页面/路由 | `app/router.dart` + 对应 `features/*/presentation` |
| 数据库表结构或迁移 | `core/database/local_database.dart` |
| 首页布局、权限引导 | `library/presentation/local_page.dart` |
| 视频卡片样式 | `library/presentation/widgets/media_tiles.dart` |
| 多选操作条 | `library/presentation/widgets/media_selection.dart` |
| 收藏 / 分类 / 播放列表面板 | `library/presentation/video_actions.dart` |
| 播放器手势与控制层 | `player/presentation/player_page.dart` |
| 字幕 / 音轨选择与渲染 | `player/domain/playback_tracks.dart`、`player/data/media_kit_engine.dart`、`player/presentation/player_page.dart` |
| 进度保存、续播、完成判定 | `player/domain/playback_session.dart` |
| 直播搜索与取流 | `network/data/bili_live_api.dart` |
| 双路播放、声音切换、同步 | `network/data/dual_live_session.dart` |
| 直播控制台布局 | `network/presentation/live_player_page.dart` + `widgets/` |
| 横屏飘屏 / 弹幕设置 | `network/presentation/widgets/live_danmaku_overlay.dart`、`live_danmaku_settings_panel.dart` |
| 发送弹幕 / 登录校验 | `network/data/bili_live_api.dart`、`network/presentation/live_player_page.dart` |
| 弹幕接收 / 解析 / 重连 | `network/data/danmaku_client.dart` |
| WBI 签名 | `network/data/bili_wbi.dart` |
| 收藏直播组合 | `network/domain/live_models.dart` + `network_repository.dart` + `network_page.dart` |
| B 站登录与 Cookie | `bili_session.dart`、`bili_cookie_bridge.dart`、`bili_login_page.dart`、`MainActivity.kt`、`AppDelegate.swift` |
| 文件选择与已选清单 | `transfer/presentation/select_files_page.dart` |
| 传输会话与历史 | `transfer/application/transfer_session_controller.dart`、`transfer/data/transfer_repository.dart` |
| 扫码 / 亮码 / 任务页 | `transfer/presentation/transfer_scan_page.dart`、`transfer_receive_page.dart`、`transfer_task_page.dart` |
| 传输协议与落盘 | `android/.../transfer/TransferProtocol.kt`、`TransferServer.kt`、`TransferClient.kt`、`TransferStore.kt` |
| 设置项增删 | `settings/domain/app_settings.dart` + `settings/presentation/settings_pages.dart` |
| 通用卡片、页头、空状态 | `core/widgets/ui_kit.dart` |
