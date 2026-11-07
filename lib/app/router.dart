import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/app_theme.dart';
import '../features/category/presentation/categories_page.dart';
import '../features/category/presentation/category_detail_page.dart';
import '../features/favorites/presentation/favorites_page.dart';
import '../features/history/presentation/history_page.dart';
import '../features/library/presentation/all_videos_page.dart';
import '../features/library/presentation/folder_page.dart';
import '../features/library/presentation/search_page.dart';
import '../features/library/presentation/video_actions.dart';
import '../features/player/presentation/player_page.dart';
import '../features/playlist/presentation/playlist_detail_page.dart';
import '../features/playlist/presentation/playlists_page.dart';
import '../features/settings/presentation/info_pages.dart';
import '../features/settings/presentation/library_settings_pages.dart';
import '../features/settings/presentation/settings_pages.dart';
import '../features/shell/presentation/home_shell.dart';

/// 构建应用路由。测试中也可以调用它获得独立实例。
GoRouter buildRouter({String initialLocation = '/'}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: <RouteBase>[
      GoRoute(path: '/', builder: (_, _) => const HomeShell()),
      GoRoute(
        path: '/folder/:id',
        builder: (BuildContext context, GoRouterState state) =>
            FolderPage(folderId: state.pathParameters['id']!),
      ),
      GoRoute(path: '/videos', builder: (_, _) => const AllVideosPage()),
      GoRoute(
        path: '/search',
        builder: (BuildContext context, GoRouterState state) =>
            SearchPage(folderId: state.uri.queryParameters['folder']),
      ),
      GoRoute(path: '/favorites', builder: (_, _) => const FavoritesPage()),
      GoRoute(path: '/categories', builder: (_, _) => const CategoriesPage()),
      GoRoute(
        path: '/categories/:id',
        builder: (BuildContext context, GoRouterState state) =>
            CategoryDetailPage(categoryId: state.pathParameters['id']!),
      ),
      GoRoute(path: '/playlists', builder: (_, _) => const PlaylistsPage()),
      GoRoute(
        path: '/playlists/:id',
        builder: (BuildContext context, GoRouterState state) =>
            PlaylistDetailPage(playlistId: state.pathParameters['id']!),
      ),
      GoRoute(path: '/history', builder: (_, _) => const HistoryPage()),
      GoRoute(
        path: '/hidden-folders',
        builder: (_, _) => const HiddenFoldersPage(),
      ),
      GoRoute(
        path: '/settings/media',
        builder: (_, _) => const MediaScanPage(),
      ),
      GoRoute(
        path: '/settings/playback',
        builder: (_, _) => const PlaybackSettingsPage(),
      ),
      GoRoute(
        path: '/settings/appearance',
        builder: (_, _) => const AppearancePage(),
      ),
      GoRoute(
        path: '/settings/storage',
        builder: (_, _) => const StoragePage(),
      ),
      GoRoute(path: '/about', builder: (_, _) => const AboutPage()),
      GoRoute(path: '/privacy', builder: (_, _) => const PrivacyPage()),
      GoRoute(path: '/help', builder: (_, _) => const HelpPage()),
      GoRoute(
        path: '/player',
        builder: (BuildContext context, GoRouterState state) {
          final Object? extra = state.extra;
          if (extra is PlayerArgs) return PlayerPage(args: extra);
          return const _MissingPlayerPage();
        },
      ),
    ],
    errorBuilder: (BuildContext context, GoRouterState state) {
      return Scaffold(
        backgroundColor: context.appBackground,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.explore_off_rounded,
                size: 40,
                color: AppColors.primary,
              ),
              const SizedBox(height: 12),
              Text(
                '页面不存在',
                style: TextStyle(fontSize: 14, color: context.textPrimary),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => context.go('/'),
                child: const Text('回到首页'),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// 应用级单例路由。
final GoRouter appRouter = buildRouter();

class _MissingPlayerPage extends StatelessWidget {
  const _MissingPlayerPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.play_disabled_rounded,
              color: Colors.white54,
              size: 40,
            ),
            const SizedBox(height: 12),
            const Text('没有可播放的视频', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () =>
                  context.canPop() ? context.pop() : context.go('/'),
              child: const Text('返回'),
            ),
          ],
        ),
      ),
    );
  }
}
