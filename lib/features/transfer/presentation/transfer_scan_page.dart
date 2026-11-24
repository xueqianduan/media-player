// -------------------------------------------------------------------------
// 功能：扫码发送（P04）
//
// 扫接收方二维码 → 校验格式 → 建立 TLS → 自动进入任务页。
// 相机不可用时支持手动粘贴接收码。
// -------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../application/transfer_session_controller.dart';
import '../domain/transfer_models.dart';
import '../domain/transfer_session.dart';

class TransferScanPage extends ConsumerStatefulWidget {
  const TransferScanPage({super.key, required this.request});

  final TransferSendRequest request;

  @override
  ConsumerState<TransferScanPage> createState() => _TransferScanPageState();
}

class _TransferScanPageState extends ConsumerState<TransferScanPage> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const <BarcodeFormat>[BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  final TextEditingController _manual = TextEditingController();
  bool _handled = false;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    _manual.dispose();
    super.dispose();
  }

  Future<void> _accept(String raw) async {
    if (_handled || _sending) return;
    final String text = raw.trim();
    if (!text.startsWith('LUMI1|')) {
      setState(() => _error = '这不是 LumiPlayer 的接收码');
      return;
    }
    setState(() {
      _handled = true;
      _sending = true;
      _error = null;
    });
    await _controller.stop();
    final String? taskId = await ref
        .read(transferSessionProvider.notifier)
        .startSend(invite: text, files: widget.request.files);
    if (!mounted) return;
    if (taskId == null) {
      final TransferSessionState session = ref.read(transferSessionProvider);
      setState(() {
        _sending = false;
        _handled = false;
        _error = session.error ?? '连接失败，请重试';
      });
      await _controller.start();
      return;
    }
    final bool? backToPlayer = await context.push<bool>(
      '/transfer/task',
      extra: widget.request.fromPlayer,
    );
    if (!mounted) return;
    if (backToPlayer == true) {
      context.pop(true);
      return;
    }
    // 从任务页返回（失败、取消或主动退出）：恢复相机，允许重新扫码。
    setState(() {
      _handled = false;
      _sending = false;
      _error = null;
    });
    try {
      await _controller.start();
    } on Object {
      // 相机不可用时仍保留手动粘贴入口。
    }
  }

  @override
  Widget build(BuildContext context) {
    final TransferSessionState session = ref.watch(transferSessionProvider);

    ref.listen<TransferSessionState>(transferSessionProvider, (
      TransferSessionState? previous,
      TransferSessionState next,
    ) {
      if (next.phase == TransferPhase.failed &&
          next.error != null &&
          previous?.error != next.error &&
          mounted) {
        setState(() {
          _error = next.error;
          _sending = false;
          _handled = false;
        });
      }
    });

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: <Widget>[
            MobileScanner(
              controller: _controller,
              onDetect: (BarcodeCapture capture) {
                for (final Barcode code in capture.barcodes) {
                  final String? value = code.rawValue;
                  if (value != null && value.startsWith('LUMI1|')) {
                    _accept(value);
                    break;
                  }
                }
              },
              errorBuilder:
                  (BuildContext context, MobileScannerException error) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          '相机不可用：${error.errorCode.name}\n可在下方手动粘贴接收码。',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    );
                  },
            ),
            Positioned(
              top: 6,
              left: 4,
              child: IconButton(
                onPressed: () => context.pop(),
                icon: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  size: 18,
                  color: Colors.white,
                ),
              ),
            ),
            Positioned(
              left: 20,
              right: 20,
              top: 56,
              child: Text(
                '扫描接收方的二维码',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 18,
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                  color: const Color(0xE60B0D14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      '共 ${widget.request.files.length} 个文件，连接后自动开始发送',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: TextField(
                            controller: _manual,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                            ),
                            decoration: const InputDecoration(
                              isDense: true,
                              filled: false,
                              border: InputBorder.none,
                              hintText: '相机不可用时，粘贴 LUMI1|… 接收码',
                              hintStyle: TextStyle(
                                color: Colors.white30,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        FilledButton(
                          onPressed: _sending
                              ? null
                              : () => _accept(_manual.text),
                          child: Text(_sending ? '连接中' : '连接'),
                        ),
                      ],
                    ),
                    if (_sending) ...<Widget>[
                      const SizedBox(height: 10),
                      LinearProgressIndicator(
                        value: session.progress,
                        minHeight: 3,
                      ),
                    ],
                    if (_error != null) ...<Widget>[
                      const SizedBox(height: 8),
                      Text(
                        _error!,
                        style: const TextStyle(
                          color: Color(0xFFE08A8A),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (_sending)
              const Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white70,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
