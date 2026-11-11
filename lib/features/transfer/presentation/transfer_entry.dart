// -------------------------------------------------------------------------
// 功能：传输模块入口
//
// 主要内容：
// - 视频分享 → 统一发送流程（自动带入已选视频）
// - 路由参数的类型安全转换
// -------------------------------------------------------------------------

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../library/domain/models.dart';
import '../domain/transfer_models.dart';

/// 视频分享入口：把视频转成待发送文件并进入文件选择页。
void openTransferShare(BuildContext context, Iterable<MediaItem> items) {
  final List<TransferFile> files = <TransferFile>[
    for (final MediaItem item in items)
      TransferFile(
        id: item.id,
        path: item.sourceLocator,
        name: item.displayName,
        size: item.fileSize,
        type: TransferFileType.video,
        source: item.originalName,
      ),
  ];
  if (files.isEmpty) return;
  context.push('/transfer/select', extra: files);
}
