/// 时间、大小、分辨率等展示格式化工具。
library;

String _two(int value) => value.toString().padLeft(2, '0');

/// 播放器时间：`42:18` / `1:02:03`。
String formatDuration(int milliseconds) {
  if (milliseconds <= 0) return '00:00';
  final int totalSeconds = milliseconds ~/ 1000;
  final int hours = totalSeconds ~/ 3600;
  final int minutes = (totalSeconds % 3600) ~/ 60;
  final int seconds = totalSeconds % 60;
  if (hours > 0) {
    return '$hours:${_two(minutes)}:${_two(seconds)}';
  }
  return '${_two(minutes)}:${_two(seconds)}';
}

/// 文件大小：`972 MB` / `2.8 GB`。
String formatBytes(int bytes) {
  if (bytes <= 0) return '未知大小';
  const List<String> units = <String>['B', 'KB', 'MB', 'GB', 'TB'];
  double value = bytes.toDouble();
  int unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final String text = unit == 0
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(value >= 100 ? 0 : 1);
  return '$text ${units[unit]}';
}

/// `2025-01-16 19:32`
String formatDateTime(DateTime time) {
  final DateTime local = time.toLocal();
  return '${local.year}-${_two(local.month)}-${_two(local.day)} '
      '${_two(local.hour)}:${_two(local.minute)}';
}

/// 最近列表里的相对时间：`今天 20:11` / `昨天 17:32` / `03-12 09:20`
String formatRelativeTime(DateTime time, {DateTime? now}) {
  final DateTime local = time.toLocal();
  final DateTime current = (now ?? DateTime.now()).toLocal();
  final DateTime today = DateTime(current.year, current.month, current.day);
  final DateTime target = DateTime(local.year, local.month, local.day);
  final int diffDays = today.difference(target).inDays;
  final String clock = '${_two(local.hour)}:${_two(local.minute)}';
  if (diffDays == 0) return '今天 $clock';
  if (diffDays == 1) return '昨天 $clock';
  if (diffDays < 7) return '$diffDays 天前 $clock';
  if (local.year == current.year) {
    return '${_two(local.month)}-${_two(local.day)} $clock';
  }
  return formatDateTime(local);
}

/// `1920×1080`，未知时返回 `--`。
String formatResolution(int width, int height) {
  if (width <= 0 || height <= 0) return '--';
  return '$width×$height';
}

/// `已观看 32%`
String formatWatchPercent(double fraction) {
  final int percent = (fraction * 100).clamp(0, 100).round();
  return '已观看 $percent%';
}
