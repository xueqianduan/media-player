// -------------------------------------------------------------------------
// 功能：文件传输状态控制器
//
// 主要内容：
// - 传输记录的读取与写入（首页最近记录、历史页共用）
// - 当前活动任务（首版同一时刻只允许一个）
// -------------------------------------------------------------------------

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../data/transfer_repository.dart';
import '../domain/transfer_models.dart';

final Provider<TransferRepository> transferRepositoryProvider =
    Provider<TransferRepository>(
      (Ref ref) => TransferRepository(database: ref.watch(databaseProvider)),
    );

class TransferController extends Notifier<List<TransferRecord>> {
  @override
  List<TransferRecord> build() => ref.watch(transferRepositoryProvider).load();

  TransferRepository get _repository => ref.read(transferRepositoryProvider);

  /// 首页只展示最近三条。
  List<TransferRecord> get recent => state.take(3).toList();

  /// 当前正在进行的任务（首版同时只允许一个）。
  TransferRecord? get active {
    for (final TransferRecord record in state) {
      if (!record.status.isFinished) return record;
    }
    return null;
  }

  void upsert(TransferRecord record) {
    final List<TransferRecord> next = _repository.upsert(state, record);
    state = next;
    _repository.save(next);
  }

  void clear() {
    state = const <TransferRecord>[];
    _repository.save(const <TransferRecord>[]);
  }
}

final NotifierProvider<TransferController, List<TransferRecord>>
transferControllerProvider =
    NotifierProvider<TransferController, List<TransferRecord>>(
      TransferController.new,
    );
