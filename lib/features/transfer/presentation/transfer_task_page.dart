// -------------------------------------------------------------------------
// 功能：传输任务详情（P05）
//
// 展示设备、进度、当前文件与逐文件结果；传输中可取消，完成后可打开文件。
// -------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/ui_kit.dart';
import '../application/transfer_session_controller.dart';
import '../data/transfer_bridge.dart';
import '../domain/transfer_models.dart';
import '../domain/transfer_session.dart';

class TransferTaskPage extends ConsumerWidget {
  const TransferTaskPage({super.key, this.fromPlayer = false});

  /// 由播放控制台发起：结束后逐级返回播放器，而不是回到首页。
  final bool fromPlayer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TransferSessionState session = ref.watch(transferSessionProvider);
    final bool busy = !session.finished;
    final bool receive = session.direction == TransferDirection.receive;

    return Scaffold(
      backgroundColor: context.appBackground,
      appBar: AppBar(
        backgroundColor: context.appBackground,
        elevation: 0,
        title: Text(receive ? '接收任务' : '发送任务'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => _leave(context, ref, busy),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
        children: <Widget>[
          AppCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(
                      receive ? Icons.download_rounded : Icons.upload_rounded,
                      size: 18,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      session.phase.label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: context.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      session.deviceName.isEmpty ? '对端设备' : session.deviceName,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: context.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: session.progress,
                    minHeight: 6,
                    backgroundColor: context.dividerColor,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${formatBytes(session.receivedBytes)} / '
                  '${formatBytes(session.totalBytes)}',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: context.textSecondary,
                  ),
                ),
                if (session.currentFile.isNotEmpty && busy) ...<Widget>[
                  const SizedBox(height: 6),
                  Text(
                    session.currentFile,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: context.textSecondary,
                    ),
                  ),
                ],
                if (session.error != null) ...<Widget>[
                  const SizedBox(height: 10),
                  Text(
                    session.error!,
                    style: const TextStyle(
                      color: Color(0xFFE08A8A),
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (session.results.isNotEmpty) ...<Widget>[
            SectionHeader(title: '文件（${session.results.length}）'),
            for (final TransferFileResult result in session.results)
              AppCard(
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                child: Row(
                  children: <Widget>[
                    Icon(
                      result.ok
                          ? Icons.check_circle_rounded
                          : Icons.error_outline_rounded,
                      size: 18,
                      color: result.ok
                          ? const Color(0xFF37C26A)
                          : const Color(0xFFE24B4A),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            result.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: context.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            result.ok
                                ? formatBytes(result.bytes)
                                : (result.error ?? '失败'),
                            style: TextStyle(
                              fontSize: 10.5,
                              color: context.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (result.ok && result.uri != null)
                      TextButton(
                        onPressed: () => _open(context, result),
                        child: const Text('打开'),
                      ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 12),
          if (busy)
            OutlinedButton.icon(
              onPressed: () => _cancel(context, ref),
              icon: const Icon(Icons.close_rounded, size: 17),
              label: const Text('取消传输'),
            )
          else ...<Widget>[
            FilledButton(
              onPressed: () {
                ref.read(transferSessionProvider.notifier).reset();
                if (fromPlayer) {
                  context.pop(true);
                } else {
                  context.go('/');
                }
              },
              child: Text(fromPlayer ? '返回播放器' : '完成'),
            ),
            if (fromPlayer &&
                session.phase == TransferPhase.failed) ...<Widget>[
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => context.pop(),
                child: const Text('重新扫码'),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Future<void> _open(BuildContext context, TransferFileResult result) async {
    try {
      await TransferBridge().openFile(uri: result.uri!, mime: '*/*');
    } on Object catch (error) {
      if (context.mounted) showToast(context, '$error');
    }
  }

  Future<bool> _cancel(BuildContext context, WidgetRef ref) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('取消传输？'),
        content: const Text('已完成的文件会保留，未完成的会被清理。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('继续传输'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('取消传输'),
          ),
        ],
      ),
    );
    if (ok != true) return false;
    await ref.read(transferSessionProvider.notifier).cancel();
    return true;
  }

  Future<void> _leave(BuildContext context, WidgetRef ref, bool busy) async {
    if (!busy) {
      if (fromPlayer) {
        ref.read(transferSessionProvider.notifier).reset();
        context.pop(true);
      } else {
        context.pop();
      }
      return;
    }
    final bool cancelled = await _cancel(context, ref);
    if (!context.mounted || !cancelled) return;
    ref.read(transferSessionProvider.notifier).reset();
    if (fromPlayer) {
      // 确认取消后直接回到播放器，恢复原来的视频与时间点。
      context.pop(true);
    } else {
      context.pop();
    }
  }
}
