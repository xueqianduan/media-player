// -------------------------------------------------------------------------
// 功能：分类管理页
//
// 主要内容：
// - 分类列表与新建入口
// - 重命名/删除菜单
// -------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/ui_kit.dart';
import '../../library/application/library_controller.dart';
import '../../library/domain/models.dart';

/// 自定义分类列表：与系统文件夹完全区分。
class CategoriesPage extends ConsumerWidget {
  const CategoriesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final LibraryState state = ref.watch(libraryControllerProvider);
    final LibraryController controller = ref.read(
      libraryControllerProvider.notifier,
    );

    return Scaffold(
      backgroundColor: context.appBackground,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final String? name = await showTextInputDialog(
            context,
            title: '新建分类',
            description: '分类是应用内的虚拟文件夹，不会移动手机中的原始文件。',
            hintText: '例如：学习资料',
          );
          if (name != null && name.isNotEmpty) controller.createCategory(name);
        },
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        highlightElevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        icon: const Icon(Icons.add_rounded, size: 20),
        label: const Text('新建分类', style: TextStyle(fontSize: 13)),
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            PageHeader(
              title: '我的分类',
              subtitle: '共 ${state.categories.length} 个分类',
              leading: AppIconButton(
                icon: Icons.arrow_back_ios_new_rounded,
                iconSize: 18,
                onPressed: () =>
                    context.canPop() ? context.pop() : context.go('/'),
              ),
            ),
            Expanded(
              child: state.categories.isEmpty
                  ? const EmptyState(
                      icon: Icons.folder_special_outlined,
                      title: '还没有自定义分类',
                      message: '把视频按自己的习惯整理起来，例如「学习资料」「面试准备」，\n一个视频可以同时属于多个分类。',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                      itemCount: state.categories.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (BuildContext context, int index) {
                        final Category category = state.categories[index];
                        return AppCard(
                          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
                          onTap: () =>
                              context.push('/categories/${category.id}'),
                          child: Row(
                            children: <Widget>[
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: context.softPrimary,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.folder_special_rounded,
                                  size: 21,
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
                                      category.name,
                                      style: TextStyle(
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.w600,
                                        color: context.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      '${state.mediaInCategory(category.id).length} 个视频',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: context.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              PopupMenuButton<String>(
                                icon: Icon(
                                  Icons.more_horiz_rounded,
                                  size: 20,
                                  color: context.textSecondary,
                                ),
                                onSelected: (String value) async {
                                  if (value == 'rename') {
                                    final String? name =
                                        await showTextInputDialog(
                                          context,
                                          title: '重命名分类',
                                          initialValue: category.name,
                                        );
                                    if (name != null && name.isNotEmpty) {
                                      controller.renameCategory(
                                        category.id,
                                        name,
                                      );
                                    }
                                  } else if (value == 'delete') {
                                    final bool
                                    confirmed = await showConfirmDialog(
                                      context,
                                      title: '删除分类',
                                      message:
                                          '只删除分类与视频的关联，不会删除视频本身，也不影响其他分类和播放列表。',
                                      confirmLabel: '删除',
                                      danger: true,
                                    );
                                    if (confirmed) {
                                      controller.deleteCategory(category.id);
                                    }
                                  }
                                },
                                itemBuilder: (BuildContext context) =>
                                    const <PopupMenuEntry<String>>[
                                      PopupMenuItem<String>(
                                        value: 'rename',
                                        child: Text('重命名'),
                                      ),
                                      PopupMenuItem<String>(
                                        value: 'delete',
                                        child: Text('删除分类'),
                                      ),
                                    ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
