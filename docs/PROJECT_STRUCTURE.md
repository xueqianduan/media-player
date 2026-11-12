# LumiPlayer `lib/` 目录结构说明

> 统计时间：2026-11-12　版本 `1.0.4+6`  
> 范围：仅 `lib/`（64 个 Dart 文件，约 19,000 行）  
> 本文回答：每个文件夹是干什么的、里面有哪些文件、每个文件负责什么。



---

## 1. 目录树

```
lib/
├── main.dart                       应用入口
├── app/                            应用级装配（启动、路由、主题、全局 Provider）
│   ├── app.dart
│   ├── bootstrap.dart
│   ├── providers.dart
│   └── router.dart
├── core/                           跨模块基础设施（不含业务逻辑）
│   ├── database/local_database.dart
│   ├── theme/app_theme.dart
│   ├── utils/formatters.dart
│   └── widgets/
│       ├── ui_kit.dart
│       └── dialogs.dart
└── features/                       业务模块（每个模块内部按四层组织）
    ├── library/                    本地视频库（最大模块）
    │   ├── domain/models.dart
    │   ├── data/                   repository / scanner / import / probe / resolver / thumbnail
    │   ├── application/library_controller.dart
    │   └── presentation/           首页、列表页、搜索、导入、业务动作 + widgets/
    ├── player/                     播放：引擎、会话、队列、播放页
    ├── network/                    B 站直播：接口、双路会话、搜索页、播放页
    ├── transfer/                   文件传输：模型、记录、选择页、首页
    ├── settings/                   设置：模型、仓储、控制器、各类设置页
    ├── category/                   分类管理 + 分类详情
    ├── playlist/                   播放列表管理 + 详情
    ├── favorites/                  收藏页
    ├── history/                    最近播放页
    ├── profile/                    「我的」页面
    ├── shell/                      底部导航壳
    └── magnet/                     磁力占位页
```

---

## 2. 分层约定

`features/<模块>/` 内部固定四层，缺层就不建目录：

| 层  | 目录              | 能做什么                                 | 不能做什么                      |
| -- | --------------- | ------------------------------------ | -------------------------- |
| 领域 | `domain/`       | 纯 Dart 实体、枚举、状态、序列化                  | 不 import Flutter，不发请求，不读文件 |
| 数据 | `data/`         | 接口请求、文件读写、持久化、平台能力                   | 不持有 UI 状态                  |
| 应用 | `application/`  | Riverpod `Notifier`，编排 data → 暴露给 UI | 不写 Widget                  |
| 表现 | `presentation/` | 页面、组件、交互                             | 不直接碰数据库/网络                 |

依赖方向单向：`presentation → application → data → domain`。

---

## 3. `lib/` 顶层

| 文件          | 行数 | 作用                                                |
| ----------- | -- | ------------------------------------------------- |
| `main.dart` | 13 | 应用入口：初始化插件与数据库，`ProviderScope` 挂载 `LumiPlayerApp` |

---

## 4. `lib/app/` —— 应用级装配

| 文件               | 行数  | 作用                               | 关键内容                                                                    |
| ---------------- | --- | -------------------------------- | ----------------------------------------------------------------------- |
| `app.dart`       | 56  | 根组件：主题、路由、中文本地化、全局字号缩放           | `LumiPlayerApp`、`MaterialApp.router`、三个 `Global*Localizations` 委托       |
| `bootstrap.dart` | 64  | 启动初始化：打开数据库、初始化 `media_kit`、错误兜底 | `bootstrap()`、启动期异常处理                                                   |
| `providers.dart` | 65  | 全局 Provider：数据库、初始媒体库、初始设置、扫描器   | `databaseProvider`、`initialLibraryStateProvider`、`mediaScannerProvider` |
| `router.dart`    | 223 | 路由表：所有页面路径与参数解析                  | `buildRouter()`、`/`、`/videos`、`/network/*`、`/transfer/*`；缺失参数兜底页        |

---

## 5. `lib/core/` —— 跨模块基础设施

### 5.1 `core/database/`

| 文件                    | 行数  | 作用                     | 关键内容                                                                       |
| --------------------- | --- | ---------------------- | -------------------------------------------------------------------------- |
| `local_database.dart` | 160 | 单 JSON 持久化：版本迁移 + 原子写入 | `schemaVersion`（当前 2）、`migrate()`、`readTable()` / `writeTable()`、`flush()` |

