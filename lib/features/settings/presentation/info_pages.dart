// -------------------------------------------------------------------------
// 功能：信息页集合
//
// 主要内容：
// - 关于页
// - 隐私与权限说明
// - 帮助与反馈（FAQ 折叠列表）
// -------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/ui_kit.dart';
import '../../library/application/library_controller.dart';
import '../../library/domain/models.dart';
import '../../profile/presentation/profile_page.dart';
import 'settings_pages.dart';

// ===== 关于 =====
/// 关于 ReelBox。
class AboutPage extends ConsumerWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final LibraryState state = ref.watch(libraryControllerProvider);

    return SettingsScaffold(
      title: '关于 ReelBox',
      children: <Widget>[
        const SizedBox(height: 8),
        Center(
          child: Column(
            children: <Widget>[
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[Color(0xFF7C8CFF), Color(0xFF4C5BE8)],
                  ),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 46,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'ReelBox',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: context.textPrimary,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '版本 ${ProfilePage.version}',
                style: TextStyle(fontSize: 11.5, color: context.textSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        AppCard(
          padding: const EdgeInsets.all(16),
          child: Text(
            'ReelBox 是一款轻量级本地视频播放器。以本地视频文件夹为核心，'
            '以视频播放为基础，以视频管理为辅助：不推送内容、不申请无关权限，'
            '视频只保存在你的设备上。',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.7,
              color: context.textSecondary,
            ),
          ),
        ),
        const SizedBox(height: 12),
        AppCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: <Widget>[
              _AboutRow(label: '视频总数', value: '${state.totalCount} 个'),
              _AboutRow(label: '分类数量', value: '${state.categories.length} 个'),
              _AboutRow(label: '播放列表', value: '${state.playlists.length} 个'),
              _AboutRow(label: '播放记录', value: '${state.progress.length} 条'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(
            'Flutter · Riverpod · media_kit',
            style: TextStyle(fontSize: 10.5, color: context.textSecondary),
          ),
        ),
      ],
    );
  }
}

class _AboutRow extends StatelessWidget {
  const _AboutRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 12.5, color: context.textSecondary),
            ),
          ),
          Text(
            value,
            style: TextStyle(fontSize: 12.5, color: context.textPrimary),
          ),
        ],
      ),
    );
  }
}

// ===== 隐私与权限 =====
/// 隐私与权限说明。
class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});

  @override
  Widget build(BuildContext context) {
    const List<List<String>> sections = <List<String>>[
      <String>['视频只保存在本地', 'ReelBox 不上传、不备份、不分析你的视频内容，所有索引、分类与播放记录都保存在设备本地。'],
      <String>[
        '需要的权限',
        '视频读取权限用于扫描和播放本地视频；文件选择器权限仅在你主动导入视频时使用。应用不申请通讯录、位置、麦克风等无关权限。',
      ],
      <String>[
        '系统相册访问',
        'Android 通过 MediaStore 读取授权范围内的视频；iOS 通过 PhotoKit 访问相册，支持「仅选择的照片」有限授权。拒绝授权时仍可以通过文件选择器手动导入。',
      ],
      <String>[
        '数据删除',
        '「从 ReelBox 移除」只删除应用内记录，不影响手机中的原始文件；「清空视频库索引」同样不会删除视频文件。',
      ],
      <String>['未来版本', '磁力与云端能力尚未实现，V1.0 不包含账号系统、云端同步与任何网络视频请求。'],
    ];

    return SettingsScaffold(
      title: '隐私与权限',
      subtitle: 'ReelBox 不需要账号，也不会联网上传视频',
      children: <Widget>[
        for (final List<String> section in sections) ...<Widget>[
          AppCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  section[0],
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: context.textPrimary,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  section[1],
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.7,
                    color: context.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

// ===== 帮助与反馈 =====
/// 帮助与反馈。
class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  static const List<List<String>> faqs = <List<String>>[
    <String>[
      '为什么首页看不到视频？',
      '首次使用需要授权视频访问权限。如果此前拒绝过，可以到「我的 → 隐私与权限」或系统设置中重新授权，也可以直接用「导入视频」。',
    ],
    <String>[
      '分类和系统文件夹有什么区别？',
      '系统文件夹反映视频在手机中的真实存储位置，不能随意改变；分类是应用内的虚拟整理方式，一个视频可以同时属于多个分类，删除分类不会影响视频文件。',
    ],
    <String>[
      '播放进度会自动保存吗？',
      '会。播放中每 5 秒保存一次，暂停、拖动进度、退出播放器与进入后台时也会立即保存。观看达到 95% 会标记为已看完。',
    ],
    <String>[
      '支持哪些播放手势？',
      '单击显示控制栏，双击左右两侧快退 / 快进 10 秒，双击中间播放暂停，左右滑动调节亮度与音量，长按临时 2 倍速。可在播放设置中关闭手势。',
    ],
    <String>['如何切换倍速和播放队列？', '播放器底部可以直接切换倍速、查看播放队列；播放列表支持顺序、列表循环、单曲循环与随机播放。'],
    <String>[
      '磁力功能什么时候可用？',
      'V1.0 只保留入口与预告。磁力链接解析、P2P 下载与云端能力属于后续版本规划，不影响本地视频的浏览与播放。',
    ],
    <String>['移除视频会删除原文件吗？', '不会。ReelBox 只删除应用内记录。V1.0 不提供删除系统相册原始视频的能力，避免误删。'],
  ];

  @override
  Widget build(BuildContext context) {
    return SettingsScaffold(
      title: '帮助与反馈',
      subtitle: '常见问题',
      children: <Widget>[
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: faqs
                .map(
                  (List<String> faq) => Theme(
                    data: Theme.of(context).copyWith(
                      dividerColor: Colors.transparent,
                      splashColor: Colors.transparent,
                      highlightColor: Colors.transparent,
                    ),
                    child: ExpansionTile(
                      title: Text(
                        faq[0],
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: context.textPrimary,
                        ),
                      ),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                      expandedCrossAxisAlignment: CrossAxisAlignment.start,
                      iconColor: context.textSecondary,
                      collapsedIconColor: context.textSecondary,
                      children: <Widget>[
                        Text(
                          faq[1],
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.7,
                            color: context.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(
            'V1.0 · 反馈渠道将在后续版本提供',
            style: TextStyle(fontSize: 10.5, color: context.textSecondary),
          ),
        ),
      ],
    );
  }
}
