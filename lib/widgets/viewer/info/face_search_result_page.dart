import 'dart:typed_data';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/extensions/metadata_edition.dart';
import 'package:aves/model/entry/extensions/props.dart';
import 'package:aves/model/face/face_manager.dart';
import 'package:aves/model/face/face_row.dart';
import 'package:aves/model/filters/covered/tag.dart';
import 'package:aves/model/source/collection_source.dart';
import 'package:aves/widgets/collection/collection_page.dart';
import 'package:aves/widgets/common/basic/scaffold.dart';
import 'package:aves/widgets/common/thumbnail/decorated.dart';
import 'package:aves/widgets/viewer/info/face_section.dart';
import 'package:material_ui/material_ui.dart';

class FaceSearchResultPage extends StatefulWidget {
  final AvesEntry? targetEntry;
  final FaceRow? targetFace;
  final Float32List? customEmbedding;
  final String? initialTagName;
  final CollectionSource source;

  const new({
    super.key,
    this.targetEntry,
    this.targetFace,
    this.customEmbedding,
    this.initialTagName,
    required this.source,
  }) : assert(targetFace != null || customEmbedding != null);

  @override
  State<FaceSearchResultPage> createState() => _FaceSearchResultPageState();
}

class _FaceSearchResultPageState extends State<FaceSearchResultPage> {
  double _threshold = 0.68;
  List<FaceMatch> _allMatches = [];
  final Set<AvesEntry> _selectedEntries = {};
  bool _isScanning = false;
  int _scannedCount = 0;
  int _scanTotal = 0;

  Float32List get embedding => widget.targetFace?.embedding ?? widget.customEmbedding!;

  @override
  void initState() {
    super.initState();
    _refreshMatches();
  }

  void _refreshMatches() {
    final matches = faceManager.findSimilarFaces(
      embedding,
      widget.source,
      threshold: _threshold,
      excludeEntryId: widget.targetEntry?.id,
    );
    setState(() {
      _allMatches = matches;
      _selectedEntries.clear();
      _selectedEntries.addAll(matches.map((m) => m.entry));
    });
  }

