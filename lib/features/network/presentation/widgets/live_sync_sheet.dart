// -------------------------------------------------------------------------
// 功能：双路同步面板
//
// 主要内容：
// - 显示画面 / 声音两路的累计延迟
// - 画面慢 0.5 秒、声音慢 0.5 秒、重新连接并从零校准
// -------------------------------------------------------------------------

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/ui_kit.dart';
import '../../data/dual_live_session.dart';

/// 同步调节底部面板。
class LiveSyncSheet extends StatefulWidget {
  const LiveSyncSheet({
    super.key,
    required this.session,
    required this.onRestart,
  });

  final DualLiveSession session;
  final VoidCallback onRestart;

  @override
  State<LiveSyncSheet> createState() => _LiveSyncSheetState();
}

class _LiveSyncSheetState extends State<LiveSyncSheet> {
  bool _busy = false;

  Future<void> _delay({required bool picture}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (picture) {
        await widget.session.delayPicture(const Duration(milliseconds: 500));
      } else {
        await widget.session.delayVoice(const Duration(milliseconds: 500));
      }
    } on Object catch (error) {
      if (mounted) showToast(context, '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final DualLiveSession session = widget.session;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Text(
                  '同步调节',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(
                    Icons.close_rounded,
                    color: Colors.white54,
                    size: 20,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              '画面延迟 ${(session.pictureDelay.inMilliseconds / 1000).toStringAsFixed(1)}s'
              ' · 声音延迟 ${(session.voiceDelay.inMilliseconds / 1000).toStringAsFixed(1)}s',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 16),
            _SyncAction(
              icon: Icons.ondemand_video_rounded,
              title: '画面慢 0.5 秒',
              subtitle: '声音比画面晚时使用',
              enabled: !_busy && session.hasVoice,
              onTap: () => _delay(picture: true),
            ),
            _SyncAction(
              icon: Icons.graphic_eq_rounded,
              title: '声音慢 0.5 秒',
              subtitle: '画面比声音晚时使用',
              enabled: !_busy && session.hasVoice,
              onTap: () => _delay(picture: false),
            ),
            _SyncAction(
              icon: Icons.restart_alt_rounded,
              title: '重新连接并从零校准',
              subtitle: '延迟会重置，需要重新建立两路连接',
              enabled: !_busy,
              onTap: widget.onRestart,
            ),
            const SizedBox(height: 6),
            const Text(
              '同步只在本次播放内有效，重连或切换直播间后会重置。',
              style: TextStyle(
                color: Colors.white30,
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

class _SyncAction extends StatelessWidget {
  const _SyncAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: <Widget>[
            Icon(
              icon,
              size: 20,
              color: enabled ? AppColors.primary : Colors.white24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    title,
                    style: TextStyle(
                      color: enabled ? Colors.white : Colors.white38,
                      fontSize: 13.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Colors.white30, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
