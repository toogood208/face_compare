import 'dart:math';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

class FaceComparator {
  late Interpreter _interpreter;
  static const String modelPath = 'assets/moble_face_two.tflite';
  static const int inputSize = 112;

  final double _sameDistanceThreshold = 0.9;
  final double _sameCosineThreshold = 0.75;

  late int _embeddingSize;

  Future<void> loadModel() async {
    try {
      final options = InterpreterOptions();
      _interpreter = await Interpreter.fromAsset(modelPath, options: options);
      _interpreter.allocateTensors();

      final outputTensor = _interpreter.getOutputTensor(0);

      final outShape = outputTensor.shape;
      _embeddingSize = outShape.length > 1 ? outShape[1] : outShape[0];
    } catch (e) {
      rethrow;
    }
  }

  Future<ComparisonResult> compareFaces(
    Uint8List image1Bytes,
    Uint8List image2Bytes,
  ) async {
    final emb1 = await _getEmbedding(image1Bytes);
    final emb2 = await _getEmbedding(image2Bytes);

    final cosine = _cosineSimilarity(emb1, emb2);
    final distance = _euclideanDistance(emb1, emb2);

    double cosineNorm = ((cosine - 0.5) / 0.5);
    if (cosineNorm < 0) cosineNorm = 0;
    if (cosineNorm > 1) cosineNorm = 1;

    double distanceNorm = ((1.2 - distance) / 1.2);
    if (distanceNorm < 0) distanceNorm = 0;
    if (distanceNorm > 1) distanceNorm = 1;

    final hybridScore = (0.6 * cosineNorm + 0.4 * distanceNorm).clamp(0.0, 1.0);
    final confidence = (0.65 * cosineNorm + 0.35 * distanceNorm).clamp(
      0.0,
      1.0,
    );
    final explanation = _generateExplanation(distance, cosine);

    return ComparisonResult(
      hybridScore,
      confidence,
      explanation,
      cosine,
      distance,
    );
  }

  Future<Float32List> _getEmbedding(Uint8List imageBytes) async {
    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) throw Exception('Unable to decode image');

    final resized = img.copyResize(
      decoded,
      width: inputSize,
      height: inputSize,
    );

    final input = List.generate(1, (_) {
      return List.generate(inputSize, (y) {
        return List.generate(inputSize, (x) {
          final pixel = resized.getPixel(x, y);
          final r = pixel.r / 255.0;
          final g = pixel.g / 255.0;
          final b = pixel.b / 255.0;
          return [r, g, b];
        });
      });
    });

    final output = List.generate(1, (_) => List.filled(_embeddingSize, 0.0));
    _interpreter.run(input, output);

    final embedding = Float32List.fromList(
      output[0].map((e) => e.toDouble()).toList(),
    );
    return _l2Normalize(embedding);
  }

  Float32List _l2Normalize(Float32List vec) {
    double sum = 0.0;
    for (int i = 0; i < vec.length; i++) {
      sum += vec[i] * vec[i];
    }
    final norm = sqrt(sum);
    if (norm == 0) return vec;
    final out = Float32List(vec.length);
    for (int i = 0; i < vec.length; i++) {
      out[i] = vec[i] / norm;
    }
    return out;
  }

  double _cosineSimilarity(Float32List a, Float32List b) {
    double dot = 0.0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
    }
    return dot;
  }

  double _euclideanDistance(Float32List a, Float32List b) {
    double sum = 0.0;
    for (int i = 0; i < a.length; i++) {
      final d = a[i] - b[i];
      sum += d * d;
    }
    return sqrt(sum);
  }

  String _generateExplanation(double distance, double cosine) {
    if (distance < _sameDistanceThreshold && cosine > _sameCosineThreshold) {
      return 'High confidence: Very likely the same person';
    }

    if (distance < 1.05 && cosine > 0.70) {
      return 'Moderate confidence: Likely the same person';
    }

    if (distance < 1.2 && cosine > 0.65) {
      return 'Low confidence: Possibly the same person (needs manual review)';
    }

    if (distance < 1.4 && cosine > 0.60) {
      return 'Uncertain: Not enough agreement — treat as different unless additional evidence';
    }

    return 'High confidence: Very likely different persons';
  }
}

class ComparisonResult {
  final double score;
  final double confidence;
  final String explanation;
  final double cosine;
  final double distance;

  ComparisonResult(
    this.score,
    this.confidence,
    this.explanation,
    this.cosine,
    this.distance,
  );
}
