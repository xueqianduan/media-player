// -------------------------------------------------------------------------
// 功能：直播弹幕区与弹幕输入栏
//
// 主要内容：
// - 弹幕列表：实时滚动、自动贴底，彩色昵称与弹幕颜色
// - 醒目留言：金色块展示价格与内容
// - 连接状态：连接中 / 已连接 / 重连中 / 失败
// - 底部输入栏：发送能力下一版开放
// -------------------------------------------------------------------------

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/danmaku_models.dart';
import '../../domain/live_models.dart';

/// 弹幕区：展示所选直播间的实时弹幕。
class LiveDanmakuPanel extends StatelessWidget {
  const LiveDanmakuPanel({
    super.key,
    required this.source,
    required this.status,
    required this.messages,
    this.roomName = '',
    this.error,
  });

  final DanmakuSource source;
  final DanmakuStatus status;
  final List<DanmakuMessage> messages;

  /// 弹幕来源房间名，为空时只显示来源类型。
  final String roomName;

  /// 连接失败原因，仅在 [status] 为 failed 时展示。
  final String? error;

  bool get _enabled => source != DanmakuSource.off;

  String get _sourceLabel {
    switch (source) {
      case DanmakuSource.picture:
        return roomName.isEmpty ? '画面直播间' : roomName;
      case DanmakuSource.voice:
        return roomName.isEmpty ? '声音直播间' : roomName;
      case DanmakuSource.off:
        return '未开启';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      decoration: BoxDecoration(
        color: const Color(0xFF12151E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _buildHeader(),
          Expanded(
            child: messages.isEmpty
                ? _buildPlaceholder()
                : RepaintBoundary(
                    child: ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.only(top: 2, bottom: 10),
                      itemCount: messages.length,
                      itemBuilder: (BuildContext context, int index) {
                        // reverse + 反向取：最新一条贴在底部，用户上滑时不会被拽回。
                        final DanmakuMessage message =
                            messages[messages.length - 1 - index];
                        return _DanmakuRow(
                          key: ValueKey<String>(message.id),
                          message: message,
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 11, 12, 8),
      child: Row(
        children: <Widget>[
          const Icon(Icons.forum_rounded, size: 14, color: Colors.white54),
          const SizedBox(width: 6),
          const Text(
            '弹幕',
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              _sourceLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white38, fontSize: 10.5),
            ),
          ),
          const SizedBox(width: 6),
          _StatusBadge(
            label: _enabled ? status.label : '未开启',
            color: _statusColor,
            busy:
                _enabled &&
                (status == DanmakuStatus.connecting ||
                    status == DanmakuStatus.reconnecting),
          ),
        ],
      ),
    );
  }

  Color get _statusColor {
    if (!_enabled) return Colors.white30;
    switch (status) {
      case DanmakuStatus.connected:
        return const Color(0xFF37C26A);
      case DanmakuStatus.failed:
        return const Color(0xFFE05A5A);
      case DanmakuStatus.connecting:
      case DanmakuStatus.reconnecting:
        return const Color(0xFFE0A94A);
      case DanmakuStatus.idle:
        return Colors.white30;
    }
  }

  Widget _buildPlaceholder() {
    final String title;
    final String subtitle;
    if (!_enabled) {
      title = '弹幕已关闭';
      subtitle = '在首页选择「弹幕来源」后，这里会实时滚动弹幕';
    } else {
      switch (status) {
        case DanmakuStatus.connecting:
          title = '正在连接弹幕…';
          subtitle = '正在获取弹幕服务器并完成鉴权';
        case DanmakuStatus.connected:
          title = '已连接，等待弹幕';
          subtitle = '这个直播间暂时没人说话';
        case DanmakuStatus.reconnecting:
          title = '弹幕连接中断';
          subtitle = '正在自动重连，画面不受影响';
        case DanmakuStatus.failed:
          title = '弹幕连接失败';
          subtitle = error ?? '请稍后重试，或换一个弹幕来源';
        case DanmakuStatus.idle:
          title = '弹幕未连接';
          subtitle = '弹幕会在直播开始后自动连接';
      }
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              !_enabled
                  ? Icons.chat_bubble_outline_rounded
                  : Icons.forum_outlined,
              size: 30,
              color: Colors.white.withValues(alpha: 0.18),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(color: Colors.white54, fontSize: 12.5),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white24,
                fontSize: 11,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 连接状态小胶囊。
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.label,
    required this.color,
    required this.busy,
  });

  final String label;
  final Color color;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (busy)
            SizedBox(
              width: 8,
              height: 8,
              child: CircularProgressIndicator(strokeWidth: 1.4, color: color),
            )
          else
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: color, fontSize: 9.5)),
        ],
      ),
    );
  }
}

/// 一条弹幕：`昵称：内容`，颜色按弹幕自身颜色并做暗色提亮。
class _DanmakuRow extends StatelessWidget {
  const _DanmakuRow({super.key, required this.message});

  final DanmakuMessage message;

