# ReelBox 功能扩展清单

> 基于 V1.0 现有实现（`lib/` 48 个文件）梳理的使用向功能缺口。  
> 只讨论"用户能感知到的功能"，不涉及架构重构。  
> 工作量：S ≈ 半天内，M ≈ 1–3 天，L ≈ 一周以上。

---

## 0. 现有能力盘点（避免重复建设）

| 分类  | 已实现                                         |
| --- | ------------------------------------------- |
| 媒体库 | 相册扫描、相册分组文件夹、全部视频、搜索（全部/当前文件夹）、6 种排序、列表/网格  |
| 导入  | 系统文件选择器、复制到私有目录、探测时长/分辨率/封面、同名同大小去重         |
| 组织  | 收藏、自定义分类（多归属）、播放列表（拖动排序）、播放全部/从指定视频开始       |
| 播放  | 播放/暂停/拖动、上下集、队列面板、倍速 0.5–5x、画面尺寸 4 种、横竖屏    |
| 手势  | 单击显隐、双击左右快进退 10s、双击中间暂停、横滑进度、左亮度右音量、长按加速    |
| 记录  | 每 5s 存进度、15s 续播阈值、95% 完成判定、继续观看/最近/已看完、历史清理 |
| 设置  | 默认倍速、长按倍速、手势开关、续播提醒、屏幕常亮、主题、存储管理、隐藏文件夹、扫描管理 |
| 其他  | 多选批量操作、重命名显示名、分享（复制路径）、移除记录、磁力占位页           |

**明显空白**：字幕、音轨切换、画中画、迷你播放器、截图、A-B 循环、隐私锁、备份迁移、外部打开。

---

## 1. 先修：两个已存在的使用缺陷

这两项不是新功能，是"用户会碰到但说不清哪里不对"的问题。

### 1.1 三个设置项重启后丢失

`AppSettings.toJson()`（`app_settings.dart:125–133`）只写了 7 个字段，但 `fromJson()`（`:135–153`）读了 10 个：

| 字段                                                                                                             | 写入 | 读取 | 结果             |
| -------------------------------------------------------------------------------------------------------------- | -- | -- | -------------- |
| `themeMode` / `defaultSpeed` / `gesturesEnabled` / `resumePrompt` / `keepScreenOn` / `sortOption` / `viewMode` | ✅  | ✅  | 正常             |
| `playlistRepeatMode`                                                                                           | ❌  | ✅  | **重启回到「列表循环」** |
| `longPressSpeed`                                                                                               | ❌  | ✅  | **重启回到 2.0x**  |
| `videoScaleMode`                                                                                               | ❌  | ✅  | **重启回到「常规」**   |

`SettingsRepository.save()` 直接写 `toJson()`，所以改完设置当场生效、杀掉进程就还原。README 里"播放列表播放模式…选择持久化"目前是不成立的。

修复：`toJson()` 补三个字段。5 行代码，顺手补一个 round-trip 单测。

### 1.2 随机播放写了引擎但没入口

`RepeatMode.shuffle` 存在，`PlaybackQueue` 已实现随机推进，`playlist_detail_page.dart:130` 甚至写了 shuffle 的说明文案，但 `RepeatMode.playbackModes`（`models.dart:68`）把它排除了，UI 只给三个选项。

结果：播放列表页文案说"支持顺序、循环与随机播放"，用户点开只有三个模式。

修复：把 `shuffle` 加回 `playbackModes`，补一个图标分支（`Icons.shuffle_rounded`）。

---

## 2. 第一梯队 · 补完核心体验（建议 V1.5）

这五项的共同点：**用户一天之内就会遇到，缺了会觉得"这个播放器不完整"**。

### 2.1 字幕系统 ⭐ 最高优先

本地视频 80% 的价值在外挂字幕上（外语片、纪录片、下载的剧集）。

