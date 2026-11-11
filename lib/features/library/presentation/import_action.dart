// -------------------------------------------------------------------------
// 功能：导入动作
//
// 主要内容：
// - 触发文件选择导入
// - 导入进度弹窗与结果提示
// -------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/ui_kit.dart';
import '../application/library_controller.dart';

/// 导入视频：展示复制进度，结束后给出结果提示。
Future<void> importVideosWithFeedback(
  BuildContext context,
  WidgetRef ref,
) async {
  final int? count = await showDialog<int>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext dialogContext) {
      return _ImportProgressDialog(
        onImport: (void Function(double progress, String message) onProgress) {
          return ref
              .read(libraryControllerProvider.notifier)
              .importVideos(onProgress: onProgress);
        },
      );
    },
  );

  if (!context.mounted || count == null) return;
  if (count > 0) {
    showToast(context, '已导入 $count 个视频');
  } else if (count == 0) {
    showToast(context, '未选择新的视频');
  } else {
    showToast(context, '导入失败，请检查文件是否可访问');
  }
}

class _ImportProgressDialog extends StatefulWidget {
  const _ImportProgressDialog({required this.onImport});

  final Future<int> Function(void Function(double, String)) onImport;

  @override
  State<_ImportProgressDialog> createState() => _ImportProgressDialogState();
}

class _ImportProgressDialogState extends State<_ImportProgressDialog> {
  double _progress = 0;
  String _message = '正在打开文件选择器…';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    final int result = await widget.onImport((double progress, String message) {
      if (!mounted) return;
      setState(() {
        _progress = progress;
        _message = message;
      });
    });
    if (!mounted) return;
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              '正在导入视频',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: _progress == 0 ? null : _progress,
                minHeight: 4,
              ),
            ),
            const SizedBox(height: 10),
            Text(_message, style: const TextStyle(fontSize: 11.5)),
          ],
        ),
      ),
    );
  }
}
