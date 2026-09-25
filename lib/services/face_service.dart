import 'dart:typed_data';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/services/common/channel.dart';
import 'package:aves/services/common/services.dart';
import 'package:flutter/services.dart';

class FaceDetection {
  final Rect bounds; // Normalized [0..1] bounds relative to image
  final Float32List embedding; // 192-dimensional normalized feature vector

  const new({
    required this.bounds,
    required this.embedding,
  });

  factory fromMap(Map map) {
    final rawBounds = (map['bounds'] as List).cast<num>();
    final rawEmbedding = (map['embedding'] as List).cast<num>();
    return FaceDetection(
      bounds: Rect.fromLTRB(
        rawBounds[0].toDouble(),
        rawBounds[1].toDouble(),
        rawBounds[2].toDouble(),
        rawBounds[3].toDouble(),
      ),
      embedding: Float32List.fromList(rawEmbedding.map((e) => e.toDouble()).toList()),
    );
  }
}

class FaceService {
  static const _platform = AvesMethodChannel('deckers.thibault/aves/face');

  static Future<List<FaceDetection>> detectFaces(AvesEntry entry) async {
    try {
      final res = await _platform.invokeMethod<List>('detectFaces', <String, dynamic>{
        'uri': entry.uri,
        'path': entry.path,
        'mimeType': entry.mimeType,
      });
      if (res == null) return [];
      return res.cast<Map>().map(FaceDetection.fromMap).toList();
    } on PlatformException catch (e, stack) {
      await reportService.recordError(e, stack);
      rethrow;
    }
  }

  /// Calculates cosine similarity between two unit-normalized 192D embeddings.
  /// Returns a value between -1.0 and 1.0 (typically > 0.65 indicates same person).
  static double cosineSimilarity(Float32List a, Float32List b) {
    if (a.length != b.length) return 0.0;
    double dot = 0.0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
    }
    return dot;
  }
}