- 自动匹配同名 `.srt` / `.ass` / `.vtt`（视频同目录）
- 手动「加载字幕」→ 文件选择器
- 内嵌字幕轨列表 + 切换 + 关闭
- 字幕延迟 ±0.5 秒（校对口型）
- 样式：字号 3 档、颜色、描边、上下位置

实现：`media_kit` 原生支持，不需要新依赖。

- 轨道：`player.state.tracks.subtitle` + `player.setSubtitleTrack(SubtitleTrack.uri(path))`
- 延迟：`player.setProperty('sub-delay', seconds)`
- 样式：`Video(subtitleViewConfiguration: SubtitleViewConfiguration(...))`
- 需要扩展 `VideoPlaybackEngine` 接口：`tracksStream` / `setSubtitleTrack` / `setSubtitleDelay`

工作量 **M**（接口扩展 + 面板 UI + 同名自动匹配）。

### 2.2 播放队列可编辑

现在队列面板只能看和跳，不能改。用户想"删掉这个不想看的""把下一集提前"就没办法。

- 拖动排序
- 左滑删除单项
- 「下一首播放」插入

实现：`playback_queue.dart` 加 `move(from, to)` / `removeAt(i)` / `insertNext(item)`；队列面板换 `ReorderableListView`。工作量 **S**。

### 2.3 音轨切换

多语言片源（国配/原声）、5.1 与立体声切换。

实现：`player.state.tracks.audio` + `player.setAudioTrack(...)`，UI 与字幕面板合并成一个「轨道」面板。工作量 **S**（接口扩展和字幕一起做，几乎白送）。

### 2.4 播放器内截图

看到好画面想存下来，现在只能手机截屏（带控制栏）。

- 一键截图保存到相册
- 文件名用「视频名_时:分:秒」

实现：`player.screenshot()` 已经用过（`media_probe.dart:60`），落盘到相册用 `gal` 包（Android 10+ 走 MediaStore，免存储权限）。工作量 **S**。

### 2.5 屏幕锁定（防误触）

躺着看、小孩看动画时必开。锁住后所有手势与控制层失效，只保留一个解锁按钮。

实现：纯 UI 状态位，`Stack` 最上层加透明遮罩 + 长按/双击解锁提示。工作量 **S**。

---

## 3. 第二梯队 · 明显拉开差距（V1.6）

### 3.1 迷你播放器 + 画中画 ⭐

这是"完善播放器"最典型的特征：退出播放页还能继续看/听。

- 返回列表后，底部悬浮小窗继续播放（可拖动、可关闭、点击回全屏）
- 切到其他 App 时进入系统画中画

实现要点：

- 迷你窗：`PlaybackSession` 已经在全局 provider 里，但 `Video` 控件现在挂在页面内。需要把 `VideoController` 提升到会话层，用 `Overlay` 渲染悬浮窗。工作量 **M**
- PiP：`AndroidManifest` 加 `android:supportsPictureInPicture="true"`，MethodChannel 调 `enterPictureInPictureMode`（或用 `simple_pip_mode`）。工作量 **S**
- 后台纯音频继续播：需要前台服务，工程量 **L**，建议先做 PiP 代替

### 3.2 A-B 循环 + 时间点书签

学舞蹈、看教学、反复听一段台词。

- A-B：设起点/终点，循环该区间，进度条上高亮
- 书签：任意时间点打标记，命名，列表跳转

实现：书签存 `Map<mediaId, List<Bookmark>>` 进 `LocalDatabase`；A-B 在 `PlaybackSession` 的 position 监听里做回跳。工作量 **S / M**。

### 3.3 片头跳过与单集倍速记忆

- 片头跳过：记住用户在该视频手动跳到 N 秒的习惯，第二次自动弹「跳过片头」
- 倍速记忆：同一视频下次打开沿用上次倍速（现在只有全局默认）

实现：给 `MediaItem` 加 `lastSpeed`、`introSkipMs`，或在 progress 表里扩展。工作量 **S**。

### 3.4 隐私锁

