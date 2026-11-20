// -------------------------------------------------------------------------
// 功能：传输历史（P06）
//
// 全部保留记录 + 方向筛选；空文件列表的旧记录不会崩溃。
// -------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/ui_kit.dart';
import '../application/transfer_controller.dart';
import '../domain/transfer_models.dart';

class TransferRecordsPage extends ConsumerStatefulWidget {
  const TransferRecordsPage({super.key});

  @override
  ConsumerState<TransferRecordsPage> createState() =>
      _TransferRecordsPageState();
}

class _TransferRecordsPageState extends ConsumerState<TransferRecordsPage> {
  String _filter = '全部';

  @override
  Widget build(BuildContext context) {
    final List<TransferRecord> all = ref.watch(transferControllerProvider);
    final List<TransferRecord> records = all.where((TransferRecord record) {
      if (_filter == '发送') return record.direction == TransferDirection.send;
      if (_filter == '接收') {
        return record.direction == TransferDirection.receive;
      }
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: context.appBackground,
      appBar: AppBar(
        backgroundColor: context.appBackground,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => context.pop(),
        ),
        title: const Text('传输记录'),
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              children: <Widget>[
                for (final String label in <String>['全部', '发送', '接收'])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(label),
                      selected: _filter == label,
                      onSelected: (_) => setState(() => _filter = label),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: records.isEmpty
                ? Center(
                    child: Text(
                      '没有传输记录',
                      style: TextStyle(color: context.textSecondary),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: records.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (BuildContext context, int index) {
                      final TransferRecord record = records[index];
                      return AppCard(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: <Widget>[
                            Icon(
                              record.direction == TransferDirection.send
                                  ? Icons.upload_rounded
                                  : Icons.download_rounded,
                              size: 18,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    record.summary,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: context.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '${record.direction.label} · '
                                    '${record.status.label} · '
                                    '${formatBytes(record.totalBytes)}',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      color: context.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
