import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/ui_kit.dart';

/// 网络模块：直播 / 视频两栏的界面骨架。
///
/// V1.0 只提供界面与演示数据，实际的地址解析、拉流与播放后续版本实现。
class NetworkPage extends StatefulWidget {
  const NetworkPage({super.key});

  @override
  State<NetworkPage> createState() => _NetworkPageState();
}

class _NetworkSource {
  const _NetworkSource({
    required this.name,
    required this.kind,
    required this.format,
    required this.icon,
  });

  final String name;
  final String kind;
  final String format;
  final IconData icon;
}

class _NetworkPageState extends State<NetworkPage> {
  int _tab = 0;

  final List<_NetworkSource> _liveSources = <_NetworkSource>[
    const _NetworkSource(
      name: 'CCTV-1',
      kind: '直播',
      format: 'm3u8',
      icon: Icons.live_tv_rounded,
    ),
    const _NetworkSource(
      name: '节目直播示例',
      kind: '直播',
      format: 'http3',
      icon: Icons.folder_rounded,
    ),
  ];

  final List<_NetworkSource> _videoSources = <_NetworkSource>[
    const _NetworkSource(
      name: 'Flutter 开发教程',
      kind: '视频',
      format: 'mp4',
      icon: Icons.play_circle_fill_rounded,
    ),
  ];

  List<_NetworkSource> get _sources => _tab == 0 ? _liveSources : _videoSources;

  bool get _isLive => _tab == 0;

  void _notImplemented(String action) {
    showToast(context, '$action功能后续开放');
  }

  void _showMore() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.add_link_rounded),
                title: Text(_isLive ? '添加直播源' : '添加视频链接'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _notImplemented('添加');
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: Text(_isLive ? '清空直播源' : '清空网络视频'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  setState(() => _sources.clear());
                  showToast(context, '列表已清空（仅界面演示）');
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        children: <Widget>[
          PageHeader(
            title: '网络',
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            actions: <Widget>[
              IconButton(
                tooltip: '添加链接',
                onPressed: () => _notImplemented('添加'),
                icon: Icon(
                  Icons.add_rounded,
                  size: 25,
                  color: context.textPrimary,
                ),
              ),
              IconButton(
                tooltip: '更多',
                onPressed: _showMore,
                icon: Icon(
                  Icons.more_vert_rounded,
                  size: 22,
                  color: context.textPrimary,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildSegment(context),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
              children: <Widget>[
                if (_sources.isNotEmpty) ...<Widget>[
                  SectionHeader(
                    title: _isLive
                        ? '我的直播源（${_sources.length}）'
                        : '我的网络视频（${_sources.length}）',
                  ),
                  AppCard(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Column(
                      children: <Widget>[
                        for (int i = 0; i < _sources.length; i++) ...<Widget>[
                          _SourceTile(
                            source: _sources[i],
                            onTap: () => _notImplemented('播放'),
                          ),
                          if (i != _sources.length - 1)
                            Divider(
                              height: 1,
                              indent: 62,
                              color: context.dividerColor,
                            ),
                        ],
                      ],
                    ),
                  ),
                ],
                if (_sources.isEmpty) ...<Widget>[
                  const SizedBox(height: 56),
                  _buildEmptyState(context),
                ] else ...<Widget>[
                  const SizedBox(height: 28),
                  Center(
                    child: _AddLinkButton(onTap: () => _notImplemented('添加')),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSegment(BuildContext context) {
    return Container(
      height: 42,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: context.isDark
            ? Colors.white.withValues(alpha: 0.06)
            : const Color(0xFFEFF1F8),
        borderRadius: BorderRadius.circular(21),
      ),
      child: Row(
        children: <Widget>[
          _buildSegmentItem(context, '直播', 0),
          _buildSegmentItem(context, '视频', 1),
        ],
      ),
    );
  }

  Widget _buildSegmentItem(BuildContext context, String label, int index) {
    final bool selected = _tab == index;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _tab = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(17),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? Colors.white : context.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Column(
      children: <Widget>[
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            color: context.isDark
                ? Colors.white.withValues(alpha: 0.05)
                : const Color(0xFFF0F1F6),
            borderRadius: BorderRadius.circular(26),
          ),
          child: Icon(
            _isLive
                ? Icons.podcasts_rounded
                : Icons.play_circle_outline_rounded,
            size: 44,
            color: context.textSecondary,
          ),
        ),
        const SizedBox(height: 22),
        Text(
          _isLive ? '暂无网络源' : '暂无网络视频',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: context.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _isLive ? '点击右上角 + 添加观看' : '点击右上角 + 添加视频链接',
          style: TextStyle(fontSize: 12, color: context.textSecondary),
        ),
        const SizedBox(height: 22),
        _AddLinkButton(onTap: () => _notImplemented('添加')),
      ],
    );
  }
}

/// 源列表的一行：图标 + 名称 + 「直播 · m3u8」 + 箭头。
class _SourceTile extends StatelessWidget {
  const _SourceTile({required this.source, required this.onTap});

  final _NetworkSource source;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
        child: Row(
          children: <Widget>[
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(source.icon, size: 21, color: AppColors.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    source.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: context.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${source.kind} · ${source.format}',
                    style: TextStyle(
                      fontSize: 11,
                      color: context.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: context.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

/// 细边描边的「+ 添加链接」按钮。
class _AddLinkButton extends StatelessWidget {
  const _AddLinkButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.add_rounded, size: 18),
      label: const Text('添加链接'),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        side: BorderSide(color: AppColors.primary.withValues(alpha: 0.35)),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
