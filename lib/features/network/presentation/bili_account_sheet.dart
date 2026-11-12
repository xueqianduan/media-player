// -------------------------------------------------------------------------
// 功能：B 站账号面板与头像
//
// 主要内容：
// - 已登录时的账号面板：刷新会话、切换账号、退出登录
// - BiliAvatar：账号头像，加载失败回落到默认图标
// - 登录入口本身在 bili_login_page.dart（内嵌官方网页登录）
// -------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../application/bili_account_controller.dart';
import '../data/bili_session.dart';

/// 已登录时的账号面板。
///
/// 返回 true 表示用户选择「切换账号」，由调用方打开登录页。
Future<bool?> showBiliAccountSheet(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: context.cardColor,
    builder: (BuildContext sheetContext) => Consumer(
      builder: (BuildContext context, WidgetRef ref, Widget? child) {
        final BiliAccountState state = ref.watch(biliAccountProvider);
        final BiliAccount? account = state.account;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text(
                      'B 站账号',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: context.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(
                        Icons.close_rounded,
                        size: 20,
                        color: context.textSecondary,
                      ),
                    ),
                  ],
                ),
                if (account != null) ...<Widget>[
                  Row(
                    children: <Widget>[
                      BiliAvatar(url: account.face, size: 44),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              account.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: context.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'UID ${account.mid}${account.vip ? ' · 大会员' : ''}',
                              style: TextStyle(
                                fontSize: 11,
                                color: context.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                ],
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.refresh_rounded, size: 20),
                  title: const Text('刷新账号状态', style: TextStyle(fontSize: 13.5)),
                  subtitle: Text(
                    state.error ?? '确认当前会话在平台仍然有效',
                    style: TextStyle(
                      fontSize: 11,
                      color: state.error == null
                          ? context.textSecondary
                          : const Color(0xFFE24B4A),
                    ),
                  ),
                  onTap: () => ref.read(biliAccountProvider.notifier).refresh(),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.swap_horiz_rounded, size: 20),
                  title: const Text('切换账号', style: TextStyle(fontSize: 13.5)),
                  subtitle: Text(
                    '用另一个 B 站账号登录',
                    style: TextStyle(
                      fontSize: 11,
                      color: context.textSecondary,
                    ),
                  ),
                  onTap: () => Navigator.of(context).pop(true),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.logout_rounded, size: 20),
                  title: const Text('退出登录', style: TextStyle(fontSize: 13.5)),
                  subtitle: Text(
                    '退出后画质会回到匿名可用档位，收藏与组合保留',
                    style: TextStyle(
                      fontSize: 11,
                      color: context.textSecondary,
                    ),
                  ),
                  onTap: () async {
                    await ref.read(biliAccountProvider.notifier).logout();
                    if (context.mounted) Navigator.of(context).pop();
                  },
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

/// 账号头像：加载失败回落到默认图标。
class BiliAvatar extends StatelessWidget {
  const BiliAvatar({super.key, required this.url, this.size = 40});

  final String url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final String normalized = url.startsWith('//') ? 'https:$url' : url;
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: normalized.isEmpty
            ? _fallback(context)
            : Image.network(
                normalized,
                fit: BoxFit.cover,
                headers: const <String, String>{
                  'Referer': 'https://www.bilibili.com/',
                },
                errorBuilder: (_, _, _) => _fallback(context),
                loadingBuilder:
                    (BuildContext context, Widget child, ImageChunkEvent? p) =>
                        p == null ? child : _fallback(context),
              ),
      ),
    );
  }

  Widget _fallback(BuildContext context) {
    return Container(
      color: context.softPrimary,
      alignment: Alignment.center,
      child: Icon(
        Icons.person_rounded,
        size: size * 0.55,
        color: AppColors.primary,
      ),
    );
  }
}
