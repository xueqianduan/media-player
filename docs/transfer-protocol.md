# LumiPlayer 局域网传输协议（v1）

配套实现：`android/app/src/main/kotlin/com/example/myplayer/transfer/`。
首版只覆盖 Android 双机、同一 Wi-Fi / 热点，不含暂停续传与断点恢复。

## 1. 邀请与连接

二维码文本（`LUMI1`，7 段）：

```
LUMI1|sessionId|ip|port|fingerprint|token|expiresAt
```

| 字段 | 说明 |
| --- | --- |
| sessionId | 接收端生成的 UUID，用于事件与状态对齐 |
| ip / port | 接收端绑定的可达 IPv4 与系统分配端口 |
| fingerprint | 接收端证书 DER 的 SHA-256（64 位小写 hex） |
| token | `SecureRandom` 32 字节 hex，只允许使用一次 |
| expiresAt | Unix 秒；以接收端为准，默认 120 秒 |

发送端解析后先校验格式与过期时间，再建立 TLS 1.2+ 连接；握手完成后**先比对指纹**，不一致立即断开，之后才发送凭证。

## 2. 帧格式

```
[type:1][length:4 大端][payload]
```

- `type=0`：UTF-8 JSON 控制帧，单帧 ≤ 64 KiB；
- `type=1`：文件数据块，默认 256 KiB。

## 3. 控制消息

| 方向 | 消息 | 关键字段 |
| --- | --- | --- |
| 发送 → 接收 | `HELLO` | `v`、`sessionId`、`token`、`name` |
| 接收 → 发送 | `HELLO_OK` / `HELLO_ERR` | `name` / `message` |
| 发送 → 接收 | `MANIFEST` | `taskId`、`files[]`（`id,name,mime,type,size`） |
| 接收 → 发送 | `MANIFEST_OK` / `MANIFEST_ERR` | `taskId` / `message` |
| 发送 → 接收 | `FILE_BEGIN` | `id` |
| 收发 | `DATA`（type=1） | 原始字节 |
| 发送 → 接收 | `FILE_END` | `id`、`size`、`sha256` |
| 接收 → 发送 | `FILE_OK` / `FILE_ERR` | `name`、`uri` / `message` |
| 接收 → 发送 | `ACK` | `bytes`（累计已写入字节） |
| 发送 → 接收 | `FINISH` | `taskId` |
| 接收 → 发送 | `FINISH_ACK` | `taskId` |
| 双向 | `CANCEL` / `PING` / `PONG` | — |

## 4. 时序与约束

- 单任务、单连接；接收端只接受一次成功认领，认证后立即关闭监听；
- 发送端按 4 MiB 未确认窗口等待 `ACK`；接收端每 4 MiB 或 200 ms 回一次；定时 ACK 只更新进度，不重置窗口计数，窗口边界必须再次确认累计字节；
- 每个文件独立计算 SHA-256，接收端校验字节数与摘要后才发布并回 `FILE_OK`；
- 清单上限 200 个文件、总大小 8 GiB；控制帧与数据块在分配内存前先校验长度；
- 超时：TCP 连接 5 s，握手/会话 8 s，读超时 30 s，邀请 120 s。

## 5. 落盘

- API 29+：`MediaStore.Downloads`，`Download/LumiPlayer/`，写入时 `IS_PENDING=1`，校验通过后置 0；
- API < 29：应用外部目录 `Download/LumiPlayer`（无需额外权限）；
- 重名自动追加 ` (1)`、` (2)`，不覆盖已有文件；
- 失败时删除本轮创建的对象。

## 6. 已知限制（v1）

- 证书随包发布，未做到每台设备独立生成；指纹校验可防误连与普通中间人，但拿到 APK 私钥的人理论上可仿冒；
- 未实现 Android 17 的 `ACCESS_LOCAL_NETWORK` 运行时授权（targetSdk 36 暂不需要）；
- 未实现暂停/续传、断点恢复、SAF 自定义目录。
