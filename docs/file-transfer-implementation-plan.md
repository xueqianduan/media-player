# LumiPlayer 文件传输实现方案

复核日期 2026-11-19 · 代码基线 `93446b8` · Android 首版

以[文件传输需求](file-transfer-requirements.md)中的 FR 和 AC 编号为验收依据。首版沿用接收方亮码、发送方选文件后扫码的流程，在同一可互通 Wi-Fi 或用户已建立的热点中完成 Android 双机传输。建议先验证两台手机能稳定建立加密连接、直接读取授权 URI 并写入公开接收目录，再接通完整页面和队列。

## 1. 现状与缺口

| 模块 | 已有实现 | 需要补齐 |
| --- | --- | --- |
| P01 首页和导航 | 底栏已有「传输」，首页有发送、接收、历史空态及最近三条的渲染逻辑 | 最近记录行没有详情点击。记录行直接访问 `files.first`，旧记录或异常数据的空列表会崩溃。接收方向的文案和首页操作需随真实数据验收。 [首页](../lib/features/transfer/presentation/transfer_home_page.dart) · [底栏](../lib/features/shell/presentation/home_shell.dart) |
| P02 文件清单 | 六类入口，视频、图片、音频支持相册和文件夹视图，应用、文档、其他通过系统选择器添加。已具备按项勾选、已选清单、移除和清空 | 媒体只查询第 0 页的 200 项，「全选」也只作用于这些结果。授权请求未传当前媒体类型，拒绝态只有再请求，缺少系统选择器回退。列表取大小和选中时反复调用 `asset.file`，失败被当成 `0`。切换分类时旧异步结果可能覆盖新页面。「下一步」只弹说明，缺少可读性、大小和授权复核。 [选择页](../lib/features/transfer/presentation/select_files_page.dart) |
| 视频分享 | 单条菜单、批量操作均能预选文件进入 P02 | 分享预选使用 `MediaItem.id`，相册列表使用 `AssetEntity.id`，同一视频可被重复选中。`sourceLocator` 对相册资源可能只是资产 ID，不能直接作为路径读取。播放器仍调用分享占位方法。 [分享入口](../lib/features/transfer/presentation/transfer_entry.dart) · [列表操作](../lib/features/library/presentation/video_actions.dart) · [播放器](../lib/features/player/presentation/player_page.dart) |
| P03、P04 接收与扫码 | P03 已有路由和静态骨架 | 接收准备、网络权限、监听、临时二维码都未实现。缺少 P04 扫码页、相机权限、扫码去重、连接超时和失败恢复。 [接收页](../lib/features/transfer/presentation/transfer_receive_page.dart) · [路由](../lib/app/router.dart) |
| P05 真实传输与结果 | 枚举和记录模型预留任务状态、总字节和保存路径 | 没有传输协议、活动任务锁、字节流、文件队列、逐文件结果、进度确认、取消、失败重试、暂停或接收文件保存与打开。`active` 目前只从历史找第一条非结束记录。 [状态控制](../lib/features/transfer/application/transfer_controller.dart) · [领域模型](../lib/features/transfer/domain/transfer_models.dart) |
| P06 历史 | `TransferRepository` 能读写 `LocalDatabase` 的 `transfers` 列表，当前保留最近 50 个任务 | 当前代码没有实际收发结果写入；「查看全部」会跳到未注册的 `/transfer/records`。缺完整历史、组合筛选、文件级结果、权限失效提示和冷启动中断恢复。现有控制器没有等待保存结果，`LocalDatabase.flush()` 会吞写入异常。 [历史仓库](../lib/features/transfer/data/transfer_repository.dart) · [本地存储](../lib/core/database/local_database.dart) |
| Android 与测试 | Manifest 已声明联网、网络状态和媒体读取权限。本机项目所用 Flutter SDK 的默认值为 minSdk 24、compileSdk 36、targetSdk 36，Gradle 配置继承这些值 | 缺扫码依赖和文件传输的 Android 桥接。现有 Widget 测试仍会点击旧「磁力」Tab，未发现针对传输的自动化测试。接入时以实际构建产物的 SDK 和合并 Manifest 复核权限。 [Manifest](../android/app/src/main/AndroidManifest.xml) · [Gradle](../android/app/build.gradle.kts) · [导航测试](../test/widget/navigation_test.dart) |

