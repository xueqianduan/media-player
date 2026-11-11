// -------------------------------------------------------------------------
// 功能：底部导航壳
//
// 主要内容：
// - 五个 tab 的切换与索引状态
// - 自定义底部导航栏样式
// -------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../library/application/library_controller.dart';
import '../../library/data/media_scanner.dart';
import '../../library/domain/models.dart';
import '../../library/presentation/local_page.dart';
import '../../magnet/presentation/magnet_page.dart';
import '../../network/presentation/network_page.dart';
import '../../profile/presentation/profile_page.dart';
import '../../settings/application/settings_controller.dart';

/// 应用外壳：四个底部导航入口。
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeScan());
  }

  Future<void> _maybeScan() async {
    final LibraryState state = ref.read(libraryControllerProvider);
    if (state.isScanning) return;
    final MediaScanner scanner = ref.read(mediaScannerProvider);

    // 当前平台不支持自动扫描：只更新提示，不涉及权限弹窗。
    if (!scanner.isSupported) {
      await ref.read(libraryControllerProvider.notifier).scan();
      return;
    }
    // 已授权且视频库为空（例如清空索引后）时自动重建列表；
    // 首次启动先展示权限说明，由用户点击「授权访问」后再申请，避免启动即弹系统框。
    if (state.permission.canRead && state.media.isEmpty) {
      await ref.read(libraryControllerProvider.notifier).scan();
    }
  }

  @override
  Widget build(BuildContext context) {
    final int index = ref.watch(navTabProvider);

    return Scaffold(
      backgroundColor: context.appBackground,
      body: IndexedStack(
        index: index,
        children: const <Widget>[
          LocalPage(),
          NetworkPage(),
          MagnetPage(),
          ProfilePage(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: context.cardColor,
          border: Border(
            top: BorderSide(color: context.dividerColor, width: 0.8),
          ),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 58,
            child: Row(
              children: <Widget>[
                _NavItem(
                  icon: Icons.folder_outlined,
                  activeIcon: Icons.folder_rounded,
                  label: '本地',
                  selected: index == 0,
                  onTap: () => ref.read(navTabProvider.notifier).select(0),
                ),
                _NavItem(
                  icon: Icons.language_outlined,
                  activeIcon: Icons.language_rounded,
                  label: '网络',
                  selected: index == 1,
                  onTap: () => ref.read(navTabProvider.notifier).select(1),
                ),
                _NavItem(
                  icon: Icons.link_rounded,
                  activeIcon: Icons.link_rounded,
                  label: '磁力',
                  selected: index == 2,
                  onTap: () => ref.read(navTabProvider.notifier).select(2),
                ),
                _NavItem(
                  icon: Icons.person_outline_rounded,
                  activeIcon: Icons.person_rounded,
                  label: '我的',
                  selected: index == 3,
                  onTap: () => ref.read(navTabProvider.notifier).select(3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color color = selected ? AppColors.primary : context.textSecondary;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(selected ? activeIcon : icon, size: 22, color: color),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: color,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
