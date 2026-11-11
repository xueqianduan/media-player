// -------------------------------------------------------------------------
// 功能：启动初始化流程
//
// 主要内容：
// - 初始化 media_kit、数据库等一次性依赖
// - 统一捕获启动期异常
// -------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import '../core/database/local_database.dart';
import '../features/library/data/library_repository.dart';
import '../features/library/domain/models.dart';
import '../features/settings/data/settings_repository.dart';
import '../features/settings/domain/app_settings.dart';
import 'app.dart';
import 'providers.dart';

/// 应用启动：初始化播放引擎、本地数据库、路由与首帧数据。
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  try {
    MediaKit.ensureInitialized();
  } on Object {
    // 某些平台（如 Web）可能不支持原生播放库，播放时会给出明确提示。
  }

  LocalDatabase database;
  try {
    database = await LocalDatabase.open();
  } on Object {
    database = LocalDatabase.inMemory();
  }

  LibraryState initialState = const LibraryState();
  AppSettings initialSettings = const AppSettings();
  try {
    initialState = LibraryRepository(database: database).load();
    initialSettings = SettingsRepository(database: database).load();
  } on Object {
    initialState = const LibraryState();
    initialSettings = const AppSettings();
  }

  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(database),
        initialLibraryStateProvider.overrideWithValue(initialState),
        initialSettingsProvider.overrideWithValue(initialSettings),
      ],
      child: const ReelBoxApp(),
    ),
  );
}
