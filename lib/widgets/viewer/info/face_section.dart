import 'dart:math';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/extensions/props.dart';
import 'package:aves/model/face/face_manager.dart';
import 'package:aves/model/face/face_row.dart';
import 'package:aves/model/source/collection_lens.dart';
import 'package:aves/model/source/collection_source.dart';
import 'package:aves/widgets/common/action_mixins/feedback.dart';
import 'package:aves/widgets/common/thumbnail/image.dart';
import 'package:aves/widgets/viewer/info/common.dart';
import 'package:aves/widgets/viewer/info/face_search_result_page.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

class FaceAvatar extends StatelessWidget {
  final AvesEntry entry;
  final Rect bounds;
  final double size;

  const new({
    super.key,
    required this.entry,
    required this.bounds,
    this.size = 56,
  });

  @override
  Widget build(BuildContext context) {
    final cx = bounds.center.dx;
    final cy = bounds.center.dy;
    final w = bounds.width.clamp(0.05, 1.0);
    final h = bounds.height.clamp(0.05, 1.0);
    final scale = 1.0 / (max(w, h) * 1.5);

    return ClipOval(
      child: Container(
        width: size,
        height: size,
        color: Colors.black26,
        child: ClipRect(
          child: OverflowBox(
            maxWidth: size * scale,
            maxHeight: size * scale,
            minWidth: size * scale,
            minHeight: size * scale,
            alignment: FractionalOffset(cx, cy),
            child: ThumbnailImage(
              entry: entry,
              extent: size * scale,
              devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
            ),
          ),
        ),
      ),
    );
  }
}

class FaceSectionSliver extends StatefulWidget {
  final AvesEntry entry;
  final CollectionLens? collection;

  const new({
    super.key,
    required this.entry,
    this.collection,
  });

  @override
  State<FaceSectionSliver> createState() => _FaceSectionSliverState();
}

class _FaceSectionSliverState extends State<FaceSectionSliver> with FeedbackMixin {
  bool _loading = false;
  List<FaceRow>? _faces;
  bool _detected = false;

  AvesEntry get entry => widget.entry;

  @override
  void initState() {
    super.initState();
    _loadFaces();
  }

  @override
  void didUpdateWidget(covariant FaceSectionSliver oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry != widget.entry) {
      _faces = null;
      _detected = false;
      _loadFaces();
    }
  }

  Future<void> _loadFaces() async {
    try {
      final cached = await faceManager.getFaces(entry, detectIfMissing: false);
      if (mounted) {
        setState(() {
          _faces = cached;
          _detected = cached.isNotEmpty;
        });
      }
    } catch (e) {
      debugPrint('FaceSectionSliver _loadFaces error: $e');
    }
  }

  Future<void> _detectFaces() async {
    setState(() => _loading = true);
    try {
      final faces = await faceManager.getFaces(entry, detectIfMissing: true);
      if (mounted) {
        setState(() {
          _faces = faces;
          _detected = true;
          _loading = false;
        });
        if (faces.isEmpty) {
          showFeedback(context, FeedbackType.info, '未在此照片中检测到清晰人脸');
        } else {
          showFeedback(context, FeedbackType.info, '成功识别到 ${faces.length} 张人脸');
        }
      }
    } catch (e, stack) {
      debugPrint('_detectFaces error: $e\n$stack');
      if (mounted) {
        setState(() => _loading = false);
        showFeedback(context, FeedbackType.warn, '人脸检测失败: $e');
      }
    }
  }

  void _searchByFace(BuildContext context, FaceRow face) {
    final source = widget.collection?.source ?? context.read<CollectionSource>();
    Navigator.maybeOf(context)?.push(
      MaterialPageRoute(
        builder: (context) => FaceSearchResultPage(
          targetEntry: entry,
          targetFace: face,
          source: source,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!entry.isImage) return const SliverToBoxAdapter(child: SizedBox());

    final theme = Theme.of(context);
    final faces = _faces ?? [];

    Widget content;
    if (_loading) {
      content = const Padding(
        padding: EdgeInsets.all(16),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 12),
              Text('正在识别人脸...', style: TextStyle(fontSize: 14)),
            ],
          ),
        ),
      );
    } else if (!_detected) {
      content = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: OutlinedButton.icon(
          onPressed: _detectFaces,
          icon: const Icon(Icons.face_retouching_natural, size: 20),
          label: const Text('检测并提取此照片中的人脸'),
          style: OutlinedButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
        ),
      );
    } else if (faces.isEmpty) {
      content = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.face_unlock_outlined, color: Colors.grey, size: 20),
            const SizedBox(width: 8),
            const Text('未检测到人脸', style: TextStyle(color: Colors.grey, fontSize: 13)),
            const Spacer(),
            TextButton(
              onPressed: _detectFaces,
              child: const Text('重新检测'),
            ),
          ],
        ),
      );
    } else {
      content = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Wrap(
          spacing: 12,
          runSpacing: 8,
          children: faces.asMap().entries.map((item) {
            final idx = item.key;
            final face = item.value;
            return Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              margin: EdgeInsets.zero,
              elevation: 0,
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FaceAvatar(
                      entry: entry,
                      bounds: face.bounds,
                      size: 48,
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '人脸 #${idx + 1}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        const SizedBox(height: 4),
                        FilledButton.tonalIcon(
                          onPressed: () => _searchByFace(context, face),
                          icon: const Icon(Icons.search, size: 16),
                          label: const Text('以脸搜脸', style: TextStyle(fontSize: 12)),
                          style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      );
    }

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionRow(icon: Icons.face),
            content,
          ],
        ),
      ),
    );
  }
}
