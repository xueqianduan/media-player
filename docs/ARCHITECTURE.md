# ReelBox 架构说明

## 1. 分层

```
Presentation（页面 / Widget）
      │  read / watch
      ▼
Application（Riverpod Notifier：LibraryController / SettingsController）
      │  调用方法，拿到新快照
      ▼
Data（LibraryRepository / LocalDatabase / 扫描与导入适配器 / 播放引擎）
      │
      ▼
Domain（MediaItem、SourceFolder、Category、Playlist、PlaybackProgress、
        PlaybackQueue、PlaybackSession、VideoPlaybackEngine 接口）
```

约束：

1. UI 不直接访问文件系统或数据库，只消费 `LibraryState` 快照。
2. `LibraryRepository` 的每个写方法都是「传入旧快照 → 返回新快照 → 异步落盘」，便于单元测试与回滚。
3. 插件差异封装在 data 层：`photo_manager`（扫描）、`file_picker`（导入）、`media_kit`（播放）。
4. 播放器 UI 只依赖 `VideoPlaybackEngine` 接口；`MediaKitPlaybackEngine` 是唯一实现，测试可用替身。
5. 一条视频只保留一份核心媒体记录，分类与播放列表只存 id 关联。

## 2. 数据模型

| 实体 | 关键字段 | 说明 |
| --- | --- | --- |
| `MediaItem` | id、folderId、sourceType、sourceId、sourceLocator、displayName、durationMs、width/height、fileSize、isFavorite、isAvailable、lastPlayedAt | 视频元数据；文件本身不入库 |
| `SourceFolder` | id、name、itemCount、totalSize、isHidden、lastScannedAt | 系统相册分组 / 真实文件夹 |
| `Category` | id、name、mediaIds | 应用内虚拟分类，多对多 |
| `Playlist` | id、name、mediaIds（有序） | 播放顺序，多对多 |
| `PlaybackProgress` | mediaId、positionMs、durationMs、lastPlayedAt、completed | 进度与完成状态 |

规则：

- `sourceId` 是去重键。重新扫描时保留原 `id`、收藏、自定义名称、缩略图与播放进度。
- 本次扫描未出现的相册资源标 `isAvailable = false`，不删除记录（TRD 19.3）。
- 播放进度 ≥ 95% 视为看完，并把位置归一到总时长。
- 「从 ReelBox 移除」会同时清理分类关联、播放列表关联与进度，但不动原始文件。

## 3. 本地存储与迁移

`LocalDatabase` 保存单个 `library.json`：

```json
{
  "schemaVersion": 2,
  "media": [], "folders": [], "categories": [], "playlists": [], "progress": [],
  "settings": {}, "permission": "granted", "lastScanAt": "..."
}
```

- `LocalDatabase.migrate()` 在读取时把旧版本结构升级到当前版本。
- v1 → v2：把独立的 `favorites: [id]` 合并进 `media[].isFavorite`。
- 写入使用「临时文件 + 替换」，避免进程中断导致文件损坏；解析失败回退为空库。
- 内存模式（`LocalDatabase.inMemory()`）用于测试。
- 后续替换 Drift/SQLite 时，只需实现同一组 Repository 方法，页面与控制器无需改动。

## 4. 媒体扫描

`PhotoManagerMediaScanner`：

1. `requestPermissionExtend` 申请视频权限（Android 只申请 `READ_MEDIA_VIDEO` / 旧版本 `READ_EXTERNAL_STORAGE`）。
2. `getAssetPathList(type: video, hasAll: false)` 获取相册分组。
3. 每个分组按 200 条分页读取，映射为 `MediaItem`，通过进度回调上报进度。
4. `sourceId` 去重（同一视频可能出现在多个相册）。
5. 缩略图不在此阶段生成，由 `ThumbnailService` 在列表可见时按需生成并缓存。

`MediaImportService`：系统文件选择器 → 复制到应用私有目录 → `MediaProbe` 探测时长 / 分辨率 / 封面 → 写入 `导入的视频` 文件夹。

