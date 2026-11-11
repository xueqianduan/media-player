// -------------------------------------------------------------------------
// 功能：文件传输领域模型
//
// 主要内容：
// - 文件类型 / 传输方向 / 任务状态枚举
// - 待发送文件 TransferFile
// - 传输记录 TransferRecord（含字节进度与结果）
// -------------------------------------------------------------------------

/// 文件分类，对应选择页顶部的六个标签。
enum TransferFileType { video, app, document, image, audio, other }

extension TransferFileTypeX on TransferFileType {
  String get label {
    switch (this) {
      case TransferFileType.video:
        return '视频';
      case TransferFileType.app:
        return '应用';
      case TransferFileType.document:
        return '文档';
      case TransferFileType.image:
        return '图片';
      case TransferFileType.audio:
        return '音频';
      case TransferFileType.other:
        return '其他';
    }
  }

  /// 媒体类（视频 / 图片 / 音频）支持「全部文件 / 文件夹」两种浏览方式。
  bool get supportsFolders =>
      this == TransferFileType.video ||
      this == TransferFileType.image ||
      this == TransferFileType.audio;

  static TransferFileType? fromName(String? value) {
    for (final TransferFileType type in TransferFileType.values) {
      if (type.name == value) return type;
    }
    return null;
  }
}

/// 传输方向。
enum TransferDirection { send, receive }

extension TransferDirectionX on TransferDirection {
  String get label => this == TransferDirection.send ? '发送' : '接收';

  static TransferDirection fromName(String? value) =>
      value == 'receive' ? TransferDirection.receive : TransferDirection.send;
}

/// 任务状态。首版用于记录与详情页展示。
enum TransferStatus { queued, running, paused, completed, failed, cancelled }

extension TransferStatusX on TransferStatus {
  String get label {
    switch (this) {
      case TransferStatus.queued:
        return '排队中';
      case TransferStatus.running:
        return '传输中';
      case TransferStatus.paused:
        return '已暂停';
      case TransferStatus.completed:
        return '已完成';
      case TransferStatus.failed:
        return '失败';
      case TransferStatus.cancelled:
        return '已取消';
    }
  }

  bool get isFinished =>
      this == TransferStatus.completed ||
      this == TransferStatus.failed ||
      this == TransferStatus.cancelled;

  static TransferStatus fromName(String? value) {
    for (final TransferStatus status in TransferStatus.values) {
      if (status.name == value) return status;
    }
    return TransferStatus.queued;
  }
}

/// 一个待发送文件。
///
/// [id] 是稳定标识（相册资产 id 或文件路径），全局去重与任务快照都以它为准，
/// 不能用文件名代替——同名文件可能来自不同目录。
class TransferFile {
  const TransferFile({
    required this.id,
    required this.path,
    required this.name,
    required this.size,
    required this.type,
    this.source = '',
  });

  final String id;
  final String path;
  final String name;
  final int size;
  final TransferFileType type;

  /// 来源说明，用于区分同名文件（文件夹名、系统选择器等）。
  final String source;

  bool get isAvailable => path.isNotEmpty;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'path': path,
    'name': name,
    'size': size,
    'type': type.name,
    'source': source,
  };

  static TransferFile? fromJson(Object? value) {
    if (value is! Map) return null;
    final Map<String, dynamic> json = Map<String, dynamic>.from(value);
    final String id = '${json['id'] ?? ''}';
    final String path = '${json['path'] ?? ''}';
    if (id.isEmpty || path.isEmpty) return null;
    return TransferFile(
      id: id,
      path: path,
      name: '${json['name'] ?? '未命名文件'}',
      size: (json['size'] as num?)?.toInt() ?? 0,
      type: TransferFileTypeX.fromName(json['type'] as String?) ??
          TransferFileType.other,
      source: '${json['source'] ?? ''}',
    );
  }
}

/// 一次传输任务。
class TransferRecord {
  const TransferRecord({
    required this.id,
    required this.direction,
    required this.status,
    required this.deviceName,
    required this.files,
    required this.totalBytes,
    required this.startedAt,
    this.transferredBytes = 0,
    this.finishedAt,
    this.savePath,
    this.error,
  });

  final String id;
  final TransferDirection direction;
  final TransferStatus status;

  /// 对端临时设备名，未连接时为空。
  final String deviceName;
  final List<TransferFile> files;
  final int totalBytes;
  final int transferredBytes;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final String? savePath;
  final String? error;

  double get progress {
    if (totalBytes <= 0) return 0;
    final double value = transferredBytes / totalBytes;
    return value.clamp(0, 1).toDouble();
  }

  /// 首页摘要：单文件显示文件名，多文件显示「首个文件等 N 个文件」。
  String get summary {
    if (files.isEmpty) return '未选择文件';
    if (files.length == 1) return files.first.name;
    return '${files.first.name} 等 ${files.length} 个文件';
  }

  TransferRecord copyWith({
    TransferStatus? status,
    String? deviceName,
    int? transferredBytes,
    DateTime? finishedAt,
    String? savePath,
    String? error,
  }) {
    return TransferRecord(
      id: id,
      direction: direction,
      status: status ?? this.status,
      deviceName: deviceName ?? this.deviceName,
      files: files,
      totalBytes: totalBytes,
      transferredBytes: transferredBytes ?? this.transferredBytes,
      startedAt: startedAt,
      finishedAt: finishedAt ?? this.finishedAt,
      savePath: savePath ?? this.savePath,
      error: error ?? this.error,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'direction': direction.name,
    'status': status.name,
    'deviceName': deviceName,
    'files': files.map((TransferFile file) => file.toJson()).toList(),
    'totalBytes': totalBytes,
    'transferredBytes': transferredBytes,
    'startedAt': startedAt.toIso8601String(),
    'finishedAt': finishedAt?.toIso8601String(),
    'savePath': savePath,
    'error': error,
  };

  static TransferRecord? fromJson(Object? value) {
    if (value is! Map) return null;
    final Map<String, dynamic> json = Map<String, dynamic>.from(value);
    final String id = '${json['id'] ?? ''}';
    if (id.isEmpty) return null;

    final List<TransferFile> files = <TransferFile>[];
    final Object? rows = json['files'];
    if (rows is List) {
      for (final Object? row in rows) {
        final TransferFile? file = TransferFile.fromJson(row);
        if (file != null) files.add(file);
      }
    }

    return TransferRecord(
      id: id,
      direction: TransferDirectionX.fromName(json['direction'] as String?),
      status: TransferStatusX.fromName(json['status'] as String?),
      deviceName: '${json['deviceName'] ?? ''}',
      files: files,
      totalBytes: (json['totalBytes'] as num?)?.toInt() ?? 0,
      transferredBytes: (json['transferredBytes'] as num?)?.toInt() ?? 0,
      startedAt: DateTime.tryParse('${json['startedAt']}') ?? DateTime.now(),
      finishedAt: DateTime.tryParse('${json['finishedAt']}'),
      savePath: json['savePath'] as String?,
      error: json['error'] as String?,
    );
  }
}
