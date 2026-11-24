# LumiPlayer 下一版实施方案

日期 2026-11-24 · Android · 代码基线 `9268c7d`（当前版本 `1.2.2+11`）

当前状态为**步骤 1、2 已实施，等待真机验收**；步骤 3「发送失败重试」待开始。计划顺序是本地视频多音轨切换、发送桥接修复、播放器分享、发送失败重试。每次开始改代码前，先说明本次范围并询问用户，得到明确同意后实施。对外发布准备暂缓。 [项目代码实施确认](../AGENTS.md) · [本地字幕与音轨方案](local-playback-tracks-implementation-plan.md) · [文件传输方案](file-transfer-implementation-plan.md)

## 1. 现状与优先级

| 优先级 | 工作 | 当前情况 |
| --- | --- | --- |
| P0 传输修复 | 统一 Kotlin 与 Flutter 的发送返回值 | Kotlin 启动线程后用 `result.success(taskId)` 返回字符串，Flutter 的 `_invoke()` 按 Map 读取。跨通道类型不一致会让 Flutter 在原生已开始任务后报错。先修这条公共路径，再接分享和重试。 [Android 发送桥](../android/app/src/main/kotlin/com/example/myplayer/transfer/TransferBridge.kt) · [Flutter 发送桥](../lib/features/transfer/data/transfer_bridge.dart) |
| P0 已完成（待验收） | 内嵌音轨切换 | 已增加音轨领域模型、引擎与会话接口，并将侧栏扩展为「字幕与音轨」。多音轨支持自动与指定轨，单音轨只读展示；双音轨 MKV 的真实听感仍待真机确认。 [播放器接口](../lib/features/player/domain/playback_engine.dart) |
| P0 已完成（待验收） | 播放器分享 | 播放控制台右上角已接入完整分享流程：取当前集、暂停、确认页展示名称与真实大小、下一步才扫码，完成后返回原视频与播放状态。发送失败重试仍未实现。 [播放器](../lib/features/player/presentation/player_page.dart) · [分享入口](../lib/features/transfer/presentation/transfer_entry.dart) · [传输详情](../lib/features/transfer/presentation/transfer_task_page.dart) |
| 暂缓 | 设备身份、正式签名与发布验收 | TLS 身份随 APK 共用，Android `release` 配置引用调试签名。真机验收表仍待填写，导航测试还有旧的「磁力」用例。公开发布时再安排。 [TLS 实现](../android/app/src/main/kotlin/com/example/myplayer/transfer/TransferSsl.kt) · [签名配置](../android/app/build.gradle.kts) · [真机验收表](transfer-device-test.md) · [导航测试](../test/widget/navigation_test.dart) |

音轨可以先独立开发和验证。分享与传输重试共用发送通道，按「修桥接 → 分享 → 重试」落地。已有字幕自动、关闭和手动选项一起做回归。

## 2. 新增本地视频多音轨切换

### 用户操作

从播放器「更多」打开「字幕与音轨」。包含两条以上音轨时，显示「自动」和可用音轨，例如「英语原声」「国语配音」。用片源的标题、语言和声道信息展示，有重名时补序号，缺少元数据时显示「音轨 1」「音轨 2」。单音轨显示当前音轨，无音轨显示「当前视频无音轨」。字幕和音轨各自选中，用户可以同时选择英语原声与中文字幕。

切换直接作用于正在播放的文件，保持当前位置、暂停或播放状态、倍速和当前字幕。打开下一集时按自动策略选轨，返回「自动」可恢复引擎的自动选择。加载中和正在处理切换时禁用本组操作，切换失败在面板中提示。

### 模块实现