  Future<void> _scanGallery() async {
    final untagged = widget.source.visibleEntries.where((e) => e.isImage).toList();
    setState(() {
      _isScanning = true;
      _scannedCount = 0;
      _scanTotal = untagged.length;
    });

    await faceManager.scanEntries(
      untagged,
      onProgress: (current, total) {
        if (mounted && current % 10 == 0) {
          setState(() {
            _scannedCount = current;
            _scanTotal = total;
          });
        }
      },
    );

    if (mounted) {
      setState(() => _isScanning = false);
      _refreshMatches();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('图库人脸扫描完成，发现 ${_allMatches.length} 张匹配照片')),
      );
    }
  }

  Future<void> _batchApplyTag() async {
    if (_selectedEntries.isEmpty) return;

    final controller = TextEditingController(text: widget.initialTagName ?? '');
    final tag = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('为选中照片添加标签'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('将为已选的 ${_selectedEntries.length} 张照片打上同一标签：'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '标签名称（如女优名字）',
                hintText: '例如：Koyuki Yamaguchi',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) Navigator.pop(context, text);
            },
            child: const Text('确定打标'),
          ),
        ],
      ),
    );

    if (tag == null || tag.isEmpty || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(content: Text('正在为 ${_selectedEntries.length} 张照片写入标签 "$tag"...')),
    );

    int count = 0;
    for (final entry in _selectedEntries) {
      final currentTags = Set<String>.from(entry.tags);
      if (!currentTags.contains(tag)) {
        currentTags.add(tag);
        await entry.editTags(currentTags);
        count++;
      }
    }

    if (mounted) {
      messenger.showSnackBar(
        SnackBar(content: Text('成功为 $count 张照片添加标签 "$tag"！')),
      );
    }
  }

  void _openCollection() {
    if (_selectedEntries.isEmpty) return;
    Navigator.maybeOf(context)?.push(
      MaterialPageRoute(
        settings: const RouteSettings(name: CollectionPage.routeName),
        builder: (context) => CollectionPage(
          source: widget.source,
          filters: {if (widget.initialTagName != null) TagFilter(widget.initialTagName!)},
          entries: _selectedEntries.toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final targetEntry = widget.targetEntry;
    final targetFace = widget.targetFace;

    return AvesScaffold(
      appBar: AppBar(
        title: const Text('以脸搜脸结果'),
        actions: [
          IconButton(
            tooltip: '扫描图库中未提取人脸的照片',
            icon: const Icon(Icons.sync),
            onPressed: _isScanning ? null : _scanGallery,
          ),
        ],
      ),
      body: Column(
        children: [
          // Target face header card
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: [
                      if (targetEntry != null && targetFace != null)
                        FaceAvatar(
                          entry: targetEntry,
                          bounds: targetFace.bounds,
                          size: 56,
                        )
                      else
                        const CircleAvatar(
                          radius: 28,
                          child: Icon(Icons.face, size: 32),
                        ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.initialTagName != null
                                  ? '标签: ${widget.initialTagName}'
                                  : targetEntry?.bestTitle ?? '目标人脸',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '找到 ${_allMatches.length} 张相似照片 (已选 ${_selectedEntries.length})',
                              style: TextStyle(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            if (_selectedEntries.length == _allMatches.length) {
                              _selectedEntries.clear();
                            } else {
                              _selectedEntries.addAll(_allMatches.map((m) => m.entry));
                            }
                          });
                        },
                        child: Text(_selectedEntries.length == _allMatches.length ? '全不选' : '全选'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Similarity Threshold Slider
                  Row(
                    children: [
                      Text(
                        '相似度阈值: ${(_threshold * 100).toInt()}%',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                      Expanded(
                        child: Slider(
                          value: _threshold,
                          min: 0.50,
                          max: 0.90,
                          divisions: 40,
                          label: '${(_threshold * 100).toInt()}%',
                          onChanged: (val) {
                            setState(() => _threshold = val);
                          },
                          onChangeEnd: (_) => _refreshMatches(),
                        ),
                      ),
                    ],
                  ),
                  if (_isScanning) ...[
                    const SizedBox(height: 6),
                    LinearProgressIndicator(
                      value: _scanTotal > 0 ? _scannedCount / _scanTotal : null,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '正在检测图库人脸: $_scannedCount / $_scanTotal',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Matches grid
          Expanded(
            child: _allMatches.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.person_search, size: 64, color: Colors.grey),
                        const SizedBox(height: 12),
                        const Text(
                          '当前阈值下未找到匹配的照片',
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '尝试调低相似度阈值，或点击右上角同步扫描图库',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.tonalIcon(
                          onPressed: _scanGallery,
                          icon: const Icon(Icons.sync),
                          label: const Text('扫描图库中照片的人脸'),
                        ),
                      ],
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.all(8),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 6,
                      mainAxisSpacing: 6,
                      childAspectRatio: 0.85,
                    ),
                    itemCount: _allMatches.length,
                    itemBuilder: (context, index) {
                      final match = _allMatches[index];
                      final entry = match.entry;
                      final isSelected = _selectedEntries.contains(entry);
                      final pct = (match.similarity * 100).toInt();

                      Color pillColor = Colors.teal;
                      if (match.similarity >= 0.80) {
                        pillColor = Colors.green;
                      } else if (match.similarity < 0.65) {
                        pillColor = Colors.orange;
                      }

                      return InkWell(
                        onTap: () {
                          setState(() {
                            if (isSelected) {
                              _selectedEntries.remove(entry);
                            } else {
                              _selectedEntries.add(entry);
                            }
                          });
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            border: isSelected
                                ? Border.all(color: theme.colorScheme.primary, width: 3)
                                : Border.all(color: Colors.transparent, width: 3),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(5),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                DecoratedThumbnail(
                                  entry: entry,
                                  tileExtent: 180,
                                  selectable: false,
                                  highlightable: false,
                                ),
                                // Checkbox top right
                                Positioned(
                                  top: 3,
                                  right: 3,
                                  child: Container(
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.black54,
                                    ),
                                    padding: const EdgeInsets.all(2),
                                    child: Icon(
                                      isSelected ? Icons.check_circle : Icons.circle_outlined,
                                      color: isSelected ? Colors.greenAccent : Colors.white70,
                                      size: 20,
                                    ),
                                  ),
                                ),
                                // Similarity badge bottom
                                Positioned(
                                  bottom: 4,
                                  left: 4,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: pillColor.withValues(alpha: 0.9),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      '$pct% 相似',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),

          // Bottom Action Bar
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: theme.scaffoldBackgroundColor,
                boxShadow: const [
                  BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, -2)),
                ],
              ),
              child: Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _selectedEntries.isNotEmpty ? _openCollection : null,
                    icon: const Icon(Icons.collections, size: 18),
                    label: const Text('作为相册浏览'),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _selectedEntries.isNotEmpty ? _batchApplyTag : null,
                    icon: const Icon(Icons.local_offer, size: 18),
                    label: Text('批量打标签 (${_selectedEntries.length})'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