  @override
  Widget build(BuildContext context) {
    if (message.superChat) return _SuperChatRow(message: message);

    final Color color = _readable(message.color);
    final String? emoticon = message.emoticonUrl;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 3.5, 12, 3.5),
      child: Text.rich(
        TextSpan(
          children: <InlineSpan>[
            TextSpan(
              text: '${message.user}：',
              style: const TextStyle(
                color: Color(0xFF7FB2E5),
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                height: 1.45,
              ),
            ),
            if (emoticon != null)
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Image.network(
                  emoticon,
                  width: 22,
                  height: 22,
                  headers: const <String, String>{
                    'Referer': 'https://live.bilibili.com/',
                  },
                  errorBuilder:
                      (BuildContext context, Object error, StackTrace? stack) {
                        return Text(
                          message.text,
                          style: TextStyle(color: color, fontSize: 12.5),
                        );
                      },
                ),
              )
            else
              TextSpan(
                text: message.text,
                style: TextStyle(color: color, fontSize: 12.5, height: 1.45),
              ),
          ],
        ),
      ),
    );
  }

  /// 深色弹幕（纯红、纯蓝等）在深色背景上看不清，按需向白色插值。
  static Color _readable(int rgb) {
    final Color raw = Color(0xFF000000 | (rgb & 0xFFFFFF));
    if (raw.computeLuminance() >= 0.28) return raw;
    return Color.lerp(raw, Colors.white, 0.55) ?? Colors.white;
  }
}

/// 醒目留言：金色块 + 价格。
class _SuperChatRow extends StatelessWidget {
  const _SuperChatRow({required this.message});

  final DanmakuMessage message;

  @override
  Widget build(BuildContext context) {
    final Color accent = _DanmakuRow._readable(message.color);
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 4, 10, 4),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            accent.withValues(alpha: 0.30),
            accent.withValues(alpha: 0.10),
          ],
        ),
        border: Border.all(color: accent.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Flexible(
                child: Text(
                  message.user,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: accent,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 1.5,
                ),
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '¥${message.price}',
                  style: const TextStyle(
                    color: Color(0xFF20160A),
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            message.text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

/// 底部弹幕输入栏：输入、发送；未登录时由页面拉起 B 站登录。
class LiveDanmakuInputBar extends StatefulWidget {
  const LiveDanmakuInputBar({
    super.key,
    required this.enabled,
    required this.sending,
    required this.onSend,
    required this.onBlocked,
    required this.onEmoji,
    this.compact = false,
    this.controller,
    this.focusNode,
  });

  /// 是否已选择弹幕来源；关闭时只提示，不允许输入。
  final bool enabled;

  /// 正在发送，按钮显示进度并禁止重复提交。
  final bool sending;

  /// 返回 true 表示发送成功，输入框会清空。
  final Future<bool> Function(String text) onSend;

  /// 未选择弹幕来源时点击输入框。
  final VoidCallback onBlocked;

  /// 打开表情面板。
  final VoidCallback onEmoji;

  /// 横屏紧凑版：高度与旁边的控制台图标对齐。
  final bool compact;

  /// 外部控制器：竖屏与横屏共用同一份输入内容。
  final TextEditingController? controller;
  final FocusNode? focusNode;

  @override
  State<LiveDanmakuInputBar> createState() => _LiveDanmakuInputBarState();
}

class _LiveDanmakuInputBarState extends State<LiveDanmakuInputBar> {
  late final bool _ownsController = widget.controller == null;
  late final TextEditingController _controller =
      widget.controller ?? TextEditingController();
  late final bool _ownsFocus = widget.focusNode == null;
  late final FocusNode _focus = widget.focusNode ?? FocusNode();

  @override
  void dispose() {
    if (_ownsController) _controller.dispose();
    if (_ownsFocus) _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (widget.sending || !widget.enabled) return;
    final String text = _controller.text.trim();
    if (text.isEmpty) {
      _focus.requestFocus();
      return;
    }
    final bool ok = await widget.onSend(text);
    if (!mounted || !ok) return;
    _controller.clear();
    _focus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final bool canType = widget.enabled && !widget.sending;
    final bool compact = widget.compact;
    final double height = compact ? 32 : 46;

    return Padding(
      padding: compact
          ? EdgeInsets.zero
          : const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: <Widget>[
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.enabled ? null : widget.onBlocked,
              child: Container(
                height: height,
                padding: EdgeInsets.only(
                  left: compact ? 12 : 16,
                  right: compact ? 2 : 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(height / 2),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.10),
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        focusNode: _focus,
                        enabled: canType,
                        maxLength: 20,
                        maxLines: 1,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _submit(),
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: compact ? 12 : 13.5,
                        ),
                        cursorColor: AppColors.primary,
                        decoration: InputDecoration(
                          isDense: true,
                          counterText: '',
                          // 主题默认给输入框填了底色，这里关掉：整条胶囊就是输入区。
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                          hintText: widget.enabled ? '发个弹幕…' : '先在首页选择弹幕来源',
                          hintStyle: TextStyle(
                            color: Colors.white38,
                            fontSize: compact ? 11.5 : 13,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: widget.onEmoji,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: BoxConstraints(
                        minWidth: compact ? 26 : 28,
                        minHeight: compact ? 26 : 28,
                      ),
                      icon: Icon(
                        Icons.emoji_emotions_outlined,
                        size: compact ? 17 : 18,
                        color: Colors.white.withValues(alpha: 0.35),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(width: compact ? 6 : 8),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: canType
                ? _submit
                : (widget.enabled ? null : widget.onBlocked),
            child: Container(
              width: height,
              height: height,
              decoration: BoxDecoration(
                color: canType
                    ? AppColors.primary
                    : AppColors.primary.withValues(alpha: 0.25),
                shape: BoxShape.circle,
              ),
              child: widget.sending
                  ? Padding(
                      padding: EdgeInsets.all(compact ? 9 : 13),
                      child: const CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white70,
                      ),
                    )
                  : Icon(
                      Icons.send_rounded,
                      size: compact ? 16 : 18,
                      color: canType ? Colors.white : Colors.white38,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
