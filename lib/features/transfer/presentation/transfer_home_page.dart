// -------------------------------------------------------------------------
// 功能：传输首页（P01）
//
// 主要内容：
// - 发送 / 接收两个主要操作
// - 最近传输记录（最多三条）与「查看全部」入口
// - 无记录时的空状态
// -------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/ui_kit.dart';
import '../application/transfer_controller.dart';
import '../domain/transfer_models.dart';

class TransferHomePage extends ConsumerWidget {
  const TransferHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<TransferRecord> records = ref.watch(transferControllerProvider);

    return Scaffold(
      backgroundColor: context.appBackground,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '文件传输',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: context.textPrimary,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => _showHelp(context),
                  icon: Icon(
                    Icons.help_outline_rounded,
                    size: 21,
                    color: context.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: <Widget>[
                Expanded(
                  child: _ActionCard(
                    icon: Icons.send_rounded,
                    title: '发送文件',
                    subtitle: '选择文件发送',
                    filled: true,
                    onTap: () => context.push('/transfer/select'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ActionCard(
                    icon: Icons.download_rounded,
                    title: '接收文件',
                    subtitle: '等待对方连接',
                    filled: false,
                    onTap: () => context.push('/transfer/receive'),
                  ),
                ),
              ],
            ),
            SectionHeader(
              title: '最近传输',
              actionLabel: records.isEmpty ? null : '查看全部',
              onAction: records.isEmpty
                  ? null
                  : () => context.push('/transfer/records'),
            ),
            if (records.isEmpty)
              const _EmptyRecent()
            else
              for (final TransferRecord record in records.take(3)) ...<Widget>[
                _RecordTile(record: record),
                const SizedBox(height: 10),
              ],
          ],
        ),
      ),
    );
  }

  void _showHelp(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.cardColor,
      builder: (BuildContext sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '怎么传输文件',
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                  color: context.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '1. 两台手机连接同一个 Wi-Fi 或热点\n'
                '2. 接收方点「接收文件」并展示二维码\n'
                '3. 发送方选好文件后扫码，连接成功即开始发送\n\n'
                '首版不经过服务器，文件只在两台手机之间直传。',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.7,
                  color: context.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.filled,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final Color background = filled
        ? AppColors.primary
        : context.cardColor;
    final Color foreground = filled ? Colors.white : AppColors.primary;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(16),
          border: filled
              ? null
              : Border.all(color: context.dividerColor, width: 0.8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: filled
                    ? Colors.white.withValues(alpha: 0.20)
                    : context.softPrimary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 22, color: foreground),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: filled ? Colors.white : context.textPrimary,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 11,
                color: filled
                    ? Colors.white.withValues(alpha: 0.80)
                    : context.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordTile extends StatelessWidget {
  const _RecordTile({required this.record});

  final TransferRecord record;

  @override
  Widget build(BuildContext context) {
    final bool running = !record.status.isFinished;
    final bool failed = record.status == TransferStatus.failed;
    final bool cancelled = record.status == TransferStatus.cancelled;

    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _TypeBadge(type: record.files.first.type),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  record.summary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: context.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${record.direction.label}至 ${record.deviceName.isEmpty ? '对方设备' : record.deviceName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: context.textSecondary,
                  ),
                ),
                const SizedBox(height: 7),
                if (running) ...<Widget>[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: record.progress,
                      minHeight: 4,
                      backgroundColor: context.dividerColor,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        AppColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: <Widget>[
                      Text(
                        '${formatBytes(record.transferredBytes)} / ${formatBytes(record.totalBytes)}',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: context.textSecondary,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${(record.progress * 100).round()}%',
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ] else
                  Row(
                    children: <Widget>[
                      Icon(
                        record.status == TransferStatus.completed
                            ? Icons.check_circle_rounded
                            : Icons.error_outline_rounded,
                        size: 13,
                        color: record.status == TransferStatus.completed
                            ? const Color(0xFF37C26A)
                            : (cancelled
                                  ? context.textSecondary
                                  : const Color(0xFFE24B4A)),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        failed ? '失败' : record.status.label,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: record.status == TransferStatus.completed
                              ? const Color(0xFF37C26A)
                              : (cancelled
                                    ? context.textSecondary
                                    : const Color(0xFFE24B4A)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        formatBytes(record.totalBytes),
                        style: TextStyle(
                          fontSize: 10.5,
                          color: context.textSecondary,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.type});

  final TransferFileType type;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: context.softPrimary,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Icon(_iconFor(type), size: 18, color: AppColors.primary),
    );
  }
}

IconData _iconFor(TransferFileType type) {
  switch (type) {
    case TransferFileType.video:
      return Icons.videocam_rounded;
    case TransferFileType.app:
      return Icons.android_rounded;
    case TransferFileType.document:
      return Icons.description_rounded;
    case TransferFileType.image:
      return Icons.image_rounded;
    case TransferFileType.audio:
      return Icons.music_note_rounded;
    case TransferFileType.other:
      return Icons.insert_drive_file_rounded;
  }
}

class _EmptyRecent extends StatelessWidget {
  const _EmptyRecent();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      child: Column(
        children: <Widget>[
          Icon(
            Icons.swap_horiz_rounded,
            size: 34,
            color: context.textSecondary.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 10),
          Text(
            '还没有传输记录',
            style: TextStyle(fontSize: 12.5, color: context.textSecondary),
          ),
          const SizedBox(height: 4),
          Text(
            '发送或接收过的文件会出现在这里',
            style: TextStyle(
              fontSize: 11,
              color: context.textSecondary.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }
}