家庭共用平板、把私人视频放一个分类里。

- 给分类或播放列表加 4 位密码 / 指纹（`local_auth`）
- 解锁后本次会话内免验证

实现：`Category` 加 `isLocked` + `pinHash`；路由进入前拦截。工作量 **M**。

### 3.5 备份与迁移

换手机时收藏、分类、播放列表全没了，这是当前最大的数据风险。

- 导出：一个 JSON（收藏 id、分类、播放列表、进度）通过系统「保存到文件」或分享
- 导入：选文件 → 按 `sourceId` / 原始文件名匹配 → 提示匹配结果

实现：`LocalDatabase` 本来就是单 JSON，导出几乎零成本；`file_picker.saveFile` + `share_plus`。工作量 **S**。

### 3.6 「用其他应用打开」接入

从微信、文件管理器、下载器直接选 ReelBox 播放，而不是先导入。

实现：Manifest 加 `ACTION_VIEW` + `video/*` 的 intent-filter，`content://` 转临时可播路径（复制到缓存或直接用 fd）。工作量 **M**（原生配置 + 生命周期处理）。

---

## 4. 第三梯队 · 大工程（V2.0）

| 功能                  | 价值                        | 难点                                                                           | 工作量 |
| ------------------- | ------------------------- | ---------------------------------------------------------------------------- | --- |
| 进度条缩略图预览            | 拖动时显示该帧画面，高级感强            | 需按时间抽帧；`player.screenshot()` 逐帧太慢，建议原生 `MediaMetadataRetriever` 取 10–20 帧并缓存 | L   |
| 局域网 SMB / WebDAV 播放 | 直接播 NAS 上的片，nPlayer 类核心功能 | 协议库质量参差，需处理 Range 请求与大文件缓冲                                                   | L   |
| 网络串流（直链 / m3u8）     | 替代当前占位的「磁力」Tab            | 播放本身简单，难点在链接管理与失效提示                                                          | M   |
| 桌面小组件 / 长按快捷方式      | 一键「继续观看」                  | Android AppWidget 原生开发                                                       | M   |
| 投屏 DLNA             | 投到电视                      | 设备发现 + 协议实现，维护成本高                                                            | L   |

---

## 5. 不建议做

- **磁力 / BT 下载**：Flutter 没有可用的成熟引擎，必须引入原生 libtorrent，包体会涨 10MB+，还要处理做种、DHT、版权风险。当前这个 Tab 建议改成「网络」（直链 / m3u8 / 局域网），保留入口价值但可实现。
- **在线影视源 / 聚合搜索**：法务风险 + 源站失效维护成本，且违背"无账号、无网络请求"的隐私定位。
- **云端同步**：需要后端与账号体系，与当前单机定位冲突；用「导出 JSON 备份」覆盖 90% 需求。

---

## 6. 建议实施顺序

```
第 1 步（1 天）：修 toJson 丢字段 + 补随机播放入口 + 队列可编辑
第 2 步（3 天）：字幕系统 + 音轨切换（一次把引擎接口扩好）
第 3 步（2 天）：截图 + 屏幕锁定 + 备份导出
第 4 步（4 天）：迷你播放器 + 画中画
第 5 步（3 天）：A-B 循环 + 书签 + 片头跳过 + 单集倍速记忆
第 6 步（3 天）：隐私锁 + 外部打开
```

前两步做完，它就从"能用的本地播放器"变成"日常敢用的播放器"；第 4 步做完开始有替代品竞争力。

---

# 附录 A · "调节清晰度"到底能做成什么

## A.1 为什么本地文件没有"清晰度"

在线视频（B 站 / YouTube）的清晰度切换，本质是**服务端预先转码出 360p / 720p / 1080p 多份文件**，客户端只是换一个 URL。手机上只有一个视频文件，没有第二份码率可选，所以"换清晰度"这个动作在本地**没有对象**。

本地播放器能做的是另外三件事，作用在链路的不同环节：

