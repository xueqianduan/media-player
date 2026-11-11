// -------------------------------------------------------------------------
// 功能：传输记录持久化
//
// 主要内容：
// - 从 LocalDatabase 的 transfers 表读取历史
// - 按任务 upsert 并落盘（最多保留 50 条）
// -------------------------------------------------------------------------

import '../../../core/database/local_database.dart';
import '../domain/transfer_models.dart';

class TransferRepository {
  TransferRepository({required this.database});

  final LocalDatabase database;

  /// 最多保留的记录条数，避免单 JSON 无限膨胀。
  static const int maxRecords = 50;

  List<TransferRecord> load() {
    final List<TransferRecord> records = <TransferRecord>[];
    for (final Object? row in database.readList('transfers')) {
      final TransferRecord? record = TransferRecord.fromJson(row);
      if (record != null) records.add(record);
    }
    records.sort(
      (TransferRecord a, TransferRecord b) =>
          b.startedAt.compareTo(a.startedAt),
    );
    return records;
  }

  Future<List<TransferRecord>> save(List<TransferRecord> records) {
    final List<TransferRecord> trimmed = records.take(maxRecords).toList();
    database.writeTable(
      'transfers',
      trimmed.map((TransferRecord record) => record.toJson()).toList(),
    );
    return database.flush().then((_) => trimmed);
  }

  /// 新任务插入到最前；同 id 则替换（进度更新走这里）。
  List<TransferRecord> upsert(
    List<TransferRecord> current,
    TransferRecord record,
  ) {
    final List<TransferRecord> next = <TransferRecord>[
      record,
      ...current.where((TransferRecord item) => item.id != record.id),
    ]..sort(
        (TransferRecord a, TransferRecord b) =>
            b.startedAt.compareTo(a.startedAt),
      );
    return next.take(maxRecords).toList();
  }
}
