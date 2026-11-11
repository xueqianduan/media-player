// -------------------------------------------------------------------------
// 功能：设置持久化
//
// 主要内容：
// - 读取/写入 AppSettings
// -------------------------------------------------------------------------

import 'dart:async';

import '../../../core/database/local_database.dart';
import '../domain/app_settings.dart';

/// 设置仓储：主题、默认倍速、手势开关、排序与展示方式。
class SettingsRepository {
  SettingsRepository({required this.database});

  final LocalDatabase database;

  AppSettings load() {
    final Map<String, dynamic> raw = database.readTable('settings');
    if (raw.isEmpty) return const AppSettings();
    try {
      return AppSettings.fromJson(raw);
    } catch (_) {
      return const AppSettings();
    }
  }

  Future<void> save(AppSettings settings) async {
    database.writeTable('settings', settings.toJson());
    unawaited(database.flush());
  }
}