### 5.2 `core/theme/`

| 文件               | 行数  | 作用       | 关键内容                                                              |
| ---------------- | --- | -------- | ----------------------------------------------------------------- |
| `app_theme.dart` | 173 | 色板与亮/暗主题 | `AppColors`、`AppTheme.light()/dark()`、`context.textPrimary` 等取色扩展 |

### 5.3 `core/utils/`

| 文件                | 行数 | 作用    | 关键内容                                                                                    |
| ----------------- | -- | ----- | --------------------------------------------------------------------------------------- |
| `formatters.dart` | 69 | 展示格式化 | `formatDuration`、`formatBytes`、`formatDateTime`、`formatRelativeTime`、`formatResolution` |

### 5.4 `core/widgets/`

| 文件             | 行数  | 作用    | 关键内容                                                                                                                |
| -------------- | --- | ----- | ------------------------------------------------------------------------------------------------------------------- |
| `ui_kit.dart`  | 455 | 通用组件库 | `PageHeader`、`SectionHeader`、`AppCard`、`EmptyState`、`SoftIconBadge`、`AppIconButton`、`SheetHeader`、`SheetActionTile` |
| `dialogs.dart` | 142 | 通用对话框 | `showConfirmDialog`、`showTextInputDialog`                                                                           |

---

## 6. `lib/features/` —— 业务模块总览

| 模块          | 职责                      | domain | data | application | presentation |
| ----------- | ----------------------- | ------ | ---- | ----------- | ------------ |
| `library`   | 本地视频库：扫描、文件夹、搜索、播放动作、多选 | ✅      | ✅    | ✅           | ✅            |
| `player`    | 播放引擎与会话：手势、进度、队列        | ✅      | ✅    | —           | ✅            |
| `network`   | B 站直播：搜索、双路观赛、收藏、网络视频   | ✅      | ✅    | ✅           | ✅            |
| `transfer`  | 文件传输：选文件、收发、记录          | ✅      | ✅    | ✅           | ✅            |
| `settings`  | 设置：播放、外观、存储、隐私          | ✅      | ✅    | ✅           | ✅            |
| `category`  | 分类管理与详情                 | —      | —    | —           | ✅            |
| `playlist`  | 播放列表管理与详情               | —      | —    | —           | ✅            |
| `favorites` | 收藏页（含收藏夹筛选）             | —      | —    | —           | ✅            |
| `history`   | 最近播放                    | —      | —    | —           | ✅            |
| `profile`   | 「我的」页面                  | —      | —    | —           | ✅            |
| `shell`     | 底部导航壳                   | —      | —    | —           | ✅            |
| `magnet`    | 磁力占位页                   | —      | —    | —           | ✅            |

> 只有 `presentation` 的模块，数据来自 `library` 或 `network` 的控制器，不单独建仓储。

---

## 7. `library` —— 本地视频库

### 7.1 `library/domain/`

| 文件            | 行数  | 作用          | 关键内容                                                                                                                                                                |
| ------------- | --- | ----------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `models.dart` | 813 | 全部领域模型与聚合状态 | `MediaItem`、`SourceFolder`、`Category`、`Playlist`、`PlaybackProgress`、`FavoriteFolder`、`LibraryState`；`SortOption` / `ViewMode` / `RepeatMode` / `MediaPermission` 枚举 |

### 7.2 `library/data/`

| 文件                          | 行数  | 作用                        | 关键内容                                                                                     |
| --------------------------- | --- | ------------------------- | ---------------------------------------------------------------------------------------- |
| `library_repository.dart`   | 853 | 所有写操作，均返回新 `LibraryState` | `mergeScan`、`toggleFavorite`、收藏夹增删、分类增删、播放列表增删、`updateProgress`、`removeFromLibrary`      |
| `media_scanner.dart`        | 252 | 相册权限与视频枚举                 | `MediaScanner` 接口、`PhotoManagerMediaScanner`、桌面端 `UnsupportedMediaScanner`、`ScanOutcome` |
| `media_import_service.dart` | 159 | 系统文件选择器导入                 | `pickAndImport`、`importPicked`（复制到应用私有目录）                                                |
| `media_probe.dart`          | 103 | 媒体元数据探测                   | `MediaProbe`、`ProbedMedia`（宽高、时长）                                                        |
| `media_resolver.dart`       | 54  | 播放路径解析                    | `MediaResolver`：`MediaItem` → 可播放路径/URL                                                  |
| `thumbnail_service.dart`    | 138 | 缩略图生成与缓存                  | `ThumbnailService`                                                                       |