| 模块 | 实现方式 |
| --- | --- |
| `playback_tracks.dart`、`playback_engine.dart` | 沿用现有字幕领域模型的模式，增加音轨信息和当前音轨状态，包含轨道 ID、标题、语言、可选声道及自动或指定轨道。增加快照、事件流及选择接口。同步补齐 `_FailedEngine` 和测试假引擎。 [领域模型](../lib/features/player/domain/playback_tracks.dart) · [引擎接口](../lib/features/player/domain/playback_engine.dart) |
| `media_kit_engine.dart` | 复用现有 `Player` 和轨道列表订阅，从 `player.state.tracks.audio` 与 `player.stream.tracks` 提取当前文件的音轨。排除虚拟 `auto`、`no` 后再计算数量。按 ID 找回当前列表中的 `AudioTrack`，调用 `setAudioTrack(track)`；自动选轨用 `AudioTrack.auto()`。真机用实际声音核对结果，必要时在原生适配器通过 `current-tracks/audio/id` 核实已生效的轨道。 [media_kit 1.2.6 轨道 API](https://pub.dev/packages/media_kit/versions/1.2.6#select-video-audio-or-subtitle-track) · [mpv 当前轨道属性](https://mpv.io/manual/stable/#properties) |
| `playback_session.dart` | 复用现有媒体打开代次和独立状态监听。串行化打开媒体和选轨，执行前复核当前媒体和音轨 ID，完成后忽略过期结果。换片时清空列表和选中状态，恢复音轨自动模式。音轨错误走面板反馈，字幕操作独立处理。释放时取消新增监听。 [播放会话](../lib/features/player/domain/playback_session.dart) |
| `player_page.dart` | 扩展已有字幕侧栏，在「更多」和面板内增加音轨分组，复用滚动、横竖屏安全区与已选行样式。UI 监听音轨状态，切换动作只调用会话的选轨接口。 [播放器面板](../lib/features/player/presentation/player_page.dart) |

**通过条件**　离线打开双音轨 MKV，能听出原声和配音的切换。播放和暂停状态各测一次，切换期间位置不回到开头。字幕开关及语言保持当前选择。连续换片时旧轨道和迟到结果不会影响下一集。配一个单音轨样片验证界面。沿用原字幕方案的 TR01、TR03–TR07，并补音轨会话测试。 [字幕与音轨验收](local-playback-tracks-implementation-plan.md#5-验收清单)

## 3. 播放控制台右上角分享

该按钮用于把正在播放的本地视频发送到另一台运行 LumiPlayer 的手机。发送内容是原始视频文件，文件内的音轨和字幕随文件一起保留。

**实施状态**　已完成（v1.2.2+11），等待真机按下方验收条件验证。

### 已确认的用户流程

1. **点击右上角「分享」。** 取点击时正在播放的这一集，记下播放位置和播放或暂停状态。离开控制台时暂停当前视频。视频正在切换或当前文件无法确定时，提示用户等视频就绪。
2. **先显示当前视频和文件大小。** 复用现有文件选择页，直接展开已选清单，默认只选中正在播放的这一集。清单首屏展示视频名称、文件大小和「下一步」。大小尚未读取时显示「正在读取大小」，读到真实大小后才可继续。用户在这个页面确认发送内容，点「下一步」即完成确认。
3. **确认后打开扫码。** 检查文件存在、授权有效且可读，通过后进入扫码页。对方在 LumiPlayer 点「接收文件」并亮码。扫码成功、连接及清单校验通过后，自动进入传输详情并开始发送。二维码无效或连接失败时，显示原因并保留已选视频。
4. **查看传输结果。** 详情展示当前文件、已传字节、总大小和结果。接收端保存并校验成功、发送端收到确认后显示完成。发送失败时保留清单，允许按第 4 节重新扫码。传输中返回时先确认是否取消，选择继续传输则留在详情页。
5. **回到原播放控制台。** 在确认页直接返回时回到播放器，从扫码页返回时先回到已选清单。完成后点「返回播放器」，或确认取消后退出分享流程，均回到发起时的视频和时间点。原来正在播放则继续，原来暂停则保持暂停。

### 实现要点

- 用 `_session.currentItem` 取得当前 `MediaItem`，通过现有 `openTransferShare` 进入 `/transfer/select`，由播放器入口请求首屏展开已选清单。从队列切换后，等当前视频就绪再允许分享。传输结束后沿来源路由返回，保留原播放会话。 [播放器](../lib/features/player/presentation/player_page.dart) · [分享入口](../lib/features/transfer/presentation/transfer_entry.dart) · [传输详情](../lib/features/transfer/presentation/transfer_task_page.dart)
- 相册视频使用 `MediaItem.sourceId` 对应 `AssetEntity.id`，相册浏览和分享预选使用同一去重规则。Android 相册优先读取授权 URI，导入视频使用可读路径。保留现有记录的读取兼容。 [媒体模型](../lib/features/library/domain/models.dart) · [媒体解析](../lib/features/library/data/media_resolver.dart) · [文件选择页](../lib/features/transfer/presentation/select_files_page.dart)
- 在「下一步」校验文件并冻结本次发送清单，打开输入流时再复核。权限撤回、源文件删除或大小读取失败时，提示具体文件和原因，保留已选清单供用户处理。 [发送会话](../lib/features/transfer/application/transfer_session_controller.dart)

### 验收条件

- 从相册扫描的视频和应用内导入的视频各点一次右上角「分享」。首屏显示正确的视频名称与文件大小，点「下一步」后才出现扫码界面。跳到下一集后重复检查，预选应是新的一集。
- 取消扫码后，确认页仍保留同一视频。授权撤回或源文件删除时，显示明确原因。成功接收的测试 MKV 仍可切换其原有音轨和字幕。
- 分别从正在播放和暂停的视频发起分享，验证返回时的视频、时间点与播放状态。验证传输完成返回、失败重扫及取消传输三条路径。

## 4. 补齐发送失败重试

### 修正发送生命周期

- 先统一 `send` 的通道返回类型。建议沿用 Flutter 现有约定，由 Kotlin 返回包含非空 `taskId` 的 Map，Flutter 校验后再转到任务详情。原生已受理的任务与相机重新启动按同一次尝试协调处理。用通道测试覆盖返回对象、错误和连续重复扫描。 [Android 发送桥](../android/app/src/main/kotlin/com/example/myplayer/transfer/TransferBridge.kt) · [Flutter 发送桥](../lib/features/transfer/data/transfer_bridge.dart)
- 在发起原生调用之前生成本地尝试 ID，原生事件携带同一标识，Dart 仅接收当前尝试的状态、进度和终态。任务号继续用于协议和历史。重试前结束旧连接并等待资源释放，禁用重复重试。拒绝「取消传输」时留在任务页，确认取消后才释放并退出。 [会话控制器](../lib/features/transfer/application/transfer_session_controller.dart) · [任务页](../lib/features/transfer/presentation/transfer_task_page.dart)

### 生成重试清单

- 发送会话保存原始文件快照和按文件 ID 归集的确认结果。接收端成功保存、发送端收到匹配文件 ID 的 `FILE_OK` 后，才把该文件记入已确认集合。传输进度 ACK 仍用于字节进度。旧任务终态和已确认结果先写入历史，重试创建新任务。 [发送端文件确认](../android/app/src/main/kotlin/com/example/myplayer/transfer/TransferClient.kt) · [传输协议](transfer-protocol.md)
- 发送失败且有待确认文件时，任务页显示「重新扫码」，带入失败或未确认的文件。发送端按新的扫码页实例恢复相机和扫码去重。接收端失败页提供「重新接收」，由对方生成新的有效码。重试前复核来源；发现文件已失效时回到可编辑清单，由用户移除或重选。
- 如果接收方已保存文件但确认消息丢失，发送端将它显示为「结果未确认」，重试可能产生同名副本。若所有文件均已确认，仅缺任务结束确认，则显示「文件已确认，任务结果待确认」，提供查看记录或退出。重试采用逐文件重新发送，重新连接后从待发文件的开头传输。

**通过条件**　三文件任务在第一份确认成功后断网，重新扫码只带入后两份。旧任务保存正确结果，新任务号不同，相机成功重新启动。测试过期码、断网、发送中取消、丢失最终确认、退出后迟到事件和连续点击重试。接收端已有文件仍可打开，未完成文件按保存规则清理。

## 5. 对外发布准备（暂缓）

- **设备独立传输身份。** 接收机在 Android Keystore 生成独立签名密钥，用于 TLS 接收端身份。二维码携带该设备当前证书指纹，发送方核验后才发送邀请凭证。移除 APK 中共用的身份文件。双机验证不同设备的指纹确实不同，正确码能连接，指纹不匹配会终止连接。 [当前 TLS 实现](../android/app/src/main/kotlin/com/example/myplayer/transfer/TransferSsl.kt) · [Android Keystore](https://developer.android.com/privacy-and-security/keystore)
- **自动化和双机测试。** 将旧「磁力」导航测试更新为传输入口测试。补音轨、分享预选、发送通道和失败重试的回归用例。双机验证 Wi-Fi 和热点下交换收发角色、1 GB 以上文件、取消、断网、同名保存，以及本次修正的字节确认行为。记录设备、系统、构建版本和实际结果。 [现有 CI](../.github/workflows/flutter-ci.yml) · [真机验收表](transfer-device-test.md)
- **正式签名。** 用发布渠道的正式密钥构建 APK，核实安装包签名与版本。已存在正式发包时沿用对应的升级身份。现有调试签名安装的测试用户需要单独验证迁移路径，尤其是有收藏、播放列表和观看进度的设备。 [Gradle 签名配置](../android/app/build.gradle.kts) · [Android 应用签名](https://developer.android.com/studio/publish/app-signing)

## 6. 实施顺序与交付物

| 步骤 | 交付物 | 验收条件 |
| --- | --- | --- |
| 1. 多音轨切换 | 「字幕与音轨」面板、引擎与会话实现、双音轨样片记录 | 离线听得出语言变化，保持进度和字幕，换片恢复自动。 |
| 2. 发送通道与播放器分享 | 统一的通道响应、当前视频确认页、扫码发送与返回播放 | 先显示当前视频和文件大小，点「下一步」才扫码。原生与界面使用同一任务号，权限失效有提示，退出分享后回到原播放位置。 |
| 3. 传输失败重试 | 发送侧重新扫码、接收侧重新接收、逐文件结果与重试测试 | 重新连接的新任务只重发待确认文件，旧记录和已保存文件可查，晚到事件不会改写当前任务。 |
| 4. 发布候选（暂缓） | 设备独立身份、签名 APK、自动化结果与双机测试记录 | `flutter analyze`、`flutter test --exclude-tags preview` 和 `flutter build apk --release --split-per-abi` 通过。双机用例通过并完成安装及升级验证。 |

后续的小版本可以优先补「用 LumiPlayer 打开」和历史按文件类型筛选。前者可覆盖系统文件管理器打开视频及接收结果直接播放，后者可复用传输重试阶段登记的文件类型和逐项结果。
