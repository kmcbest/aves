import 'dart:math';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/face/face_row.dart';
import 'package:aves/model/source/collection_source.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves/services/face_service.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

final FaceManager faceManager = FaceManager._private();

class FaceMatch {
  final AvesEntry entry;
  final FaceRow face;
  final double similarity;

  const new({
    required this.entry,
    required this.face,
    required this.similarity,
  });
}

class FaceManager {
  new _private();

  bool _initialized = false;
  // Map of entryId -> List<FaceRow>
  final Map<int, List<FaceRow>> _facesByEntryId = {};

  Future<void> init() async {
    if (_initialized) return;
    try {
      final allFaces = await localMediaDb.loadAllFaces();
      _facesByEntryId.clear();
      for (final face in allFaces) {
        _facesByEntryId.putIfAbsent(face.entryId, () => []).add(face);
      }
      _initialized = true;
      debugPrint('FaceManager initialized with ${_facesByEntryId.length} entries containing faces');
    } catch (e, stack) {
      debugPrint('FaceManager init failed: $e\n$stack');
    }
  }

  /// Get faces for an entry: checks cache first, then DB.
  /// If [detectIfMissing] is true and not found, runs ML Kit detection + MobileFaceNet inference
  /// and persists results to DB.
  Future<List<FaceRow>> getFaces(AvesEntry entry, {bool detectIfMissing = false}) async {
    if (!_initialized) await init();
    if (_facesByEntryId.containsKey(entry.id)) {
      return _facesByEntryId[entry.id]!;
    }

    final dbFaces = await localMediaDb.loadFacesByEntryId(entry.id);
    if (dbFaces.isNotEmpty) {
      _facesByEntryId[entry.id] = dbFaces;
      return dbFaces;
    }

    if (!detectIfMissing) return [];

    final detections = await FaceService.detectFaces(entry);
    await localMediaDb.saveFaces(entry.id, detections);
    final saved = await localMediaDb.loadFacesByEntryId(entry.id);
    _facesByEntryId[entry.id] = saved;
    return saved;
  }

  /// Find matches for [targetEmbedding] across all indexed entries in [source].
  List<FaceMatch> findSimilarFaces(
    Float32List targetEmbedding,
    CollectionSource source, {
    double threshold = 0.68,
    int? excludeEntryId,
  }) {
    final matches = <FaceMatch>[];
    for (final entryId in _facesByEntryId.keys) {
      if (entryId == excludeEntryId) continue;
      final entry = source.visibleEntries.firstWhereOrNull((e) => e.id == entryId);
      if (entry == null) continue;

      final faces = _facesByEntryId[entryId]!;
      for (final face in faces) {
        final sim = FaceService.cosineSimilarity(targetEmbedding, face.embedding);
        if (sim >= threshold) {
          matches.add(FaceMatch(entry: entry, face: face, similarity: sim));
          break; // one match per entry
        }
      }
    }
    matches.sort((a, b) => b.similarity.compareTo(a.similarity));
    return matches;
  }

  /// Compute normalized centroid of a list of unit embeddings
  Float32List computeCentroid(List<Float32List> embeddings) {
    if (embeddings.isEmpty) return Float32List(192);
    final centroid = Float64List(192);
    for (final emb in embeddings) {
      for (int i = 0; i < 192; i++) {
        centroid[i] += emb[i];
      }
    }
    double sumSq = 0.0;
    for (int i = 0; i < 192; i++) {
      sumSq += centroid[i] * centroid[i];
    }
    final norm = sqrt(sumSq);
    final result = Float32List(192);
    if (norm > 0) {
      for (int i = 0; i < 192; i++) {
        result[i] = (centroid[i] / norm).toDouble();
      }
    }
    return result;
  }

  /// Scan a set of entries in the background, detecting and storing faces.
  /// Reports progress via [onProgress] (current, total).
  Future<void> scanEntries(
    List<AvesEntry> entries, {
    void Function(int current, int total)? onProgress,
  }) async {
    int count = 0;
    final total = entries.length;
    for (final entry in entries) {
      if (!_facesByEntryId.containsKey(entry.id)) {
        await getFaces(entry, detectIfMissing: true);
      }
      count++;
      onProgress?.call(count, total);
    }
  }
}
