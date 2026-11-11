// -------------------------------------------------------------------------
// 功能：选择文件（P02）
//
// 主要内容：
// - 六类文件入口：视频 / 应用 / 文档 / 图片 / 音频 / 其他
// - 媒体类支持「全部文件 / 文件夹」两种浏览方式（photo_manager）
// - 非媒体类通过系统文件选择器添加
// - 跨类型跨文件夹的全局多选、已选清单与底部操作栏
// -------------------------------------------------------------------------

import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/ui_kit.dart';
import '../domain/transfer_models.dart';

/// 文件夹条目：用于「文件夹」浏览层。
class _FolderEntry {
  const _FolderEntry({
    required this.path,
    required this.name,
    required this.count,
  });

  final AssetPathEntity path;
  final String name;
  final int count;
}

class SelectFilesPage extends StatefulWidget {
  const SelectFilesPage({super.key, this.initialFiles = const <TransferFile>[]});

  /// 从视频分享入口带进来的预选文件。
  final List<TransferFile> initialFiles;

  @override
  State<SelectFilesPage> createState() => _SelectFilesPageState();
}

class _SelectFilesPageState extends State<SelectFilesPage> {
  TransferFileType _type = TransferFileType.video;
  bool _folderMode = false;

  AssetPathEntity? _folder;
  List<_FolderEntry> _folders = <_FolderEntry>[];
  List<AssetEntity> _assets = <AssetEntity>[];
  final Map<String, int> _sizes = <String, int>{};

  bool _loading = false;
  bool _denied = false;
  String? _error;

  final Map<String, TransferFile> _selected = <String, TransferFile>{};
  bool _showSelected = false;

  @override
  void initState() {
    super.initState();
    for (final TransferFile file in widget.initialFiles) {
      _selected[file.id] = file;
    }
    _load();
  }

  int get _totalBytes => _selected.values.fold(
    0,
    (int sum, TransferFile file) => sum + file.size,
  );

