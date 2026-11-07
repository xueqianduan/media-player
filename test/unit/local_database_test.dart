import 'package:flutter_test/flutter_test.dart';
import 'package:myplayer/core/database/local_database.dart';

void main() {
  group('数据结构迁移', () {
    test('v1 的收藏数组升级为 v2 的 media.isFavorite', () {
      final Map<String, dynamic> legacy = <String, dynamic>{
        'schemaVersion': 1,
        'favorites': <String>['a', 'c'],
        'media': <Map<String, dynamic>>[
          <String, dynamic>{'id': 'a', 'displayName': 'A'},
          <String, dynamic>{'id': 'b', 'displayName': 'B'},
          <String, dynamic>{'id': 'c', 'displayName': 'C'},
        ],
      };

      final Map<String, dynamic> migrated = LocalDatabase.migrate(legacy);

      expect(migrated['schemaVersion'], LocalDatabase.schemaVersion);
      final List<dynamic> media = migrated['media'] as List<dynamic>;
      expect((media[0] as Map<String, dynamic>)['isFavorite'], isTrue);
      expect((media[1] as Map<String, dynamic>)['isFavorite'], isFalse);
      expect((media[2] as Map<String, dynamic>)['isFavorite'], isTrue);
      expect(migrated.containsKey('favorites'), isFalse);
      expect(migrated['categories'], isNotNull);
      expect(migrated['playlists'], isNotNull);
    });

    test('缺少版本号的历史数据按 v1 处理', () {
      final Map<String, dynamic> legacy = <String, dynamic>{
        'media': <Map<String, dynamic>>[
          <String, dynamic>{'id': 'a'},
        ],
        'favorites': <String>['a'],
      };

      final Map<String, dynamic> migrated = LocalDatabase.migrate(legacy);

      expect(migrated['schemaVersion'], LocalDatabase.schemaVersion);
      expect(
        ((migrated['media'] as List<dynamic>).first
            as Map<String, dynamic>)['isFavorite'],
        isTrue,
      );
    });

    test('已经是当前版本的数据保持原样并补齐缺失表', () {
      final Map<String, dynamic> current = <String, dynamic>{
        'schemaVersion': LocalDatabase.schemaVersion,
        'media': <dynamic>[],
        'settings': <String, dynamic>{'themeMode': 'dark'},
      };

      final Map<String, dynamic> migrated = LocalDatabase.migrate(current);

      expect(migrated['settings']['themeMode'], 'dark');
      expect(migrated['folders'], isNotNull);
      expect(migrated['progress'], isNotNull);
    });
  });

  group('内存数据库', () {
    test('读取不存在的表返回空集合', () {
      final LocalDatabase database = LocalDatabase.inMemory();
      expect(database.readList('media'), isEmpty);
      expect(database.readTable('settings'), isEmpty);
    });

    test('写入后可以读回，不落盘', () async {
      final LocalDatabase database = LocalDatabase.inMemory();
      database.writeTable('media', <Map<String, dynamic>>[
        <String, dynamic>{'id': 'a'},
      ]);
      await database.flush();

      expect(database.isPersistent, isFalse);
      expect(database.readList('media').length, 1);
    });
  });
}
