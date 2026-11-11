// -------------------------------------------------------------------------
// 功能：视频卡片组件
//
// 主要内容：
// - 缩略图与占位图
// - 列表样式 MediaListTile、网格样式 MediaGridTile
// - 多选勾选标记
// -------------------------------------------------------------------------

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/ui_kit.dart';
import '../../domain/models.dart';

// ===== 缩略图 =====
/// 视频封面：磁盘缓存 + 懒加载 + 占位图。
class MediaThumbnail extends ConsumerStatefulWidget {
  const MediaThumbnail({
    super.key,
    required this.item,
    this.width = 104,
    this.height = 60,
    this.radius = 10,
    this.showDuration = true,
    this.showProgress = false,
    this.progress,
  });

  final MediaItem item;
  final double width;
  final double height;
  final double radius;
  final bool showDuration;
  final bool showProgress;
  final double? progress;

  @override
  ConsumerState<MediaThumbnail> createState() => _MediaThumbnailState();
}

class _MediaThumbnailState extends ConsumerState<MediaThumbnail> {
  Future<File?>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant MediaThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id) {
      _load();
    }
  }

  void _load() {
    _future = ref.read(thumbnailServiceProvider).thumbnailOf(widget.item);
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            FutureBuilder<File?>(
              future: _future,
              builder: (BuildContext context, AsyncSnapshot<File?> snapshot) {
                final File? file = snapshot.data;
                if (file == null) {
                  return _Placeholder(title: widget.item.displayName);
                }
                return Image.file(
                  file,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) =>
                      _Placeholder(title: widget.item.displayName),
                );
              },
            ),
            if (widget.showDuration && widget.item.durationMs > 0)
              Positioned(
                right: 5,
                bottom: 5,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1.5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xB3000000),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    formatDuration(widget.item.durationMs),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            if (widget.showProgress && (widget.progress ?? 0) > 0)
              Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  height: 3,
                  color: Colors.black.withValues(alpha: 0.25),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: (widget.progress ?? 0).clamp(0.0, 1.0),
                    child: Container(color: AppColors.primary),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final int seed = title.hashCode.abs();
    final List<Color> palette = <Color>[
      const Color(0xFF8FA2FF),
      const Color(0xFF6FD0E8),
      const Color(0xFF9E8CF5),
      const Color(0xFF7BA7F0),
      const Color(0xFF8ED0B8),
    ];
    final Color base = palette[seed % palette.length];
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            base.withValues(alpha: 0.85),
            base.withValues(alpha: 0.45),
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.play_arrow_rounded,
          size: 24,
          color: Colors.white.withValues(alpha: 0.9),
        ),
      ),
    );
  }
}

// ===== 列表样式 =====
/// 列表模式的视频行。
class MediaListTile extends StatelessWidget {
  const MediaListTile({
    super.key,
    required this.item,
    required this.onTap,
    required this.onMore,
    this.onLongPress,
    this.progress,
    this.selectionMode = false,
    this.selected = false,
  });

  final MediaItem item;
  final VoidCallback onTap;
  final VoidCallback onMore;
  final VoidCallback? onLongPress;
  final PlaybackProgress? progress;
  final bool selectionMode;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? AppColors.primary.withValues(alpha: 0.07)
          : context.cardColor,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              if (selectionMode) ...<Widget>[
                _SelectionMark(selected: selected),
                const SizedBox(width: 8),
              ],
              MediaThumbnail(item: item, width: 104, height: 60),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      item.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: item.isAvailable
                            ? context.textPrimary
                            : context.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      <String>[
                        formatResolution(item.width, item.height),
                        formatBytes(item.fileSize),
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: context.textSecondary,
                      ),
                    ),
                    if (progress != null) ...<Widget>[
                      const SizedBox(height: 7),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: LinearProgressIndicator(
                                value: progress!.fraction,
                                minHeight: 3,
                                backgroundColor: context.dividerColor,
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                  AppColors.primary,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            progress!.completed
                                ? '已看完'
                                : formatWatchPercent(progress!.fraction),
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              AppIconButton(
                icon: Icons.more_vert_rounded,
                iconSize: 19,
                size: 36,
                color: context.textSecondary,
                onPressed: onMore,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ===== 网格样式 =====
/// 网格模式的视频卡片。
class MediaGridTile extends StatelessWidget {
  const MediaGridTile({
    super.key,
    required this.item,
    required this.onTap,
    required this.onMore,
    this.onLongPress,
    this.progress,
    this.selectionMode = false,
    this.selected = false,
  });

  final MediaItem item;
  final VoidCallback onTap;
  final VoidCallback onMore;
  final VoidCallback? onLongPress;
  final PlaybackProgress? progress;
  final bool selectionMode;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: GestureDetector(
                    onTap: onTap,
                    child: LayoutBuilder(
                      builder:
                          (BuildContext context, BoxConstraints constraints) {
                            return MediaThumbnail(
                              item: item,
                              width: constraints.maxWidth,
                              height: constraints.maxHeight,
                              radius: 14,
                              showProgress: true,
                              progress: progress?.fraction,
                            );
                          },
                    ),
                  ),
                ),
                if (selectionMode)
                  Positioned(
                    left: 8,
                    top: 8,
                    child: _SelectionMark(selected: selected, floating: true),
                  )
                else
                  Positioned(
                    right: 2,
                    top: 2,
                    child: Material(
                      color: Colors.black.withValues(alpha: 0.28),
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: onMore,
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(
                            Icons.more_horiz_rounded,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 7),
          Text(
            item.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: context.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

// ===== 多选标记 =====
class _SelectionMark extends StatelessWidget {
  const _SelectionMark({required this.selected, this.floating = false});

  final bool selected;
  final bool floating;

  @override
  Widget build(BuildContext context) {
    final Widget mark = Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: selected ? AppColors.primary : Colors.transparent,
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? AppColors.primary : context.textSecondary,
          width: 1.6,
        ),
      ),
      child: selected
          ? const Icon(Icons.check_rounded, size: 15, color: Colors.white)
          : null,
    );
    if (!floating) return mark;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: const BoxDecoration(
        color: Color(0x66000000),
        shape: BoxShape.circle,
      ),
      child: mark,
    );
  }
}
