import 'dart:typed_data';
import 'dart:ui';
import 'package:aves/services/face_service.dart';

class FaceRow {
  final int id;
  final int entryId;
  final Rect bounds;
  final Float32List embedding;

  const new({
    required this.id,
    required this.entryId,
    required this.bounds,
    required this.embedding,
  });

  factory fromMap(Map<String, dynamic> map) {
    final rawEmbedding = map['embedding'] as Uint8List;
    final embedding = Float32List.view(
      rawEmbedding.buffer,
      rawEmbedding.offsetInBytes,
      rawEmbedding.lengthInBytes ~/ 4,
    );
    return FaceRow(
      id: map['id'] as int,
      entryId: map['entryId'] as int,
      bounds: Rect.fromLTRB(
        (map['xMin'] as num).toDouble(),
        (map['yMin'] as num).toDouble(),
        (map['xMax'] as num).toDouble(),
        (map['yMax'] as num).toDouble(),
      ),
      embedding: embedding,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != 0) 'id': id,
      'entryId': entryId,
      'xMin': bounds.left,
      'yMin': bounds.top,
      'xMax': bounds.right,
      'yMax': bounds.bottom,
      'embedding': embedding.buffer.asUint8List(embedding.offsetInBytes, embedding.lengthInBytes),
    };
  }

  FaceDetection toDetection() {
    return FaceDetection(
      bounds: bounds,
      embedding: embedding,
    );
  }
}