```
源文件 ──→ 解码 ──→ 缩放/渲染 ──→ 屏幕
  ↑          ↑          ↑
多版本换文件  硬解/软解   放大算法
```

## A.2 形态一：多版本切换（看起来最像"清晰度"）

**前提**：同一部片子本地存在多个分辨率版本。常见于下载的剧集（1080p 与 720p 各一份）、或自己转码过。

**做法**：扫描后把"同名不同分辨率"的文件归为一个版本组，播放中切换时保留播放秒数。

```dart
// 归一化文件名，去掉分辨率/编码/来源/音轨等噪声 token
final _variantTokens = RegExp(
  r'\b(2160p|4k|1080p|720p|480p|bluray|blu-ray|web-?dl|webrip|hdtv|remux'
  r'|h\.?264|h\.?265|hevc|x264|x265|av1|10bit|hdr|dv|aac|dts|ddp?5\.1)\b',
  caseSensitive: false,
);

String variantFingerprint(String fileName) {
  var name = fileName.replaceAll(RegExp(r'\.[a-z0-9]{2,4}$', caseSensitive: false), '');
  name = name.replaceAll(RegExp(r'[._\-\[\]()]'), ' ');
  name = name.replaceAll(_variantTokens, ' ');
  return name.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
}
```

分组键 = `fingerprint` + 时长容差（`|Δduration| <= 3000ms`），避免把"预告片"和"正片"误归一组。

- 数据：**动态计算，不落库**，避免 `LocalDatabase` 再升 schema
- 排序：按 `height` 降序，默认选设备能硬解的最高档
- 切换：`PlaybackSession.switchMedia(mediaId, keepPosition: true)`
- UI：播放器右侧面板加「版本」，列出 `1080P / 720P`，选中项高亮
- 工作量 **M**（含同名匹配的边界处理）

## A.3 形态二：画质档位（推荐，任意视频都有用）

这才是本地播放器该做的"清晰度"。mpv 暴露了大量渲染参数，media_kit 1.2.6 的 `NativePlayer` 提供了公开的 `setProperty`：

```dart
// media_kit 1.2.6 已导出 NativePlayer，setProperty 内部就是 mpv_set_property_string
import 'package:media_kit/media_kit.dart';

final platform = player.platform;
if (platform is NativePlayer) {
  await platform.setProperty('hwdec', 'no');      // 关闭硬解
  await platform.setProperty('scale', 'lanczos'); // 放大算法
}
```

四档预设：

| 档位 | hwdec | scale / cscale | deband | 适用 |
|---|---|---|---|---|
| 省电 | `mediacodec` | `bilinear` | 关 | 长视频、发热降频 |
| 标准 | `auto` | `bicubic` | 关 | 默认 |
| 高清 | `auto` | `spline36` | 开 | 低分辨率片源放大 |
| 极致 | `no`（软解） | `lanczos` | 开 | 硬解花屏/绿屏时兜底 |

**关键实现约束**：`hwdec` 在解码器初始化后改属性**不会生效**（mediacodec 已握手）。必须走"重开文件 + seek 回原位"：

```dart
@override
Future<void> applyQuality(QualityProfile profile) async {
  final preset = qualityPresets[profile]!;
  final platform = _player.platform;
  if (platform is! NativePlayer) return;

  final position = _player.state.position;
  final wasPlaying = _player.state.playing;

  await platform.setProperty('hwdec', preset.hwdec);
  await platform.setProperty('scale', preset.scale);
  await platform.setProperty('cscale', preset.scale);
  await platform.setProperty('deband', preset.deband ? 'yes' : 'no');

  await _player.open(Media(_currentSource), play: false);
  await _player.seek(position);
  if (wasPlaying) await _player.play();
}
```

代价是 200–500ms 黑屏一次，建议只在用户手动切换时触发，并在切换瞬间显示"正在应用画质…"。

