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
///
/// [fromPlayer] 为 true 时表示从播放控制台发起，发送流程结束后要回到播放器。
Future<void> openTransferShare(
  BuildContext context,
  Iterable<MediaItem> items, {
  bool fromPlayer = false,
}) async {
  final List<TransferFile> files = <TransferFile>[
    for (final MediaItem item in items) transferFileOf(item),
  ];
  if (files.isEmpty) return;
  await context.push<void>(
    '/transfer/select',
    extra: TransferSendRequest(files: files, fromPlayer: fromPlayer),
  );
}

/// 把媒体库记录映射成待发送文件。
///
/// 相册资源用 `sourceId`（即 `AssetEntity.id`）作为稳定标识，和相册浏览页的
/// 去重规则保持一致；导入视频用媒体记录 id。两者都保留 `sourceLocator`，
/// 由确认页负责解析成可读路径并补齐真实大小。
TransferFile transferFileOf(MediaItem item) {
  final bool fromGallery = item.sourceType == MediaSourceType.photoAsset;
  return TransferFile(
    id: fromGallery ? item.sourceId : item.id,
    path: item.sourceLocator,
    name: item.displayName,
    size: item.fileSize,
    type: TransferFileType.video,
    source: fromGallery ? '相册' : '本机文件',
  );
}
