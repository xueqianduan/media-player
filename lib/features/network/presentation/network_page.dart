// -------------------------------------------------------------------------
// 功能：网络页
//
// 主要内容：
// - 直播/视频两段切换
// - 双路观赛来源卡与开始观看
// - 收藏卡列表、添加链接弹窗
// -------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/ui_kit.dart';
import '../application/network_controller.dart';
import '../data/bili_live_api.dart';
import '../domain/live_models.dart';
import 'live_player_page.dart';
import 'live_search_page.dart';

/// 网络模块：B 站直播搜索、双路观赛、收藏与网络视频直链。
class NetworkPage extends ConsumerStatefulWidget {
  const NetworkPage({super.key});

  @override
  ConsumerState<NetworkPage> createState() => _NetworkPageState();
}

class _NetworkPageState extends ConsumerState<NetworkPage> {
  int _tab = 0;

  LiveRoom? _picture;
  LiveRoom? _voice;
  bool _managing = false;

  @override
  // ===== 生命周期 =====
  void initState() {
    super.initState();
    // 双路选择默认取上次保存的组合。
    final LivePreset preset = ref.read(networkControllerProvider).preset;
    _picture = preset.picture;
    _voice = preset.voice;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(networkControllerProvider.notifier).refreshFavoriteStatus();
      }
    });
  }

  bool get _isLive => _tab == 0;

  // ===== 选择来源与开始观看 =====
  Future<void> _pickSource(LiveSourceSlot slot) async {
    final LiveSearchResult? result = await context.push<LiveSearchResult>(
      '/network/search',
      extra: slot,
    );
    if (result == null || !mounted) return;
    setState(() {
      if (result.slot == LiveSourceSlot.picture) {
        _picture = result.room;
      } else {
        _voice = result.room;
      }
    });
  }

  void _startWatch({LiveRoom? picture, LiveRoom? voice}) {
    final LiveRoom? source = picture ?? _picture;
    if (source == null) {
      showToast(context, '先选择画面来源');
      return;
    }
    context.push(
      '/network/live',
      extra: LivePlayArgs(picture: source, voice: voice ?? _voice),
    );
  }

  void _savePreset() {
    if (_picture == null) {
      showToast(context, '先选择画面来源再保存');
      return;
    }
    ref
        .read(networkControllerProvider.notifier)
        .savePreset(LivePreset(picture: _picture, voice: _voice));
    showToast(context, '已保存组合');
  }

  // ------------------------------------------------------------------ 添加链接

  // ===== 添加链接与收藏菜单 =====
  Future<void> _showAddLinkDialog() async {
    final bool isLive = _isLive;
    final String? input = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => _AddLinkDialog(isLive: isLive),
    );
    if (input == null || input.isEmpty || !mounted) return;

    if (isLive) {
      final int? roomId = BiliLiveApi.parseRoomInput(input);
      if (roomId == null) {
        showToast(context, '请粘贴直播间链接或房间号');
        return;
      }
      showToast(context, '正在识别直播间…');
      try {
        final LiveRoom room = await ref
            .read(biliLiveApiProvider)
            .roomDetail(roomId);
        if (!mounted) return;
        setState(() => _picture = room);
        showToast(context, '已设为画面来源：${room.name}');
      } on Object catch (error) {
        if (mounted) showToast(context, '$error');
      }
      return;
    }

    if (!input.startsWith('http://') && !input.startsWith('https://')) {
      showToast(context, '请输入以 http(s) 开头的直链');
      return;
    }
    final String name = Uri.tryParse(input)?.pathSegments.isNotEmpty == true
        ? Uri.parse(input).pathSegments.last
        : '网络视频';
    ref
        .read(networkControllerProvider.notifier)
        .addVideo(name: name.isEmpty ? '网络视频' : name, url: input);
    showToast(context, '已添加网络视频');
  }

  // ------------------------------------------------------------------ 收藏操作

  Future<void> _showFavoriteMenu(LiveFavorite favorite) async {
    final LiveRoom room = favorite.room;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF16181F),
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  room.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                _MenuAction(
                  icon: Icons.play_arrow_rounded,
                  label: '直接观看',
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _startWatch(picture: room);
                  },
                ),
                _MenuAction(
                  icon: Icons.ondemand_video_rounded,
                  label: '设为画面来源',
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    setState(() => _picture = room);
                    showToast(context, '已设为画面来源');
                  },
                ),
                _MenuAction(
                  icon: Icons.graphic_eq_rounded,
                  label: '设为声音来源',
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    setState(() => _voice = room);
                    showToast(context, '已设为声音来源');
                  },
                ),
                _MenuAction(
                  icon: Icons.star_border_rounded,
                  label: '取消收藏',
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    ref
                        .read(networkControllerProvider.notifier)
                        .removeFavorite(room.roomId);
                    showToast(context, '已取消收藏');
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // -------------------------------------------------------------------- build

  @override
  // ===== 页面骨架 =====
  Widget build(BuildContext context) {
    final NetworkState network = ref.watch(networkControllerProvider);

    return Scaffold(
      backgroundColor: context.appBackground,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            PageHeader(
              title: '网络',
              padding: const EdgeInsets.fromLTRB(16, 6, 8, 8),
              actions: <Widget>[
                TextButton.icon(
                  onPressed: _showAddLinkDialog,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 19),
                  label: const Text('添加链接', style: TextStyle(fontSize: 13.5)),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildSearchBox(context),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildSegment(context),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                children: _isLive
                    ? _buildLiveTab(context, network)
                    : _buildVideoTab(context, network),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===== 顶部区域：搜索框与分段切换 =====
  Widget _buildSearchBox(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (_isLive) {
          _pickSource(LiveSourceSlot.picture);
        } else {
          _showAddLinkDialog();
        }
      },
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: context.cardColor,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: context.dividerColor.withValues(alpha: 0.6),
          ),
        ),
        child: Row(
          children: <Widget>[
            Icon(Icons.search_rounded, size: 19, color: context.textSecondary),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                _isLive ? '搜索直播间、主播或粘贴链接' : '粘贴 mp4 / m3u8 直链',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, color: context.textSecondary),
              ),
            ),
          ],
        ),
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
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          // 滑块宽度固定为一半，切换时整块平移过去。
          final double pillWidth = constraints.maxWidth / 2;
          return Stack(
            children: <Widget>[
              AnimatedPositioned(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                left: _tab == 0 ? 0 : pillWidth,
                top: 0,
                width: pillWidth,
                height: constraints.maxHeight,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(17),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.26),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: <Widget>[
                  _buildSegmentLabel(context, '直播', 0),
                  _buildSegmentLabel(context, '视频', 1),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSegmentLabel(BuildContext context, String label, int index) {
    final bool selected = _tab == index;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() {
          _tab = index;
          _managing = false;
        }),
        child: Center(
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? Colors.white : context.textSecondary,
            ),
            child: Text(label),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ 直播 tab

  // ===== 直播 tab =====
  List<Widget> _buildLiveTab(BuildContext context, NetworkState network) {
    return <Widget>[
      _buildDualCard(context),
      SectionHeader(
        title: '我的收藏  ${network.favorites.length}',
        actionLabel: network.favorites.isEmpty
            ? null
            : (_managing ? '完成' : '管理'),
        onAction: network.favorites.isEmpty
            ? null
            : () => setState(() => _managing = !_managing),
        padding: const EdgeInsets.fromLTRB(2, 22, 2, 10),
      ),
      if (network.favorites.isEmpty)
        _buildEmptyFavorites(context)
      else
        for (final LiveFavorite favorite in network.favorites)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _FavoriteCard(
              favorite: favorite,
              managing: _managing,
              onPlay: () => _startWatch(picture: favorite.room),
              onMore: () => _showFavoriteMenu(favorite),
              onDelete: () => ref
                  .read(networkControllerProvider.notifier)
                  .removeFavorite(favorite.room.roomId),
            ),
          ),
      const SizedBox(height: 14),
      Center(
        child: TextButton.icon(
          onPressed: () => _pickSource(LiveSourceSlot.picture),
          style: TextButton.styleFrom(foregroundColor: AppColors.primary),
          icon: const Icon(Icons.search_rounded, size: 18),
          label: const Text(
            '搜索更多直播',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ),
      ),
    ];
  }

  Widget _buildDualCard(BuildContext context) {
    final bool hasPicture = _picture != null;
    final bool voiceLive = _voice?.live ?? false;
    final String note = !hasPicture
        ? '先选择赛事画面，再挑一个你喜欢的解说。'
        : (_voice == null
              ? '还没有选择声音源，可以先听赛事原声。'
              : (voiceLive ? '两路都已开播，点下方按钮开始观看。' : '声音源未开播，可先听赛事原声。'));

    return AppCard(
      radius: 20,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.layers_rounded,
                  size: 19,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      '双路观赛',
                      style: TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w700,
                        color: context.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '赛事画面，搭配你喜欢的解说。',
                      style: TextStyle(
                        fontSize: 11,
                        color: context.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: _savePreset,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: BorderSide(
                    color: AppColors.primary.withValues(alpha: 0.30),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  minimumSize: const Size(0, 30),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                icon: const Icon(Icons.bookmark_border_rounded, size: 14),
                label: const Text('保存组合', style: TextStyle(fontSize: 11.5)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Expanded(
                child: _SourceTile(
                  label: '画面来源',
                  icon: Icons.desktop_windows_rounded,
                  room: _picture,
                  onTap: () => _pickSource(LiveSourceSlot.picture),
                ),
              ),
              SizedBox(
                width: 26,
                child: Center(
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.10),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.link_rounded,
                      size: 13,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: _SourceTile(
                  label: '声音来源',
                  icon: Icons.headphones_rounded,
                  room: _voice,
                  hint: '可选',
                  onTap: () => _pickSource(LiveSourceSlot.voice),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Icon(
                Icons.info_outline_rounded,
                size: 13,
                color: context.textSecondary,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  note,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1.4,
                    color: context.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: FilledButton.icon(
              onPressed: hasPicture
                  ? () => _startWatch()
                  : () => _pickSource(LiveSourceSlot.picture),
              style: FilledButton.styleFrom(
                backgroundColor: hasPicture
                    ? AppColors.primary
                    : AppColors.primary.withValues(alpha: 0.35),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
                padding: EdgeInsets.zero,
              ),
              icon: Icon(
                hasPicture ? Icons.play_arrow_rounded : Icons.add_link_rounded,
                size: 20,
              ),
              label: Text(
                !hasPicture ? '选择画面来源' : (voiceLive ? '开始观看' : '先看赛事原声'),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 2),
          Divider(height: 1, color: context.dividerColor),
          InkWell(
            onTap: () => showToast(context, '开始观看后，可在播放页调整两路同步'),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 11),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.tune_rounded,
                    size: 16,
                    color: context.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '同步调节',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: context.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: context.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyFavorites(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.star_border_rounded,
            size: 22,
            color: context.textSecondary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '还没有收藏的直播间，搜索后点「加入收藏」即可保存在这里。',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.5,
                color: context.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ 视频 tab

  // ===== 视频 tab =====
  List<Widget> _buildVideoTab(BuildContext context, NetworkState network) {
    return <Widget>[
      SectionHeader(
        title: '我的网络视频  ${network.videos.length}',
        actionLabel: network.videos.isEmpty ? null : (_managing ? '完成' : '管理'),
        onAction: network.videos.isEmpty
            ? null
            : () => setState(() => _managing = !_managing),
        padding: const EdgeInsets.fromLTRB(2, 6, 2, 10),
      ),
      if (network.videos.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 40),
          child: Column(
            children: <Widget>[
              EmptyState(
                icon: Icons.play_circle_outline_rounded,
                title: '还没有网络视频',
                message: '点击右上角「添加链接」粘贴 mp4 / m3u8 直链，保存后即可离线访问列表。',
              ),
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: _showAddLinkDialog,
                icon: const Icon(Icons.add_link_rounded, size: 18),
                label: const Text('添加链接'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: BorderSide(
                    color: AppColors.primary.withValues(alpha: 0.35),
                  ),
                ),
              ),
            ],
          ),
        )
      else
        for (final NetworkVideo video in network.videos)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: AppCard(
              padding: const EdgeInsets.all(10),
              onTap: _managing
                  ? null
                  : () => context.push('/network/video', extra: video),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.play_circle_fill_rounded,
                      size: 24,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          video.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: context.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${video.format.toUpperCase()} · 直链播放',
                          style: TextStyle(
                            fontSize: 11,
                            color: context.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_managing)
                    IconButton(
                      onPressed: () => ref
                          .read(networkControllerProvider.notifier)
                          .removeVideo(video.id),
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        size: 19,
                        color: Color(0xFFE05252),
                      ),
                    )
                  else
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: context.textSecondary,
                    ),
                ],
              ),
            ),
          ),
    ];
  }
}

// ===== 对话框与卡片组件 =====
/// 添加直播链接 / 视频直链的输入弹窗。
class _AddLinkDialog extends StatefulWidget {
  const _AddLinkDialog({required this.isLive});

  final bool isLive;

  @override
  State<_AddLinkDialog> createState() => _AddLinkDialogState();
}

class _AddLinkDialogState extends State<_AddLinkDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.isLive ? '添加直播链接' : '添加视频链接',
        style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700),
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLines: 3,
        minLines: 1,
        decoration: InputDecoration(
          hintText: widget.isLive
              ? '粘贴直播间链接或房间号，例如\nhttps://live.bilibili.com/6'
              : '粘贴 mp4 / m3u8 直链',
        ),
        onSubmitted: (String value) => Navigator.of(context).pop(value.trim()),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text(
            '确定',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

/// 双路观赛里的来源卡：标签 + 名称 + 副标题 + 更换。
class _SourceTile extends StatelessWidget {
  const _SourceTile({
    required this.label,
    required this.icon,
    required this.room,
    required this.onTap,
    this.hint,
  });

  final String label;
  final IconData icon;
  final LiveRoom? room;
  final String? hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final LiveRoom? value = room;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: BoxDecoration(
        color: context.isDark
            ? Colors.white.withValues(alpha: 0.04)
            : const Color(0xFFF7F8FD),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: 12, color: context.textSecondary),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(fontSize: 10.5, color: context.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value?.name ?? '未选择',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: value == null
                  ? context.textSecondary
                  : context.textPrimary,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value == null
                ? (hint ?? '点击选择')
                : 'B站 · ${value.isUp ? '主播' : '房间 ${value.roomId}'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5,
              color: context.textSecondary.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                '更换',
                style: TextStyle(
                  fontSize: 10.5,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 收藏卡片：直播间显示封面 + 播放入口，主播显示头像图标 + 更多菜单。
class _FavoriteCard extends StatelessWidget {
  const _FavoriteCard({
    required this.favorite,
    required this.managing,
    required this.onPlay,
    required this.onMore,
    required this.onDelete,
  });

  final LiveFavorite favorite;
  final bool managing;
  final VoidCallback onPlay;
  final VoidCallback onMore;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final LiveRoom room = favorite.room;
    final bool up = room.isUp;

    return AppCard(
      padding: const EdgeInsets.all(10),
      onTap: managing ? null : onMore,
      child: Row(
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: up ? 56 : 96,
              height: up ? 56 : 58,
              child: up
                  ? ColoredBox(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      child: const Icon(
                        Icons.headphones_rounded,
                        size: 26,
                        color: AppColors.primary,
                      ),
                    )
                  : _NetworkCover(url: room.coverUrl),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  room.name,
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
                  room.categoryLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: context.textSecondary,
                  ),
                ),
                const SizedBox(height: 5),
                Row(
                  children: <Widget>[
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: room.live
                            ? const Color(0xFF37C26A)
                            : context.textSecondary.withValues(alpha: 0.5),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      room.live ? '直播中' : '未开播',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: room.live
                            ? const Color(0xFF37C26A)
                            : context.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (managing)
            IconButton(
              onPressed: onDelete,
              icon: const Icon(
                Icons.remove_circle_outline_rounded,
                size: 21,
                color: Color(0xFFE05252),
              ),
            )
          else if (!up)
            GestureDetector(
              onTap: onPlay,
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.55),
                  ),
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  size: 19,
                  color: AppColors.primary,
                ),
              ),
            )
          else
            IconButton(
              onPressed: onMore,
              icon: Icon(
                Icons.more_horiz_rounded,
                size: 20,
                color: context.textSecondary,
              ),
            ),
        ],
      ),
    );
  }
}

/// 收藏封面：加载失败时回落到直播图标。
class _NetworkCover extends StatelessWidget {
  const _NetworkCover({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final String normalized = url.startsWith('//') ? 'https:$url' : url;
    if (normalized.isEmpty) return _fallback(context);
    return Image.network(
      normalized,
      fit: BoxFit.cover,
      headers: const <String, String>{'Referer': 'https://live.bilibili.com/'},
      errorBuilder: (_, _, _) => _fallback(context),
    );
  }

  Widget _fallback(BuildContext context) {
    return ColoredBox(
      color: context.isDark
          ? Colors.white.withValues(alpha: 0.06)
          : const Color(0xFFEFF1F8),
      child: Icon(
        Icons.live_tv_rounded,
        size: 24,
        color: context.textSecondary,
      ),
    );
  }
}

class _MenuAction extends StatelessWidget {
  const _MenuAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 19, color: Colors.white54),
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 13.5),
            ),
          ],
        ),
      ),
    );
  }
}
