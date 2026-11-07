import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/ui_kit.dart';

/// 磁力模块：V1.0 仅保留入口与功能预告。
class MagnetPage extends StatelessWidget {
  const MagnetPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: <Widget>[
          const PageHeader(title: '磁力'),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 36),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Container(
                      width: 128,
                      height: 128,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: <Color>[
                            AppColors.primary.withValues(alpha: 0.18),
                            AppColors.primary.withValues(alpha: 0.05),
                          ],
                        ),
                      ),
                      child: const Icon(
                        Icons.link_rounded,
                        size: 58,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 26),
                    Text(
                      '功能开发中',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        color: context.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '后续将支持磁力链接管理与播放，包括链接解析、\n文件选择与按需播放。当前版本不影响本地视频使用。',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.7,
                        color: context.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: 220,
                      child: OutlinedButton.icon(
                        onPressed: null,
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('添加磁力链接'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          side: BorderSide(color: context.dividerColor),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'ReelBox Magnet · V2.0 规划',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: context.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
