import 'dart:async';

import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../library/domain/models.dart';
import '../data/settings_repository.dart';
import '../domain/app_settings.dart';

/// 设置控制器：所有设置项都会立即持久化。
class SettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.watch(initialSettingsProvider);

  SettingsRepository get _repository => ref.read(settingsRepositoryProvider);

  void setThemeMode(AppThemeMode mode) {
    _update(state.copyWith(themeMode: mode));
  }

  void setDefaultSpeed(double speed) {
    _update(state.copyWith(defaultSpeed: speed));
  }

  void setGesturesEnabled(bool enabled) {
    _update(state.copyWith(gesturesEnabled: enabled));
  }

  void setResumePrompt(bool enabled) {
    _update(state.copyWith(resumePrompt: enabled));
  }

  void setKeepScreenOn(bool enabled) {
    _update(state.copyWith(keepScreenOn: enabled));
  }

  void setSortOption(SortOption option) {
    _update(state.copyWith(sortOption: option));
  }

  void markScreenshotTipShown() {
    _update(state.copyWith(screenshotTipShown: true));
  }

  void setLongPressSpeed(double speed) {
    _update(state.copyWith(longPressSpeed: speed));
  }

  void setVideoScaleMode(VideoScaleMode mode) {
    _update(state.copyWith(videoScaleMode: mode));
  }

  void setPlaylistRepeatMode(RepeatMode mode) {
    _update(state.copyWith(playlistRepeatMode: mode));
  }

  void setViewMode(ViewMode mode) {
    _update(state.copyWith(viewMode: mode));
  }

  void toggleViewMode() {
    setViewMode(
      state.viewMode == ViewMode.list ? ViewMode.grid : ViewMode.list,
    );
  }

  void _update(AppSettings next) {
    state = next;
    unawaited(_repository.save(next));
  }
}

final NotifierProvider<SettingsController, AppSettings>
settingsControllerProvider = NotifierProvider<SettingsController, AppSettings>(
  SettingsController.new,
);

/// 应用主题模式。
final Provider<ThemeMode> themeModeProvider = Provider<ThemeMode>((Ref ref) {
  final AppThemeMode mode = ref.watch(
    settingsControllerProvider.select(
      (AppSettings settings) => settings.themeMode,
    ),
  );
  switch (mode) {
    case AppThemeMode.system:
      return ThemeMode.system;
    case AppThemeMode.light:
      return ThemeMode.light;
    case AppThemeMode.dark:
      return ThemeMode.dark;
  }
});

/// 底部导航索引。
class NavTabController extends Notifier<int> {
  @override
  int build() => 0;

  void select(int index) {
    if (index == state) return;
    state = index;
  }
}

final NotifierProvider<NavTabController, int> navTabProvider =
    NotifierProvider<NavTabController, int>(NavTabController.new);
