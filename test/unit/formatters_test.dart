import 'package:flutter_test/flutter_test.dart';
import 'package:myplayer/core/utils/formatters.dart';

void main() {
  group('时长格式化', () {
    test('小于一小时显示 mm:ss', () {
      expect(formatDuration(0), '00:00');
      expect(formatDuration(65000), '01:05');
      expect(formatDuration(2538000), '42:18');
    });

    test('超过一小时显示 h:mm:ss', () {
      expect(formatDuration(3723000), '1:02:03');
    });
  });

  group('文件大小', () {
    test('按单位换算', () {
      expect(formatBytes(512), '512 B');
      expect(formatBytes(1024 * 1024), '1.0 MB');
      expect(formatBytes(1024 * 1024 * 1024), '1.0 GB');
      expect(formatBytes(0), '未知大小');
    });
  });

  group('时间展示', () {
    test('绝对时间格式', () {
      expect(formatDateTime(DateTime(2025, 1, 16, 19, 32)), '2025-01-16 19:32');
    });

    test('相对时间区分今天、昨天与更早', () {
      final DateTime now = DateTime(2025, 1, 16, 22, 0);
      expect(
        formatRelativeTime(DateTime(2025, 1, 16, 20, 11), now: now),
        '今天 20:11',
      );
      expect(
        formatRelativeTime(DateTime(2025, 1, 15, 20, 11), now: now),
        '昨天 20:11',
      );
      expect(
        formatRelativeTime(DateTime(2025, 1, 12, 20, 11), now: now),
        '4 天前 20:11',
      );
      expect(
        formatRelativeTime(DateTime(2024, 12, 1, 8, 5), now: now),
        '2024-12-01 08:05',
      );
    });
  });

  group('其他', () {
    test('分辨率与观看进度', () {
      expect(formatResolution(1920, 1080), '1920×1080');
      expect(formatResolution(0, 0), '--');
      expect(formatWatchPercent(0.324), '已观看 32%');
      expect(formatWatchPercent(1), '已观看 100%');
    });
  });
}