**UI 上顺带能做的加分项**：用 `player.state.videoParams`（`w` / `h` / `pixelformat` / `hwPixelformat`）显示"实际解码：硬解 · 1920×1080 · yuv420p"——用户能看出档位到底生没生效，比一个空开关可信得多。

## A.4 形态三：网络流多码率（真·清晰度，但依赖串流）

只有接入 m3u8 / HLS 之后才成立：master playlist 里 `#EXT-X-STREAM-INF` 描述了每个变体的 `RESOLUTION` 与 `BANDWIDTH`，切换等于换 URL。本地文件永远不会有这个能力，等做了「网络」Tab 再考虑。

## A.5 风险与别做的事

1. **不要宣称"提升画质"**。`scale` 只影响放大时的采样质量，1080p 在 1080p 屏上肉眼几乎无差别。真正能提升观感的是超分着色器（Anime4K / FSRCNNX），需要 `glsl-shaders`，而 Android 上 media_kit 的 `vo` 是否支持 libplacebo shader **必须先真机验证**，不要先写进 UI。
2. **软解 4K HEVC 会烫**。极致档要有提示，并在检测到掉帧（`player.state.buffering` 频繁为 true）时建议回退。
3. **切换前先探测实际参数**：`getProperty('vo')`、`getProperty('hwdec-current')`。若 `vo` 不是 gpu/gpu-next，`scale` 系列可能完全不生效——这几档就只剩 `hwdec` 有意义，UI 文案要跟着调整。

## A.6 它到底能不能"提升画质"

**不能真正提升信息量**。视频每一帧的像素在拍摄与编码时就定死了，播放器拿到的数据不会变多。所有"画质档位"只是在三个不同层面改变呈现方式，按"观感收益是否确定"排序：

| 层面 | 具体手段 | 观感收益 | 性质 |
|---|---|---|---|
| 修正错误 | 软解兜底、`deband` 去色带 | **确定，肉眼可见** | 把本该有的画面还回来 |
| 更换采样 | `scale` / `cscale` / `dscale` | 取决于片源：源分辨率 < 屏幕时才有感，1080p 在 1080p 屏上几乎为 0 | 改变放大时的插值方式 |
| 生成细节 | `glsl-shaders`（Anime4K / FSRCNNX） | **确实像换了片源**，但会引入伪影 | 根据边缘模式"猜"像素，非真实细节 |

要点：

- `deband` 是性价比最高的一项。压缩越狠的片源，天空、暗场、渐变处的阶梯色带越明显，开关前后区别一眼可见，且几乎不吃性能。
- `scale` 档位的收益被普遍高估。它只在放大时起作用，且 `lanczos` 会带振铃（高对比边缘出现细白边），不是无脑越高越好。
- 超分 shader 是唯一能叫"提升"的，但补的是推测细节：线条会变粗、纹理可能出现油画感，中端机还有掉帧与发热风险。要上必须先在真机验证 `vo` 支持与帧率。
- 真正意义上的"画质提升"只有离线转码（超分模型跑一遍生成新文件），耗时以分钟计、文件变大，不属于播放时功能。

**文案原则**：不要叫"清晰度"（用户会期待 B 站那种换源），叫「播放画质」或「解码与画质」，档位名描述作用而非暗示更好（"省电 / 标准 / 增强"优于"标清 / 高清 / 超清"）。调了看不出变化是最容易招差评的点。

**验证方法**：用 `player.screenshot()` 抓同一帧的开关前后两张图做像素对比。`MediaProbe` 已经在用这个能力抓封面，验证成本极低。

---

# 附录 B · 「原始画质 / 1080p / 720p / 480p」四档怎么做

## B.1 前提：四档只能是"四个文件"

本地播放器没有服务端转码，所以"选 720p"必须对应一个真实存在的 720p 文件。三种可能的实现：