  // ---------------------------------------------------------------- 数据加载

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _denied = false;
      _folder = null;
      _folders = <_FolderEntry>[];
      _assets = <AssetEntity>[];
    });

    if (!_type.supportsFolders) {
      setState(() => _loading = false);
      return;
    }

    try {
      final PermissionState permission =
          await PhotoManager.requestPermissionExtend();
      if (!permission.hasAccess) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _denied = true;
        });
        return;
      }

      if (_folderMode) {
        final List<AssetPathEntity> paths = await PhotoManager.getAssetPathList(
          type: _requestType,
          onlyAll: false,
        );
        final List<_FolderEntry> folders = <_FolderEntry>[];
        for (final AssetPathEntity path in paths) {
          final int count = await path.assetCountAsync;
          if (count <= 0) continue;
          folders.add(
            _FolderEntry(path: path, name: path.name, count: count),
          );
        }
        if (!mounted) return;
        setState(() {
          _folders = folders;
          _loading = false;
        });
        return;
      }

      final List<AssetPathEntity> paths = await PhotoManager.getAssetPathList(
        type: _requestType,
        onlyAll: true,
      );
      if (paths.isEmpty) {
        if (!mounted) return;
        setState(() => _loading = false);
        return;
      }
      await _loadAssets(paths.first);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  RequestType get _requestType {
    switch (_type) {
      case TransferFileType.image:
        return RequestType.image;
      case TransferFileType.audio:
        return RequestType.audio;
      default:
        return RequestType.video;
    }
  }

  Future<void> _loadAssets(AssetPathEntity path) async {
    final List<AssetEntity> assets = await path.getAssetListPaged(
      page: 0,
      size: 200,
    );
    if (!mounted) return;
    setState(() {
      _assets = assets;
      _loading = false;
    });
    _resolveSizes(assets);
  }

  /// 文件大小需要读实际文件，异步补齐，避免卡住列表首帧。
  Future<void> _resolveSizes(List<AssetEntity> assets) async {
    for (final AssetEntity asset in assets) {
      if (_sizes.containsKey(asset.id)) continue;
      try {
        final int size = await _assetSize(asset);
        if (!mounted) return;
        setState(() => _sizes[asset.id] = size);
      } on Object {
        // 读取失败按 0 处理，不阻塞选择。
      }
    }
  }

  Future<int> _assetSize(AssetEntity asset) async {
    final File? file = await asset.file;
    if (file == null) return 0;
    try {
      return await file.length();
    } on Object {
      return 0;
    }
  }

  // ------------------------------------------------------------------ 选择

  Future<void> _toggleAsset(AssetEntity asset) async {
    final String id = asset.id;
    if (_selected.containsKey(id)) {
      setState(() => _selected.remove(id));
      return;
    }
    final int size = _sizes[id] ?? await _assetSize(asset);
    final String path = await _assetPath(asset);
    if (!mounted) return;
    setState(() {
      _sizes[id] = size;
      _selected[id] = TransferFile(
        id: id,
        path: path,
        name: asset.title ?? '未命名文件',
        size: size,
        type: _type,
        source: _folder?.name ?? '相册',
      );
    });
  }

  Future<String> _assetPath(AssetEntity asset) async {
    final File? file = await asset.file;
    return file?.path ?? '';
  }

  /// 全选范围：全部模式为当前类型全部结果，文件夹模式为当前文件夹。
  bool get _allSelected {
    if (_assets.isEmpty) return false;
    return _assets.every((AssetEntity asset) => _selected.containsKey(asset.id));
  }

  Future<void> _toggleSelectAll() async {
    if (_allSelected) {
      setState(() {
        for (final AssetEntity asset in _assets) {
          _selected.remove(asset.id);
        }
      });
      return;
    }
    for (final AssetEntity asset in _assets) {
      if (_selected.containsKey(asset.id)) continue;
      final int size = _sizes[asset.id] ?? await _assetSize(asset);
      final String path = await _assetPath(asset);
      if (!mounted) return;
      setState(() {
        _sizes[asset.id] = size;
        _selected[asset.id] = TransferFile(
          id: asset.id,
          path: path,
          name: asset.title ?? '未命名文件',
          size: size,
          type: _type,
          source: _folder?.name ?? '相册',
        );
      });
    }
  }

  Future<void> _pickFromSystem() async {
    final List<PlatformFile> picked = await FilePicker.pickFiles(
      dialogTitle: '选择${_type.label}',
      type: _type == TransferFileType.other ? FileType.any : FileType.custom,
      allowedExtensions: _extensions,
    );
    if (picked.isEmpty || !mounted) return;

    final List<TransferFile> added = <TransferFile>[];
    for (final PlatformFile file in picked) {
      final String path = file.path ?? file.uri.toString();
      if (path.isEmpty) continue;
      int size = 0;
      try {
        size = await file.length();
      } on Object {
        size = 0;
      }
      added.add(
        TransferFile(
          id: path,
          path: path,
          name: file.name,
          size: size,
          type: _type,
          source: '系统选择器',
        ),
      );
    }
    if (!mounted) return;
    setState(() {
      for (final TransferFile file in added) {
        _selected[file.id] = file;
      }
    });
  }

  List<String>? get _extensions {
    switch (_type) {
      case TransferFileType.app:
        return <String>['apk'];
      case TransferFileType.document:
        return <String>[
          'pdf',
          'doc',
          'docx',
          'xls',
          'xlsx',
          'ppt',
          'pptx',
          'txt',
          'md',
          'zip',
          'rar',
          '7z',
        ];
      default:
        return null;
    }
  }

  // ------------------------------------------------------------------ 构建

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appBackground,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _buildHeader(context),
            _buildTabs(context),
            if (_type.supportsFolders && _folder == null)
              _buildFolderSwitch(context),
            Expanded(child: _buildBody(context)),
            if (_showSelected) _buildSelectedPanel(context),
            _buildBottomBar(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final bool inFolder = _folder != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 12, 2),
      child: Row(
        children: <Widget>[
          IconButton(
            onPressed: () {
              if (inFolder) {
                setState(() {
                  _folder = null;
                  _assets = <AssetEntity>[];
                });
                _load();
              } else {
                context.pop();
              }
            },
            icon: Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 18,
              color: context.textPrimary,
            ),
          ),
          Expanded(
            child: Text(
              inFolder ? _folder!.name : '选择文件',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: context.textPrimary,
              ),
            ),
          ),
          if (_assets.isNotEmpty && !(_folderMode && _folder == null))
            TextButton(
              onPressed: _toggleSelectAll,
              child: Text(_allSelected ? '取消全选' : '全选'),
            ),
        ],
      ),
    );
  }

  Widget _buildTabs(BuildContext context) {
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: TransferFileType.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (BuildContext context, int index) {
          final TransferFileType type = TransferFileType.values[index];
          final bool selected = type == _type;
          return GestureDetector(
            onTap: () {
              if (type == _type) return;
              setState(() {
                _type = type;
                _folderMode = false;
                _folder = null;
              });
              _load();
            },
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: selected ? context.softPrimary : Colors.transparent,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                type.label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? AppColors.primary : context.textSecondary,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// 媒体类型的「全部文件 / 文件夹」切换。
  Widget _buildFolderSwitch(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        height: 38,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: context.cardColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: context.dividerColor, width: 0.8),
        ),
        child: Row(
          children: <Widget>[
            _SegmentButton(
              label: '全部文件',
              selected: !_folderMode,
              onTap: () {
                if (!_folderMode) return;
                setState(() => _folderMode = false);
                _load();
              },
            ),
            _SegmentButton(
              label: '文件夹',
              selected: _folderMode,
              onTap: () {
                if (_folderMode) return;
                setState(() => _folderMode = true);
                _load();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_denied) {
      return _StateView(
        icon: Icons.lock_outline_rounded,
        title: '需要${_type.label}访问权限',
        subtitle: '用于读取本机${_type.label}，不会上传到任何服务器',
        actionLabel: '允许访问',
        onAction: _load,
      );
    }
    if (_error != null) {
      return _StateView(
        icon: Icons.cloud_off_rounded,
        title: '读取失败',
        subtitle: _error!,
        actionLabel: '重试',
        onAction: _load,
      );
    }
    if (!_type.supportsFolders) {
      return _StateView(
        icon: Icons.folder_open_rounded,
        title: '从系统选择器添加${_type.label}',
        subtitle: '应用无法直接枚举这类文件，请通过系统文件选择器授权',
        actionLabel: '选择${_type.label}',
        onAction: _pickFromSystem,
      );
    }
    if (_folderMode && _folder == null) {
      if (_folders.isEmpty) {
        return const _StateView(
          icon: Icons.folder_off_outlined,
          title: '没有找到文件夹',
          subtitle: '当前类型下还没有可浏览的文件夹',
        );
      }
      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        itemCount: _folders.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (BuildContext context, int index) {
          final _FolderEntry folder = _folders[index];
          return AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            onTap: () async {
              setState(() => _loading = true);
              await _loadAssets(folder.path);
              if (!mounted) return;
              setState(() => _folder = folder.path);
            },
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.folder_rounded,
                  size: 26,
                  color: AppColors.primary.withValues(alpha: 0.75),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        folder.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: context.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${folder.count} 个${_type.label}',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: context.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: context.textSecondary,
                ),
              ],
            ),
          );
        },
      );
    }
    if (_assets.isEmpty) {
      return _StateView(
        icon: Icons.inbox_rounded,
        title: '没有${_type.label}',
        subtitle: '当前范围内没有可发送的${_type.label}',
        actionLabel: '用系统选择器添加',
        onAction: _pickFromSystem,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      itemCount: _assets.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (BuildContext context, int index) {
        final AssetEntity asset = _assets[index];
        final bool selected = _selected.containsKey(asset.id);
        return AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          onTap: () => _toggleAsset(asset),
          child: Row(
            children: <Widget>[
              _AssetThumb(asset: asset),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      asset.title ?? '未命名文件',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: context.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _subtitleFor(asset),
                      style: TextStyle(
                        fontSize: 10.5,
                        color: context.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              _CheckMark(selected: selected),
            ],
          ),
        );
      },
    );
  }

  String _subtitleFor(AssetEntity asset) {
    final int? size = _sizes[asset.id];
    final String sizeText = size == null ? '读取中…' : formatBytes(size);
    if (_type == TransferFileType.video && asset.duration > 0) {
      return '${formatDuration(asset.duration * 1000)} · $sizeText';
    }
    return sizeText;
  }

  Widget _buildSelectedPanel(BuildContext context) {
    final List<TransferFile> files = _selected.values.toList();
    return Container(
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: BoxDecoration(
        color: context.cardColor,
        border: Border(top: BorderSide(color: context.dividerColor, width: 0.8)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
            child: Row(
              children: <Widget>[
                Text(
                  '已选文件（${files.length}）',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: context.textPrimary,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: files.isEmpty
                      ? null
                      : () => setState(_selected.clear),
                  child: const Text('清除全部', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              itemCount: files.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (BuildContext context, int index) {
                final TransferFile file = files[index];
                return Row(
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            file.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: context.textPrimary,
                            ),
                          ),
                          Text(
                            formatBytes(file.size),
                            style: TextStyle(
                              fontSize: 10,
                              color: context.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () =>
                          setState(() => _selected.remove(file.id)),
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        Icons.close_rounded,
                        size: 16,
                        color: context.textSecondary,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    final int count = _selected.length;
    return Container(
      decoration: BoxDecoration(
        color: context.cardColor,
        border: Border(top: BorderSide(color: context.dividerColor, width: 0.8)),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: Row(
            children: <Widget>[
              GestureDetector(
                onTap: count == 0
                    ? null
                    : () => setState(() => _showSelected = !_showSelected),
                behavior: HitTestBehavior.opaque,
                child: Row(
                  children: <Widget>[
                    Text(
                      '已选 $count 项',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: count == 0
                            ? context.textSecondary
                            : AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Icon(
                      _showSelected
                          ? Icons.keyboard_arrow_down_rounded
                          : Icons.keyboard_arrow_up_rounded,
                      size: 18,
                      color: count == 0
                          ? context.textSecondary
                          : AppColors.primary,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 42,
                  child: FilledButton(
                    onPressed: count == 0 ? null : () => _next(count),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      '下一步',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _next(int count) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.cardColor,
      builder: (BuildContext sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '已选择 $count 个文件',
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                  color: context.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '共 ${formatBytes(_totalBytes)}',
                style: TextStyle(
                  fontSize: 12,
                  color: context.textSecondary,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                '扫码发送将在下一阶段接入：接收方展示二维码，'
                '发送方扫码后建立局域网连接并开始传输。',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.6,
                  color: context.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  const _SegmentButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? context.softPrimary : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                selected
                    ? Icons.list_rounded
                    : Icons.folder_outlined,
                size: 14,
                color: selected ? AppColors.primary : context.textSecondary,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? AppColors.primary : context.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AssetThumb extends StatelessWidget {
  const _AssetThumb({required this.asset});

  final AssetEntity asset;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 42,
        height: 42,
        child: FutureBuilder<Object?>(
          future: asset.thumbnailDataWithSize(const ThumbnailSize.square(120)),
          builder: (BuildContext context, AsyncSnapshot<Object?> snapshot) {
            final Object? data = snapshot.data;
            if (data is! List<int>) {
              return Container(
                color: context.softPrimary,
                child: const Icon(
                  Icons.movie_creation_outlined,
                  size: 18,
                  color: AppColors.primary,
                ),
              );
            }
            return Image.memory(
              Uint8List.fromList(data),
              fit: BoxFit.cover,
            );
          },
        ),
      ),
    );
  }
}

class _CheckMark extends StatelessWidget {
  const _CheckMark({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? AppColors.primary : Colors.transparent,
        border: Border.all(
          color: selected ? AppColors.primary : context.dividerColor,
          width: 1.4,
        ),
      ),
      child: selected
          ? const Icon(Icons.check_rounded, size: 13, color: Colors.white)
          : null,
    );
  }
}

class _StateView extends StatelessWidget {
  const _StateView({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              icon,
              size: 40,
              color: context.textSecondary.withValues(alpha: 0.55),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: context.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.6,
                color: context.textSecondary,
              ),
            ),
            if (actionLabel != null) ...<Widget>[
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
