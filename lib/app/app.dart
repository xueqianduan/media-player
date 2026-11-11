// -------------------------------------------------------------------------
// 功能：应用根组件
//
// 主要内容：
// - 主题与 light/dark 切换
// - 路由挂载（go_router）
// - 中文本地化三件套 + 全局字号缩放
// -------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../features/settings/application/settings_controller.dart';
import 'router.dart';

/// LumiPlayer 应用根组件。
class LumiPlayerApp extends ConsumerWidget {
  const LumiPlayerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'LumiPlayer',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ref.watch(themeModeProvider),
      routerConfig: appRouter,
      locale: const Locale('zh', 'CN'),
      // 声明了中文就必须同时提供中文的 Material / Widgets / Cupertino 资源，
      // 否则 MaterialLocalizations.of(context) 会直接抛异常 —— 底部弹窗
      // （showModalBottomSheet）在创建阶段就会失败，表现为「点了没反应」。
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const <Locale>[Locale('zh', 'CN'), Locale('en')],
      builder: (BuildContext context, Widget? child) {
        // 限制系统字体缩放范围，避免超大字号破坏卡片布局。
        final MediaQueryData media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: media.textScaler.clamp(
              minScaleFactor: 0.9,
              maxScaleFactor: 1.3,
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