### 7.3 `library/application/`

| 文件                        | 行数  | 作用     | 关键内容                                                       |
| ------------------------- | --- | ------ | ---------------------------------------------------------- |
| `library_controller.dart` | 269 | 媒体库控制器 | `scan()`、`requestPermission()`、`importVideos()`、转发仓储写操作并落盘 |

### 7.4 `library/presentation/`

| 文件                     | 行数  | 作用         | 关键内容                                                                                                                          |
| ---------------------- | --- | ---------- | ----------------------------------------------------------------------------------------------------------------------------- |
| `local_page.dart`      | 493 | 首页（本地 tab） | 权限引导、扫描横幅、快捷操作、系统文件夹列表                                                                                                        |
| `all_videos_page.dart` | 128 | 全部视频页      | 列表/网格、排序、多选入口                                                                                                                 |
| `folder_page.dart`     | 131 | 单文件夹页      | 该文件夹下的视频、多选                                                                                                                   |
| `search_page.dart`     | 142 | 本地搜索       | 按标题过滤                                                                                                                         |
| `video_actions.dart`   | 884 | 视频业务动作集合   | `openPlayer`、`showVideoActionSheet`、`showBatchActionSheet`、`showFavoriteSheet`、`showCategoryPicker`、`showPlaylistPicker`、分享入口 |
| `import_action.dart`   | 103 | 导入动作       | 触发文件选择、进度弹窗、结果提示                                                                                                              |

### 7.5 `library/presentation/widgets/`

| 文件                           | 行数  | 作用      | 关键内容                                                                 |
| ---------------------------- | --- | ------- | -------------------------------------------------------------------- |
| `media_tiles.dart`           | 427 | 视频卡片    | `MediaThumbnail`、`MediaListTile`、`MediaGridTile`、多选标记                |
| `media_collection_view.dart` | 225 | 列表/网格容器 | `MediaCollectionView`、`SelectionHeader`                              |
| `media_selection.dart`       | 282 | 多选能力    | `MediaSelectionState`（mixin）、`SelectionActionBar`、`MediaPageActions` |

---

## 8. `player` —— 播放

| 层            | 文件                      | 行数   | 作用                                                                |
| ------------ | ----------------------- | ---- | ----------------------------------------------------------------- |
| domain       | `playback_engine.dart`  | 64   | 播放引擎抽象：`VideoPlaybackEngine`、`PlaybackStatus`、`PlaybackException` |
| domain       | `playback_session.dart` | 317  | 播放会话：5 秒定时保存 + 关键时机保存、95% 完成判定、续播阈值                               |
| domain       | `playback_queue.dart`   | 138  | 播放队列：上/下一首、四种循环模式                                                 |
| data         | `media_kit_engine.dart` | 203  | `media_kit` 实现、视频渲染 `VideoSurface`、截图                             |
| presentation | `player_page.dart`      | 2079 | 播放器页：手势（双击快进 / 滑动调亮度音量 / 长按加速）、控制层、倍速/更多/队列面板、错误兜底                |

---

## 9. `network` —— B 站直播

| 层            | 文件                        | 行数   | 作用                                                                                |
| ------------ | ------------------------- | ---- | --------------------------------------------------------------------------------- |
| domain       | `live_models.dart`        | 267  | `LiveRoom`、`LiveStream`、`LivePreset`、`LiveFavorite`、`NetworkVideo`、`NetworkState` |
| data         | `bili_live_api.dart`      | 401  | 接口封装：搜索（412 带 `buvid3` 重试）、`isLive`、`roomDetail`、`resolve` 取流、中文错误映射              |
| data         | `live_leg.dart`           | 131  | 单路播放器：mpv 缓存参数、错误流监听、首帧等待                                                         |
| data         | `dual_live_session.dart`  | 309  | 双路会话：线路回退、声音切换、暂停、手动同步（串行执行）                                                      |
| data         | `network_repository.dart` | 108  | 收藏 / 双路组合 / 网络视频持久化                                                               |
| application  | `network_controller.dart` | 102  | 收藏增删、组合保存、收藏开播状态批量刷新（4 路并发）                                                       |
| presentation | `network_page.dart`       | 1121 | 网络页：直播/视频分段、双路观赛来源卡、收藏卡、添加链接弹窗                                                    |
| presentation | `live_search_page.dart`   | 618  | 直播搜索：420ms 防抖、`_sequence` 竞态保护、房间号直连                                              |
| presentation | `live_player_page.dart`   | 615  | 双路播放页：首帧占位、声音切换、同步调节                                                              |
| presentation | `network_video_page.dart` | 295  | 网络视频直链播放                                                                          |

