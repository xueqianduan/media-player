// -------------------------------------------------------------------------
// 功能：视觉基础：色板与主题
//
// 主要内容：
// - AppColors 色板常量
// - 亮/暗 ThemeData 构建
// - BuildContext 取色扩展（textPrimary 等）
// -------------------------------------------------------------------------

import 'package:flutter/material.dart';

/// ReelBox 设计令牌。
///
/// 浅色主题：白底 + 浅灰卡片 + 蓝紫强调色；
/// 深色主题：深色底 + 深灰卡片 + 同一强调色。
class AppColors {
  const AppColors._();

  static const Color primary = Color(0xFF5A6BF0);
  static const Color primaryDeep = Color(0xFF4051E0);
  static const Color primarySoft = Color(0xFFEDEFFF);

  static const Color lightBackground = Color(0xFFF5F7FD);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightText = Color(0xFF1B1D2A);
  static const Color lightTextSecondary = Color(0xFF8A90A4);
  static const Color lightDivider = Color(0xFFEDEFF6);

  static const Color darkBackground = Color(0xFF0E1018);
  static const Color darkSurface = Color(0xFF181B25);
  static const Color darkSurfaceHigh = Color(0xFF212533);
  static const Color darkText = Color(0xFFF2F4FA);
  static const Color darkTextSecondary = Color(0xFFA7AEC3);
  static const Color darkDivider = Color(0xFF252938);

  static const Color success = Color(0xFF2FBF71);
  static const Color warning = Color(0xFFF5A524);
  static const Color playerScrim = Color(0xCC0B0D14);
}

/// 依据当前亮度取色的便捷扩展，页面里不再写死颜色。
extension AppPaletteX on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  Color get appBackground =>
      isDark ? AppColors.darkBackground : AppColors.lightBackground;
  Color get cardColor =>
      isDark ? AppColors.darkSurface : AppColors.lightSurface;
  Color get cardColorHigh =>
      isDark ? AppColors.darkSurfaceHigh : AppColors.lightSurface;
  Color get textPrimary => isDark ? AppColors.darkText : AppColors.lightText;
  Color get textSecondary =>
      isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
  Color get dividerColor =>
      isDark ? AppColors.darkDivider : AppColors.lightDivider;
  Color get softPrimary => isDark
      ? AppColors.primary.withValues(alpha: 0.18)
      : AppColors.primarySoft;
}

class AppTheme {
  const AppTheme._();

  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final bool isDark = brightness == Brightness.dark;
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: brightness,
      primary: AppColors.primary,
      surface: isDark ? AppColors.darkSurface : AppColors.lightSurface,
    );

    final Color textPrimary = isDark ? AppColors.darkText : AppColors.lightText;
    final Color textSecondary = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: isDark
          ? AppColors.darkBackground
          : AppColors.lightBackground,
      splashFactory: InkSparkle.splashFactory,
      fontFamilyFallback: const <String>[
        'PingFang SC',
        'Microsoft YaHei',
        'Noto Sans CJK SC',
      ],
      appBarTheme: AppBarTheme(
        backgroundColor: isDark
            ? AppColors.darkBackground
            : AppColors.lightBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        foregroundColor: textPrimary,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: isDark ? AppColors.darkDivider : AppColors.lightDivider,
        thickness: 1,
        space: 1,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark
            ? AppColors.darkSurfaceHigh
            : AppColors.lightText,
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? AppColors.darkSurfaceHigh : Colors.white,
        hintStyle: TextStyle(color: textSecondary, fontSize: 14),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: isDark ? AppColors.darkDivider : AppColors.lightDivider,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: isDark ? AppColors.darkDivider : AppColors.lightDivider,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
        ),
      ),
      textTheme: Typography.material2021(platform: TargetPlatform.android).black
          .apply(bodyColor: textPrimary, displayColor: textPrimary)
          .copyWith(
            titleMedium: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: textPrimary,
            ),
            bodyMedium: TextStyle(fontSize: 14, color: textPrimary),
            bodySmall: TextStyle(fontSize: 12, color: textSecondary),
            labelSmall: TextStyle(fontSize: 11, color: textSecondary),
          ),
    );
  }
}