| 做法 | 是否成立 | 结论 |
|---|---|---|
| 播放时实时降采样（`vf=scale`） | 画面变糊，但解码仍是原分辨率、GPU 负载不降反升（多一条 CPU 滤镜） | ❌ 纯负面，不做 |
| 用 `video-scale` 缩小渲染尺寸 | 只是把画面缩小居中，不影响负载 | ❌ 无意义 |
| **离线转码生成副本** | 唯一能让"选 720p"名副其实的做法 | ✅ |

## B.2 档位必须动态生成

原片 480p 时给用户"1080p"选项是错的：上采样不增加信息，只会更糊、更大。

规则：**只列出 ≤ 原片分辨率的档位**，且"原始画质"永远指向原文件、不参与转码。

原片 1080p → 显示 `原始画质 / 720p / 480p`（三档，只需生成两个文件）
原片 4K → 显示 `原始画质 / 1080p / 720p / 480p`
原片 480p → 只显示 `原始画质`

## B.3 转码命令

```bash
# 1080p / 720p / 480p 通用（-2 保证宽高比为偶数，H.264 要求）
-vf scale=-2:720 -c:v libx264 -preset veryfast -crf 23 -c:a aac -b:a 128k -movflags +faststart
```

音频统一重编为 AAC（源可能是 AC3/DTS，容器换 mp4 后兼容性更好），`+faststart` 保证边下边播。

## B.4 转码通道选型

| 方案 | 包体 | 代码量 | 速度 | 风险 |
|---|---|---|---|---|
| ffmpeg-kit 社区 fork（`ffmpeg_kit_extended_flutter` / `ffmpeg_kit_flutter_new`） | +20–40MB | 小（一条命令） | 软编，慢 | 官方 ffmpeg-kit 已于 2026-07 归档，fork 需自行评估维护状态与 Android 16KB page size 兼容 |
| Android `MediaCodec` + `MediaMuxer` 自研 | 0 | ~400 行 Kotlin | 硬编，快 5–10× | 需要 GL 做缩放，机型兼容性要逐个验 |
| iOS `AVAssetExportSession` | 0 | ~80 行 Swift | 硬编 | 只覆盖 iOS，且 preset 只有固定几档 |

建议：先用社区 fork 打通流程（改一行命令就能试不同档位），确认产品价值后再决定是否换原生。

## B.5 数据与任务

- **模型**：`MediaItem` 增加 `derivedFromId`（源视频 id）与 `qualityLabel`（`720p`），`LocalDatabase` 升 schema v3
- **产物位置**：应用私有目录 `derived/<sourceId>/720p.mp4`，随源视频一起被"移除记录"清理
- **任务管理**：串行队列（避免同时多个硬编把手机烤了）、进度回调、可取消、失败重试
- **前后台**：转码必须跑前台服务，否则用户切走就被系统杀掉 → 需要通知栏进度条（工程量 +30%）
- **播放中切换**：`PlaybackSession.switchMedia(targetId, keepPosition: true)`，秒数保留

## B.6 成本

| 项 | 数值 |
|---|---|
| 1 小时 1080p → 720p（中端机，软编 veryfast） | 10–20 分钟 |
| 存储占用 | 720p ≈ 原片 40–60%，480p ≈ 20–30% |
| 代码量 | 转码通道 + 任务队列 + 版本组 + UI ≈ 5–7 天 |

## B.7 关键判断

**"播放时选清晰度"在本地播放器里价值很低**：省流量不成立、跨网络自适应不成立，而"降级看"是用户几乎不会主动做的动作（画质只会变差）。真正有需求的是**反向场景——把 4K 压成 1080p 省空间**。

所以推荐把四档从"播放器面板"搬到"视频详情 / 批量操作"里，做成「压缩副本」：

- 入口：视频详情 → 「压缩到 720p（预计省 58%，需 12 分钟）」
- 完成后：副本自动进入版本组，播放器右上角的版本切换里出现 720p
- 可选：压缩完成后询问是否删除原文件（默认不删）

这样四档 UI 保留了，"清晰度选择"也有了真实的使用场景。
