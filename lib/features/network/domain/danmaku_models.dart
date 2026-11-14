// -------------------------------------------------------------------------
// 功能：直播弹幕领域模型
//
// 主要内容：
// - DanmakuMessage：一条已解析的弹幕 / 醒目留言
// - DanmakuStatus：连接状态，供弹幕区展示
// -------------------------------------------------------------------------

/// 弹幕连接状态。
enum DanmakuStatus { idle, connecting, connected, reconnecting, failed }

extension DanmakuStatusX on DanmakuStatus {
  String get label {
    switch (this) {
      case DanmakuStatus.idle:
        return '待连接';
      case DanmakuStatus.connecting:
        return '连接中…';
      case DanmakuStatus.connected:
        return '已连接';
      case DanmakuStatus.reconnecting:
        return '重连中…';
      case DanmakuStatus.failed:
        return '连接失败';
    }
  }

  bool get active => this == DanmakuStatus.connected;
}

/// 一条弹幕。颜色是 RGB 十进制（B 站 `info[0][3]`），普通弹幕为白色。
class DanmakuMessage {
  const DanmakuMessage({
    required this.id,
    required this.user,
    required this.text,
    required this.color,
    required this.receivedAt,
    this.superChat = false,
    this.price = 0,
    this.emoticonUrl,
  });

  final String id;
  final String user;
  final String text;

  /// RGB 值，例如 `0xFFFFFF`。
  final int color;
  final DateTime receivedAt;

  /// 是否为醒目留言（Super Chat）。
  final bool superChat;

  /// 醒目留言价格（元），普通弹幕为 0。
  final int price;

  /// 当整条弹幕就是一个表情时，这里是表情图片地址。
  final String? emoticonUrl;
}

/// B 站官方直播表情。
///
/// [emoji] 是发送时写进弹幕内容的文本（例如 `[dog]`），[url] 用于显示。
class LiveEmoticon {
  const LiveEmoticon({
    required this.emoji,
    required this.label,
    required this.url,
  });

  /// 发送用的表情文本，形如 `[dog]`。
  final String emoji;

  /// 表情名称，用于无障碍与提示。
  final String label;

  /// 表情图片地址。
  final String url;
}
