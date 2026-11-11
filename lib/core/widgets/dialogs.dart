// -------------------------------------------------------------------------
// 功能：通用对话框
//
// 主要内容：
// - 确认对话框（二次确认）
// - 文本输入对话框（重命名/新建）
// -------------------------------------------------------------------------

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 文本输入弹窗（重命名、新建分类 / 播放列表）。
Future<String?> showTextInputDialog(
  BuildContext context, {
  required String title,
  String? description,
  String initialValue = '',
  String hintText = '',
  String confirmLabel = '确定',
}) async {
  final TextEditingController controller = TextEditingController(
    text: initialValue,
  );
  final String? result = await showDialog<String>(
    context: context,
    builder: (BuildContext dialogContext) {
      return AlertDialog(
        title: Text(
          title,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: dialogContext.textPrimary,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (description != null) ...<Widget>[
              Text(
                description,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.5,
                  color: dialogContext.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: controller,
              autofocus: true,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(hintText: hintText),
              onSubmitted: (String value) =>
                  Navigator.of(dialogContext).pop(value.trim()),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(
              '取消',
              style: TextStyle(color: dialogContext.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: Text(
              confirmLabel,
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      );
    },
  );
  controller.dispose();
  return result;
}

/// 二次确认弹窗。
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = '确定',
  bool danger = false,
}) async {
  final bool? result = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) {
      return AlertDialog(
        title: Text(
          title,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: dialogContext.textPrimary,
          ),
        ),
        content: Text(
          message,
          style: TextStyle(
            fontSize: 13.5,
            height: 1.6,
            color: dialogContext.textSecondary,
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              '取消',
              style: TextStyle(color: dialogContext.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              confirmLabel,
              style: TextStyle(
                color: danger ? const Color(0xFFE5484D) : AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      );
    },
  );
  return result ?? false;
}
