// -------------------------------------------------------------------------
// 功能：接收文件（P03）
//
// 检查网络 → 启动 TLS 监听 → 展示二维码等待扫码；到期自动换码。
// -------------------------------------------------------------------------

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

import '../../../core/theme/app_theme.dart';
import '../application/transfer_session_controller.dart';
import '../domain/transfer_session.dart';

class TransferReceivePage extends ConsumerStatefulWidget {
  const TransferReceivePage({super.key});

  @override
  ConsumerState<TransferReceivePage> createState() =>
      _TransferReceivePageState();
}

class _TransferReceivePageState extends ConsumerState<TransferReceivePage> {
  Timer? _ticker;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(transferSessionProvider.notifier).prepareReceive();
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      final TransferSessionState session = ref.read(transferSessionProvider);
      final DateTime? expires = session.expiresAt;
      if (session.phase == TransferPhase.waiting &&
          expires != null &&
          _now.isAfter(expires)) {
        // 等待超时自动换一张新码。
        ref.read(transferSessionProvider.notifier).prepareReceive();
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    final TransferSessionState session = ref.read(transferSessionProvider);
    if (session.phase == TransferPhase.waiting ||
        session.phase == TransferPhase.checking) {
      ref.read(transferSessionProvider.notifier).stopReceive();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<TransferSessionState>(transferSessionProvider, (
      TransferSessionState? previous,
      TransferSessionState next,
    ) {
      if (next.phase == TransferPhase.transferring &&
          previous?.phase != TransferPhase.transferring &&
          mounted) {
        context.push('/transfer/task');
      }
    });

    final TransferSessionState session = ref.watch(transferSessionProvider);

    return Scaffold(
      backgroundColor: context.appBackground,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 16, 2),
              child: Row(
                children: <Widget>[
                  IconButton(
                    onPressed: () => context.pop(),
                    icon: Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 18,
                      color: context.textPrimary,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '接收文件',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: context.textPrimary,
                      ),
                    ),
                  ),
                  Text(
                    session.phase.label,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: context.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: _buildBody(session)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(TransferSessionState session) {
    if (session.phase == TransferPhase.failed) {
      return _StateView(
        icon: Icons.wifi_off_rounded,
        title: '无法准备接收',
        message: session.error ?? '未知错误',
        actionLabel: '重试',
        onAction: () =>
            ref.read(transferSessionProvider.notifier).prepareReceive(),
      );
    }
    if (session.invite == null ||
        session.phase == TransferPhase.checking ||
        session.phase == TransferPhase.idle) {
      return const _StateView(
        icon: Icons.wifi_find_rounded,
        title: '正在检查网络…',
        message: '确认已连接同一 Wi-Fi 或热点，随后会显示接收二维码。',
        busy: true,
      );
    }

    final DateTime? expires = session.expiresAt;
    final int remain = expires == null
        ? 0
        : expires.difference(_now).inSeconds.clamp(0, 999);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(Icons.wifi_rounded, size: 15, color: context.textSecondary),
              const SizedBox(width: 6),
              Text(
                '${session.ip}:${session.port} · 有效期 ${remain}s',
                style: TextStyle(fontSize: 11.5, color: context.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: SizedBox(
              width: 232,
              height: 232,
              child: PrettyQrView.data(
                data: session.invite!,
                errorCorrectLevel: QrErrorCorrectLevel.M,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '让对方在「发送文件」里扫描这张码',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: context.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '文件不经过服务器，只在两台设备之间直传。\n'
            '等待期间离开本页会立即关闭接收。',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11.5,
              height: 1.7,
              color: context.textSecondary,
            ),
          ),
          const SizedBox(height: 18),
          OutlinedButton(
            onPressed: () => context.pop(),
            child: const Text('取消等待'),
          ),
        ],
      ),
    );
  }
}

class _StateView extends StatelessWidget {
  const _StateView({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.busy = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (busy)
              const SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              )
            else
              Icon(icon, size: 34, color: AppColors.primary),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: context.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 1.7,
                color: context.textSecondary,
              ),
            ),
            if (actionLabel != null) ...<Widget>[
              const SizedBox(height: 16),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
