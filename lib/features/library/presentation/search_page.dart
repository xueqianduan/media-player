import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/ui_kit.dart';
import '../../settings/application/settings_controller.dart';
import '../application/library_controller.dart';
import '../domain/models.dart';
import 'video_actions.dart';
import 'widgets/media_collection_view.dart';

/// 视频搜索：支持全部视频与当前文件夹两种范围。
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key, this.folderId});

  final String? folderId;

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final LibraryState state = ref.watch(libraryControllerProvider);
    final settings = ref.watch(settingsControllerProvider);
    final String? folderName = widget.folderId == null
        ? null
        : state.folderById(widget.folderId!)?.name;
    final List<MediaItem> results = sortMedia(
      state.search(_query, folderId: widget.folderId),
      settings.sortOption,
    );

    return Scaffold(
      backgroundColor: context.appBackground,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      onChanged: (String value) =>
                          setState(() => _query = value),
                      decoration: InputDecoration(
                        hintText: folderName == null
                            ? '搜索全部视频'
                            : '在「$folderName」中搜索',
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          size: 20,
                          color: context.textSecondary,
                        ),
                        suffixIcon: _query.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.close_rounded, size: 18),
                                onPressed: () {
                                  _controller.clear();
                                  setState(() => _query = '');
                                },
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () =>
                        context.canPop() ? context.pop() : context.go('/'),
                    child: const Text('取消'),
                  ),
                ],
              ),
            ),
            if (_query.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Row(
                  children: <Widget>[
                    Text(
                      '找到 ${results.length} 个结果',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: context.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: _query.trim().isEmpty
                  ? const EmptyState(
                      icon: Icons.search_rounded,
                      title: '搜索视频',
                      message: '输入视频名称进行模糊搜索，结果可以直接播放。',
                    )
                  : results.isEmpty
                  ? const EmptyState(
                      icon: Icons.search_off_rounded,
                      title: '没有匹配的视频',
                      message: '可以尝试更短的关键词。',
                    )
                  : MediaCollectionView(
                      items: results,
                      viewMode: settings.viewMode,
                      progress: state.progress,
                      onTap: (MediaItem item) => playSingleVideo(context, item),
                      onLongPress: (MediaItem item) {},
                      onMore: (MediaItem item) =>
                          showVideoActionSheet(context, ref, item),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