---

## 10. `transfer` —— 文件传输

| 层            | 文件                           | 行数   | 作用                                                                                |
| ------------ | ---------------------------- | ---- | --------------------------------------------------------------------------------- |
| domain       | `transfer_models.dart`       | 250  | 六类文件枚举、`TransferDirection`、`TransferStatus`、`TransferFile`、`TransferRecord`（字节进度） |
| data         | `transfer_repository.dart`   | 56   | `transfers` 表读写，最多保留 50 条                                                         |
| application  | `transfer_controller.dart`   | 53   | 记录列表、活动任务判断                                                                       |
| presentation | `transfer_home_page.dart`    | 400  | P01 首页：发送/接收、最近记录、帮助说明                                                            |
| presentation | `select_files_page.dart`     | 1010 | P02 选择文件：六类入口、全部/文件夹、全局多选、已选清单                                                    |
| presentation | `transfer_receive_page.dart` | 104  | P03 接收页（第一阶段占位）                                                                   |
| presentation | `transfer_entry.dart`        | 30   | 分享入口：视频 → `TransferFile` → 选择页                                                    |

---

## 11. `settings` —— 设置

| 层            | 文件                            | 行数  | 作用                                                    |
| ------------ | ----------------------------- | --- | ----------------------------------------------------- |
| domain       | `app_settings.dart`           | 174 | `AppSettings`、`AppThemeMode`、`VideoScaleMode` 等枚举与序列化 |
| data         | `settings_repository.dart`    | 33  | 设置读写                                                  |
| application  | `settings_controller.dart`    | 116 | `SettingsController` + `NavTabController`（底部导航索引）     |
| presentation | `settings_pages.dart`         | 591 | 播放设置、外观设置、存储管理                                        |
| presentation | `library_settings_pages.dart` | 250 | 隐藏文件夹、扫描设置                                            |
| presentation | `info_pages.dart`             | 283 | 关于、隐私与权限、帮助与反馈                                        |

---

## 12. 其余单页模块

| 文件                                                | 行数  | 作用                      |
| ------------------------------------------------- | --- | ----------------------- |
| `category/presentation/categories_page.dart`      | 178 | 分类管理：列表、新建、重命名/删除       |
| `category/presentation/category_detail_page.dart` | 134 | 分类详情：视频列表与批量操作          |
| `playlist/presentation/playlists_page.dart`       | 202 | 播放列表管理                  |
| `playlist/presentation/playlist_detail_page.dart` | 351 | 播放列表详情、播放模式与条目操作        |
| `favorites/presentation/favorites_page.dart`      | 207 | 收藏页：收藏夹筛选胶囊 + 视频列表      |
| `history/presentation/recent_page.dart`           | 312 | 最近播放：继续观看卡片 + 最近列表      |
| `profile/presentation/profile_page.dart`          | 328 | 「我的」：统计、快捷入口、设置分组、版本号   |
| `shell/presentation/home_shell.dart`              | 159 | 底部导航壳：本地 / 网络 / 传输 / 我的 |
| `magnet/presentation/magnet_page.dart`            | 102 | 磁力占位页（导航位已让给传输）         |

---

## 13. 按改动类型定位


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
| 进度保存、续播、完成判定 | `player/domain/playback_session.dart` |
| 直播搜索与取流 | `network/data/bili_live_api.dart` |
| 双路播放、声音切换、同步 | `network/data/dual_live_session.dart` |
| 文件选择与已选清单 | `transfer/presentation/select_files_page.dart` |
| 传输记录 | `transfer/data/transfer_repository.dart` |
| 设置项增删 | `settings/domain/app_settings.dart` + `settings/presentation/settings_pages.dart` |
| 通用卡片、页头、空状态 | `core/widgets/ui_kit.dart` |
