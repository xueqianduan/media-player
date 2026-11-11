// -------------------------------------------------------------------------
// 功能：直播搜索页
//
// 主要内容：
// - 关键词搜索（防抖 + 竞态保护）
// - 房间号/链接直连
// - 结果卡片与来源选择面板
// -------------------------------------------------------------------------

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/ui_kit.dart';
import '../application/network_controller.dart';
import '../data/bili_live_api.dart';
import '../domain/live_models.dart';

/// 搜索结果要放到哪一路。
enum LiveSourceSlot { picture, voice }

/// 搜索页返回的选择结果。
class LiveSearchResult {
  const LiveSearchResult({required this.room, required this.slot});

  final LiveRoom room;
  final LiveSourceSlot slot;
}

/// 直播搜索：搜直播间 / 主播，也支持直接粘贴直播间链接或房间号。
class LiveSearchPage extends ConsumerStatefulWidget {
  const LiveSearchPage({super.key, required this.target});

  final LiveSourceSlot target;

  @override
  ConsumerState<LiveSearchPage> createState() => _LiveSearchPageState();
}

class _LiveSearchPageState extends ConsumerState<LiveSearchPage> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  Timer? _debounce;
  int _sequence = 0;

  String _query = '';
  List<LiveRoom> _results = <LiveRoom>[];
  bool _loading = false;
  String? _error;

  int? _directRoomId;
  bool _directLoading = false;

  @override
  // ===== 生命周期 =====
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ===== 输入与搜索：防抖 / 竞态保护 / 房间号直连 =====
  void _onChanged(String value) {
    final int? roomId = BiliLiveApi.parseRoomInput(value);
    setState(() {
      _query = value;
      _directRoomId = roomId;
    });
    _debounce?.cancel();
    if (roomId != null) {
      // 输入看起来是房间号/链接，等用户确认直接打开。
      setState(() {
        _results = <LiveRoom>[];
        _error = null;
        _loading = false;
      });
      return;
    }
    if (value.trim().length < 2) {
      setState(() {
        _results = <LiveRoom>[];
        _error = null;
        _loading = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 420), () {
      _search(value);
    });
  }

  Future<void> _search(String keyword) async {
    final String text = keyword.trim();
    if (text.length < 2) return;
    final int seq = ++_sequence;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final List<LiveRoom> rooms = await ref
          .read(biliLiveApiProvider)
          .search(text);
      if (!mounted || seq != _sequence) return;
      setState(() {
        _results = rooms;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted || seq != _sequence) return;
      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }

  Future<void> _openDirectRoom() async {
    final int? roomId = _directRoomId;
    if (roomId == null || _directLoading) return;
    setState(() => _directLoading = true);
    try {
      final LiveRoom room = await ref
          .read(biliLiveApiProvider)
          .roomDetail(roomId);
      if (!mounted) return;
      _select(room, widget.target);
    } on Object catch (error) {
      if (!mounted) return;
      showToast(context, '$error');
    } finally {
      if (mounted) setState(() => _directLoading = false);
    }
  }

  void _select(LiveRoom room, LiveSourceSlot slot) {
    Navigator.of(context).pop(LiveSearchResult(room: room, slot: slot));
  }

  // ===== 结果选择面板 =====
  Future<void> _showRoomSheet(LiveRoom room) async {
    final NetworkController controller = ref.read(
      networkControllerProvider.notifier,
    );
    final bool favorite = ref
        .read(networkControllerProvider)
        .isFavorite(room.roomId);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF16181F),
      builder: (BuildContext sheetContext) {
        final LiveSourceSlot primary = widget.target;
        final LiveSourceSlot secondary = primary == LiveSourceSlot.picture
            ? LiveSourceSlot.voice
            : LiveSourceSlot.picture;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
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
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${room.categoryLabel} · 房间 ${room.roomId}'
                  '${room.live ? ' · 直播中' : ' · 未开播'}',
                  style: const TextStyle(color: Colors.white38, fontSize: 11.5),
                ),
                const SizedBox(height: 14),
                _SheetAction(
                  icon: Icons.ondemand_video_rounded,
                  label: primary == LiveSourceSlot.picture
                      ? '设为画面来源'
                      : '设为声音来源',
                  highlighted: true,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _select(room, primary);
                  },
                ),
                _SheetAction(
                  icon: secondary == LiveSourceSlot.picture
                      ? Icons.ondemand_video_rounded
                      : Icons.graphic_eq_rounded,
                  label: secondary == LiveSourceSlot.picture
                      ? '设为画面来源'
                      : '设为声音来源',
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _select(room, secondary);
                  },
                ),
                _SheetAction(
                  icon: favorite
                      ? Icons.star_rounded
                      : Icons.star_border_rounded,
                  label: favorite ? '取消收藏' : '加入收藏',
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    final bool now = controller.toggleFavorite(room);
                    showToast(context, now ? '已加入收藏' : '已取消收藏');
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  // ===== 页面骨架 =====
  Widget build(BuildContext context) {
    final NetworkState network = ref.watch(networkControllerProvider);

    return Scaffold(
      backgroundColor: context.appBackground,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 8, 12, 10),
              child: Row(
                children: <Widget>[
                  IconButton(
                    onPressed: () =>
                        context.canPop() ? context.pop() : context.go('/'),
                    icon: Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 18,
                      color: context.textPrimary,
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      textInputAction: TextInputAction.search,
                      onChanged: _onChanged,
                      onSubmitted: (String value) {
                        final int? roomId = BiliLiveApi.parseRoomInput(value);
                        if (roomId != null) {
                          _openDirectRoom();
                        } else {
                          _search(value);
                        }
                      },
                      decoration: const InputDecoration(
                        hintText: '搜索直播间、主播或粘贴链接',
                        prefixIcon: Icon(Icons.search_rounded, size: 20),
                        contentPadding: EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => _onChanged(_controller.text),
                    child: const Text('搜索'),
                  ),
                ],
              ),
            ),
            if (_directRoomId != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: AppCard(
                  padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                  onTap: _directLoading ? null : _openDirectRoom,
                  child: Row(
                    children: <Widget>[
                      SoftIconBadge(
                        icon: Icons.link_rounded,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(
                              '直接打开直播间',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: context.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '房间号 ${_directRoomId!}',
                              style: TextStyle(
                                fontSize: 11,
                                color: context.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_directLoading)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        Icon(
                          Icons.chevron_right_rounded,
                          color: context.textSecondary,
                        ),
                    ],
                  ),
                ),
              ),
            Expanded(child: _buildBody(context, network)),
          ],
        ),
      ),
    );
  }

  // ===== 结果列表与空态 =====
  Widget _buildBody(BuildContext context, NetworkState network) {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(strokeWidth: 2.2),
        ),
      );
    }

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              Icons.cloud_off_rounded,
              size: 44,
              color: context.textSecondary,
            ),
            const SizedBox(height: 14),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.6,
                color: context.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => _search(_query),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (_query.trim().length < 2) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              Icons.live_tv_rounded,
              size: 46,
              color: context.textSecondary.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 14),
            Text(
              '搜索「英雄联盟」「炫神」试试\n也可以直接粘贴直播间链接或房间号',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.7,
                color: context.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    if (_results.isEmpty) {
      return Center(
        child: Text(
          '没有找到相关直播间',
          style: TextStyle(fontSize: 12.5, color: context.textSecondary),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: _results.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (BuildContext context, int index) {
        final LiveRoom room = _results[index];
        return _RoomCard(
          room: room,
          favorite: network.isFavorite(room.roomId),
          onTap: () => _showRoomSheet(room),
        );
      },
    );
  }
}

// ===== 卡片组件 =====
class _RoomCard extends StatelessWidget {
  const _RoomCard({
    required this.room,
    required this.favorite,
    required this.onTap,
  });

  final LiveRoom room;
  final bool favorite;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(10),
      onTap: onTap,
      child: Row(
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 72,
              height: 54,
              child: _Cover(url: room.coverUrl, icon: Icons.live_tv_rounded),
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
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: context.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  room.title.isEmpty ? room.categoryLabel : room.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: context.textSecondary),
                ),
                const SizedBox(height: 4),
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
                    const SizedBox(width: 8),
                    Text(
                      '房间 ${room.roomId}',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: context.textSecondary.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (favorite)
            const Padding(
              padding: EdgeInsets.only(right: 2),
              child: Icon(
                Icons.star_rounded,
                size: 17,
                color: Color(0xFFFFB300),
              ),
            ),
        ],
      ),
    );
  }
}

/// 封面图：加载失败时回落到图标。
class _Cover extends StatelessWidget {
  const _Cover({required this.url, required this.icon});

  final String url;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final String normalized = url.startsWith('//') ? 'https:$url' : url;
    if (normalized.isEmpty) return _fallback(context);
    return Image.network(
      normalized,
      fit: BoxFit.cover,
      headers: const <String, String>{'Referer': 'https://live.bilibili.com/'},
      errorBuilder: (_, _, _) => _fallback(context),
      loadingBuilder:
          (BuildContext context, Widget child, ImageChunkEvent? progress) {
            if (progress == null) return child;
            return _fallback(context);
          },
    );
  }

  Widget _fallback(BuildContext context) {
    return ColoredBox(
      color: context.isDark
          ? Colors.white.withValues(alpha: 0.06)
          : const Color(0xFFEFF1F8),
      child: Icon(icon, size: 22, color: context.textSecondary),
    );
  }
}

class _SheetAction extends StatelessWidget {
  const _SheetAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          children: <Widget>[
            Icon(
              icon,
              size: 19,
              color: highlighted ? AppColors.primary : Colors.white54,
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                color: highlighted ? AppColors.primary : Colors.white,
                fontSize: 13.5,
                fontWeight: highlighted ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