## 5. 播放

### 播放入口与队列

- 从文件夹、全部视频、搜索、收藏、分类、最近、历史点击视频：只构造「单个视频」的队列，播完即停，不自动连播同页其他视频。
- 只有从播放列表进入（播放全部或点击列表内视频）才构造完整队列，并使用用户在播放列表页选择的播放模式。
- 播放模式 `RepeatMode`：不循环（sequential）、列表循环（loopAll）、单集循环（loopOne）；随机播放保留在领域层，暂不在 UI 暴露。


```
PlayerPage
   │ 创建
   ▼
PlaybackSession（ProgressSaver / SourceResolver）
   ├── VideoPlaybackEngine（media_kit：open / play / pause / seek / setSpeed / setVolume）
   ├── PlaybackQueue（顺序 / 列表循环 / 单曲循环 / 随机）
   └── 定时器（每 5 秒）+ 关键时机（暂停 / 拖动 / 退出 / 后台）保存进度
```

- 高频进度写入 `ValueNotifier<Duration>`，只重建进度条与控制栏，不重建整页。
- `PlaybackSession.dispose()` 依次取消订阅、停止定时器、释放引擎与所有 notifier，避免资源泄漏。
- 播放完成：先落库为已看完，再按队列模式自动续播；顺序模式到末尾停止。
- 续播规则：< 15 秒从头播；> 15 秒且未看完时弹窗询问（可在设置中关闭提醒）。
- 播放源解析：导入文件直接读路径；相册资源通过 `photo_manager` 换取可访问文件，失败时给出「文件不存在或权限失效」。

## 6. 状态管理

- `LibraryController extends Notifier<LibraryState>`：视频库、分类、播放列表、进度、扫描状态。
- `SettingsController extends Notifier<AppSettings>`：主题、默认倍速、手势、续播提醒、排序、展示方式；每次修改立即持久化。
- `navTabProvider`：底部导航索引。
- 启动时 `bootstrap()` 读取数据库并把首帧快照注入 Provider，避免首帧空白或闪烁。

## 7. 测试

| 层次 | 文件 | 覆盖内容 |
| --- | --- | --- |
| 单元 | `test/unit/library_repository_test.dart` | 收藏、分类多对多、播放列表排序、进度与完成阈值、扫描去重、移除清理 |
| 单元 | `test/unit/playback_queue_test.dart` | 顺序 / 循环 / 单曲 / 随机、上一首下一首、队列变更 |
| 单元 | `test/unit/playback_session_test.dart` | 播放会话：打开、暂停存进度、自动下一集、单曲循环、错误提示 |
| 单元 | `test/unit/local_database_test.dart` | schema 迁移、内存库读写 |
| 单元 | `test/unit/library_models_test.dart` | 排序、搜索、最近 / 继续观看、序列化、设置 |
| 单元 | `test/unit/formatters_test.dart` | 时间、大小、相对时间、分辨率 |
| Widget | `test/widget/local_pages_test.dart` | 首页文件夹、文件夹列表、多选、操作菜单、分类弹窗 |
| Widget | `test/widget/navigation_test.dart` | 我的页、主题切换、分类 / 播放列表、磁力预告、最近页 |
| 集成 | `integration_test/app_flow_test.dart` | 启动、文件夹浏览、多选加分类、主题写入 |

组件测试通过 `test/helpers/test_harness.dart` 注入内存数据库与固定媒体库，不依赖真机相册。

## 8. 扩展点

- **字幕 / 音轨**：`media_kit` 的 `player.stream.tracks` 已可用，新增 `TrackSelectorSheet` 并在 `PlaybackSession` 暴露轨道切换即可。
- **数据库替换**：`LocalDatabase` 与 `LibraryRepository` 之间保持接口稳定，替换为 Drift 时只改 data 层。
- **磁力模块**：`MagnetPage` 独立，后续接入解析服务时不影响本地视频链路。
- **云端同步**：`LibraryState` 可整体序列化，具备作为同步载体的基础（V3.0 规划）。