## 2. 首版技术选型

| 环节 | 建议实现 |
| --- | --- |
| 页面与状态 | 复用 Flutter、Riverpod、go_router 和现有主题。新增应用级会话控制器负责页面状态和历史，Android 引擎负责活动连接和文件 I/O。通过 `MethodChannel` 下发命令、查询快照，`EventChannel` 推送状态、逐文件结果及节流后的进度。文件正文始终在 Kotlin 的流中传递。 [Flutter 平台通道](https://docs.flutter.dev/platform-integration/platform-channels) |
| 二维码 | `pretty_qr_code` 绘码，`mobile_scanner` 只识别 QR，Android 使用随包发布的 ML Kit 模型以支持无外网扫码。依赖小样先通过项目的 AGP 9、SDK 和构建检查，再锁定版本。 [绘码包](https://pub.dev/packages/pretty_qr_code) · [扫码包](https://pub.dev/packages/mobile_scanner) · [扫码包变更记录](https://pub.dev/packages/mobile_scanner/changelog) |
| 连接与认证 | 接收方在可达局域网地址启动 Kotlin `SSLServerSocket`，发送方扫码后用 `SSLSocket` 连接。一个双向 TLS 连接承载有长度边界的控制帧和文件块。接收端用 Android Keystore 持有签名私钥，发送端握手时将服务端叶证书的 SHA-256 指纹与二维码逐字节比对，通过后才提交一次性凭证。TLS 由系统实现，允许 TLS 1.2 或更高版本。 [Android TLS Socket](https://developer.android.com/reference/javax/net/ssl/SSLSocket) · [Android Keystore 密钥参数](https://developer.android.com/reference/android/security/keystore/KeyGenParameterSpec) |
| 网络选路 | 首版以可达 IPv4 为基线。在支持的 Wi-Fi 链路上用 `ConnectivityManager`、`LinkProperties` 确定地址和路由，接收侧绑定具体地址和系统分配端口，发送侧按同网路由使用对应 `Network.socketFactory`。热点主机的本地接口和路由单独验证，禁止用固定热点 IP 猜测。接收页根据真实状态刷新邀请。 [Android Network](https://developer.android.com/reference/android/net/Network) · [LinkProperties](https://developer.android.com/reference/android/net/LinkProperties) |
| 发送源 | 保留 `photo_manager` 的相册浏览。Android 上用资源 ID 解析媒体 `content://` URI，使用 `ContentResolver` 读元数据和内容。系统选文件使用 SAF `ACTION_OPEN_DOCUMENT` 多选，保留授权 URI。应用导入的副本直接读私有文件路径。其他平台按现有应用能力显示受支持入口。 [Android SAF](https://developer.android.com/training/data-storage/shared/documents-files) · [部分照片和视频授权](https://developer.android.com/about/versions/14/changes/partial-photo-video-access) |
| 接收目标 | Android 10+ 默认使用 `MediaStore.Downloads` 的 `Download/LumiPlayer/`，以 `IS_PENDING` 控制可见性。较老系统默认提示经 SAF 授权用户可见的接收文件夹。自定义目录用 `ACTION_OPEN_DOCUMENT_TREE` 并保存 URI 授权，通过有写入、改名和清理能力的本机文档提供方验收。 [Android 共享存储](https://developer.android.com/training/data-storage/shared/media) · [SAF 目录授权](https://developer.android.com/training/data-storage/shared/documents-files) · [DocumentsContract](https://developer.android.com/reference/android/provider/DocumentsContract) |
| 权限与存储记录 | 相机只在 P04 使用，媒体权限按当前类型申请。现有 `INTERNET`、`ACCESS_NETWORK_STATE` 用于本地连接。Android 17 且 targetSdk ≥ 37 时，按官方规则对直接局域网访问声明并按需申请 `ACCESS_LOCAL_NETWORK`，targetSdk 36 的生产构建沿用 `INTERNET`。历史继续使用现有 JSON 仓库，凭证和文件正文仅用于活动任务。 [Android 局域网权限](https://developer.android.com/privacy-and-security/local-network-permission) |

这个方案把连接和文件流放在 Android 侧，是因为首版只验收 Android，且媒体 URI、SAF 和分卷存储都需要原生处理。二维码无需设备发现服务。首版使用现成的网络，范围包含两台设备互换收发角色。账号、跨网、电脑接收、iOS、锁屏后台保活和跨会话断点续传沿用需求中的后续范围。APK 仅指用户能通过系统选择器读取的安装包。

Dart 代码沿用 `lib/features/transfer/{presentation,application,domain,data}`。页面和路由消费状态，控制器协调选择、会话与历史，领域层保存清单及结果结构，数据层封装 Android 桥接与历史仓库。Kotlin 在 `com.example.myplayer.transfer` 下分为通道、会话与协议、文件源与接收目标，`MainActivity` 负责注册通道和转交 Android 权限、选择器回调。桥接最少支持 `prepareReceive`、`connectAndSend`、`cancel`、`getSnapshot` 和 `openReceivedFile`，文件选择与目录授权分别用独立命令。P1 增加 `pause`、`resume`。

## 3. 模块与实现方式

### 3.1 文件选择与分享（FR02–FR06）

- 保留 `SelectFilesPage` 的六类、文件夹层级、横向底栏和已选面板。把分类、文件夹、分页、授权和去重交给选择控制器和数据适配器。列表按页加载，切换分类或文件夹时使旧请求失效。全选遍历当前范围的完整元数据，取消全选仅移除该范围。系统返回与页面返回优先关闭已选面板，再退出文件夹。文件夹增加可辨认的来源说明。
- 将待发送文件建模为稳定标识、读取位置、显示名称、MIME、类别、可为空的字节大小和来源。相册预选和浏览用同一媒体身份，`MediaItem.sourceId` 对应 `AssetEntity.id`。SAF 用文档身份或可判定的规范 URI，应用私有文件用规范路径。跨入口能确认属于同一媒体时合并身份；同名文件、不同来源及系统无法证明相同的来源分别保留。
- 相册列表以元数据和按需缩略图渲染，发送时用现有 `AssetEntity.getMediaUrl()` 取得 Android 媒体 URI。按类型请求授权，区分完整、部分和拒绝状态，拒绝时仍可用系统选择器为当前类型补充文件。SAF 记录实际授予的权限，支持持久授权时才持久化，并清理应用已不再引用的授权。选择 APK 使用扩展名复核，混合文件按 MIME 或扩展名归类。保留 `0` 为合法的空文件大小，单独表示未知大小。
- 「下一步」前逐项重新打开来源并确认授权、可读性和大小。未知长度的来源如果可读，可先按限额流式暂存于应用私有目录以确定大小，准备过程可取消并清理；无法读取、超额或不支持的提供方给出具体文件和原因。验证失败时保留选择，允许移除或重选。开始连接时冻结清单，发送打开文件时再次校验长度和可用的变更信息。播放器读取当前正在播放的本地 `MediaItem`，复用 `openTransferShare`。

### 3.2 准备、邀请与状态机（FR07、FR08、FR15）

- P03 保留一个页面，按「检查 → 缺少准备项 → 等待扫码 → 已连接」切换。检查局域网访问、有效的本地链路和保存目标，返回前台重查。监听成功后才亮码；取消等待或离开页面时立即吊销邀请并关闭监听。设备没有互联网时，仍可使用设备间互通的 Wi-Fi 或热点。 [Android 局域网权限](https://developer.android.com/privacy-and-security/local-network-permission) |
- 邀请编码为有版本的应用专用 QR 文本，包含协议版本、会话 ID、数字 IPv4、端口、有效期、证书指纹及由 `SecureRandom` 生成的 256 位一次性凭证。发送端先验证结构、地址类型和同网路由，再连接；到期以接收端计时为准，避免两台手机时钟差导致误判。接收方用单任务门闩防止两次成功认领，认证成功后消费邀请并停止接受新连接。二维码、凭证和发送来源路径不进入对端清单或诊断日志。
- P04 新增 `/transfer/scan`。进入后按需启动相机，首次拒绝、永久拒绝和相机不可用分别给出恢复动作。一次有效识别只允许一次连接尝试，连接中暂停扫码。错误留在当前页，重扫或返回均保留选择。对已关闭的监听端，提示接收码失效或设备不可达，提供重扫动作。握手和清单接受后，双方基于任务 ID 自动进入 `/transfer/task/:id`。准备页和扫码页通过应用级状态消费事件，页面切换不销毁已接手的任务。
- 等待邀请与活动收发共用一套设备级互斥。Kotlin 串行处理状态变更，桥接命令、事件包含 `sessionId` 和序号，Dart 订阅事件并通过快照补齐重建间隔。一个会话完成、失败、取消或离开等待时，由统一清理流程释放相机租用、监听、连接、计时器、回调和文件资源，再释放任务门闩。活动详情返回先询问是否取消，系统后台中断按失败处理，回来重新核实实际状态。

### 3.3 协议、队列与进度（FR09–FR12、FR15）

| 阶段 | 执行规则 |
| --- | --- |
| 配对 | 建立 TLS 并核验证书指纹。`HELLO` 携带协议版本、会话 ID、邀请凭证和发送设备显示名。接收端认证后返回 `HELLO_OK` 和接收设备显示名。超时、忙碌、版本不支持和邀请失效分别映射到页面可理解的状态。 |
| 文件清单 | `MANIFEST` 提交任务 ID、有序文件 ID、名称、类别、MIME 和 64 位字节长度。接收方校验重复 ID、字段与总大小上限、可用空间及目录权限，通过才返回 `MANIFEST_OK`。预检容量是估算，写入阶段仍处理真实的磁盘满和授权失效。 |
| 文件流与校验 | 一次处理一个文件。`FILE_BEGIN → DATA → FILE_END`，控制帧用有长度前缀的 UTF-8 JSON，`DATA` 为有独立长度上限的二进制块。双方边读写边累计字节并更新 SHA-256，发送端在 `FILE_END` 给出摘要。接收方确认字节数和摘要，完成关闭、发布和结果登记后才发 `FILE_OK`。文件顺序、偏移和数据长度须与清单和当前文件状态一致。 |
| 字节进度 | 接收方按已写入字节返回累计 `ACK`，发送端只用收到的累计值计算进度。单写入者负责帧顺序，独立接收控制帧，发送受未确认字节窗口约束。初值为单块 256 KiB、窗口 4 MiB，窗口耗尽、文件结束或定时达到时回 ACK，避免双方等确认。速度根据 ACK 字节差和单调时钟计算。零字节文件靠逐文件确认完成，校验保存期间单独显示状态。 |
| 任务结束 | 所有文件收到 `FILE_OK` 后，发送端发 `FINISH`，接收端核对已提交结果并回 `FINISH_ACK`。接收方按实际提交结果记录成功，发送方收到最终确认才标记成功。连接恰在最终确认阶段断开时，发送侧提示对端结果未确认，接收侧保留已保存文件。 |
| 取消、中断与重试 | 双方都可发 `CANCEL`，随后有界地等待通知送出并关闭资源。文件读写失败或断网终止本轮队列，已保存的文件保留，未完成项标记取消或失败。发送方重试时预选未确认成功的项目，提示状态不明项可能已落盘，重新授权、复核并扫描新码。 |
| 暂停和继续（P1） | 允许任一端请求，以发送端发出的控制序号串行决定暂停和恢复。到块边界收完已在途数据、确认偏移后，双方进入暂停，保留当前文件流和连接，心跳继续。恢复从同一连接内已确认位置继续。会话失效时进入中断并走重试。暂停在文件发布临界段内延迟到可安全停止的位置。 |

参数集中配置并记录在协议测试中。建议初值为二维码 120 秒、TCP 连接 5 秒、TLS 和会话认证 8 秒、10 秒心跳、无网络进展 30 秒，以及 P1 暂停最长 120 秒。二维码等待期间到期自动换码。控制帧最大 64 KiB、每批至多 200 文件并同时受清单字节上限约束，长度和总量先校验再分配内存。门槛与时限在真机压测后定值，选择页提前提示批次超限。上传速度受网络和设备影响。保存校验阶段继续处理控制帧，并给本地 I/O 设置可取消机制及独立的进展超时。

### 3.4 保存、打开与恢复（FR13、FR15）

- 接收方提取单一文件名，拒绝目录分隔符、控制字符、目录跳转和过长名称，保存位置只由本机选择。重名采用数字序号并使用系统创建的新条目，不以覆盖方式打开现有 URI。发布后记录提供方实际返回的名称和 URI。
- 默认目录直接流式写新建的 `IS_PENDING=1` 条目，通过长度与摘要校验并关闭文件后，将 `IS_PENDING` 改为 `0`。SAF 目录先写清晰标识的唯一临时文档，校验和关闭后才在同目录改名。授权时验证提供方具备创建、改名、删除及不覆盖行为，UI 对不适合的目录要求重选。失败时只清理本轮暂存对象。 [Android 共享存储](https://developer.android.com/training/data-storage/shared/media) · [DocumentsContract](https://developer.android.com/reference/android/provider/DocumentsContract)
- 原生侧按任务、文件 ID 登记暂存和发布结果，用于崩溃后的清理和核对。创建临时对象前记录唯一暂存名，创建后记录 URI，发布前登记目标名，文件发布并登记结果后再发 `FILE_OK`。重启只清理可确认为本应用遗留的未发布对象。若文件已发布而历史尚未写完，保留文件并恢复逐项结果，原任务标记中断。SAF 返回新 URI 时更新登记，恢复逻辑核对临时名、目标名与提供方实际结果，避免删除已经发布的文件。
- 「打开」前重新验证授权和文件存在。视频用接收 URI 接入现有播放器的本地单项播放；扩展解析路径以允许受信任的 Android `content://`，在真机验证 `media_kit` 能打开并拖动进度。图片、音频和文档通过 `ACTION_VIEW`、MIME 和临时 URI 读取授权交给系统应用，缺查看器时提供提示。APK 和压缩包提供保存位置及文件管理入口。

### 3.5 详情与历史（FR10、FR11、FR14）

- P05 按任务 ID 展示设备、方向、当前文件、总字节、实际速度、队列和逐文件结果。传输中可取消，失败可重试，完成可打开文件。P01 最近三条可打开对应详情。P06 新增 `/transfer/records`，方向与类型组合筛选，混合任务按符合条件的文件展示并保留所属任务。
- 将当前 `TransferController` 和 `TransferRepository` 用作历史读取、更新和筛选入口，活动状态来自会话控制器。记录保留任务 ID、方向、时间、总字节、已确认字节和错误码。逐文件结果保存文件 ID、类型、字节、校验结果、保存 URI 或本地来源引用、状态和失败原因。兼容现有只有任务级结果的行，避免凭空补造逐文件成功状态。建议首版沿用 50 个最近任务的保留上限，历史页展示全部保留项，已收文件独立于记录保留期限。
- 高频进度在内存节流更新，持久化按任务创建、文件提交和任务终态触发。按任务 ID 幂等写入并等待落盘，传输仓库需能获知持久化失败。沿用现有 `LocalDatabase` 的默认调用语义，为传输提供可观测写入结果和可恢复的文件替换路径。启动时先与原生清理记录核对，再将无活动会话的旧 `queued`、`running` 或 `paused` 记录归为中断。保存历史失败时报告记录状态，已经发布的文件保持可用。

## 4. 实施顺序与每步交付

| 步骤 | 工作 | 交付成果与进入下一步的条件 |
| --- | --- | --- |
| 1. 验证 Android 技术路径 | 验证扫码插件构建、Keystore TLS 证书与指纹校验、Wi-Fi 和热点选路、URI 直读及 `MediaStore` 临时写入，试跑旧系统 SAF。记录 SDK、机型、网络、权限和实际落盘位置。 | **Android 验证 APK、协议字段草案和真机记录。** 两台手机在同一 Wi-Fi 和热点上各交换角色传输一个测试文件，哈希一致。错误指纹拒绝连接；关闭蜂窝或断开外网依然可配对。旧系统验证由独立测试记录覆盖。热点主机选路、插件兼容性或目标目录出错时先解决该路径。 |
| 2. 完成选择与分享 | 拆出文件来源和选择控制器，统一去重，补齐完整分页、分类权限、SAF 多选和可读性校验。接播放器、单条及批量分享，更新过时导航用例。 | **可编辑且可验证的发送清单、自动化测试。** 六类可添加，超过 200 项可浏览并按范围全选，单条、多选和播放器预选正常。重复选同一相册资产只留一项，同名文件可同时保留，权限撤销可恢复选择。覆盖 AC01–AC08。 |
| 3. 接通扫码与会话 | 实现 P03、P04，补充局域网准备、权限恢复、二维码、TLS 握手、凭证消费和页面跳转。 | **双机配对构建、扫码与状态测试。** 有效扫码只建立一条会话，接收端无需相机，关闭蓝牙可收发。非法、过期、重复二维码和网络不可达可恢复，退出等待后旧码马上失效。覆盖 AC09–AC16 的配对部分及 AC24 的监听回收。 |
| 4. 完成 P0 收发闭环 | 实现清单校验、混合队列、文件流、ACK、SHA-256、保存后确认、详情、取消和重试。 | **能真实收发的内部 APK、协议回归测试和双机结果。** 双方自动进入详情并传输，字节进度正确，空文件能完成，重名保留旧文件。断网、注入校验不一致、取消、空间不足或写入失败时终止任务并清理未完成文件，已完成文件仍可用。覆盖 AC15、AC17、AC19–AC21、AC25。 |
| 5. 完成历史、保存位置和恢复 | 接最近记录详情与 P06，支持筛选和打开文件；完成旧版本和自定义目录的 SAF 保存、兼容旧记录、冷启动核对与清理。 | **完整 P0 候选 APK、历史兼容和恢复测试。** 混合任务能按匹配文件筛选，重启仍可看记录，删除文件或撤回授权时提示失效。进程中断后不会保留假活动任务，已发布文件可核对并保留。覆盖 AC02、AC10 的保存准备、AC22–AC24。 |
| 6. P1 暂停与首版发布验收 | 若纳入 P1，实现会话内双端暂停、继续、超时和互操作验证。回归前后台、快速进出、旧系统、分批选择和大文件性能。 | **Android 候选 APK、P0 验收清单、真机报告和测量数据。** 所有 P0 验收通过后方可发布。P1 纳入时 AC18 必须通过，延期时界面隐藏暂停和继续。测试记录至少两种 Android 版本与两个厂商、Wi-Fi 和热点、双方角色，以及 1 GB 以上文件的字节数、SHA-256、耗时、峰值内存和失败恢复。 |

建议验收命令沿用项目 CI 的 `dart format --output=none --set-exit-if-changed lib test integration_test`、`flutter analyze`、`flutter test --exclude-tags preview` 和 `flutter build apk --debug`。在仓库 `android` 目录执行 `./gradlew.bat testDebugUnitTest`，覆盖协议帧边界、状态机、重入、超时和取消。权限、系统文件提供方、热点与进程中断使用 Android 真机验收。权限矩阵应纳入 API 24–28 的 SAF 回退、API 29+ 的公开下载目录、Android 13 的媒体分类型授权、Android 14+ 的部分照片和视频授权，以及升级 targetSdk 时的 Android 17 局域网授权。回归报告留存机型、系统与目标 SDK、收发角色、网络拓扑、文件大小、两端结果、峰值内存及实际保存位置。
