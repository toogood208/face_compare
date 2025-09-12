import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:face_compare/face_capture_screen.dart';
import 'package:face_compare/face_comparator.dart';
import 'package:flutter/material.dart';

class FaceComparisonScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const FaceComparisonScreen({super.key, required this.cameras});

  @override
  State<FaceComparisonScreen> createState() => _FaceComparisonScreenState();
}

class _FaceComparisonScreenState extends State<FaceComparisonScreen> {
  Uint8List? _image1Bytes;
  Uint8List? _image2Bytes;
  ComparisonResult? _result;
  bool _isLoading = false;
  final _faceComparator = FaceComparator();

  @override
  void initState() {
    super.initState();
    _initializeModel();
  }

  Future<void> _initializeModel() async {
    setState(() => _isLoading = true);
    await _faceComparator.loadModel();
    setState(() => _isLoading = false);
  }

  Future<void> _pickImage(bool isFirstImage) async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (context) => FaceCaptureScreen(
              cameras: widget.cameras,
              title:
                  isFirstImage ? 'Capture First Face' : 'Capture Second Face',
            ),
      ),
    );

    if (result != null && result is Uint8List) {
      setState(() {
        if (isFirstImage) {
          _image1Bytes = result;
        } else {
          _image2Bytes = result;
        }
        _result = null;
      });
    }
  }

  Future<void> _compareFaces() async {
    if (_image1Bytes == null || _image2Bytes == null) return;

    setState(() => _isLoading = true);
    try {
      final result = await _faceComparator.compareFaces(
        _image1Bytes!,
        _image2Bytes!,
      );
      setState(() => _result = result);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Face Comparison')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildImageSelectors(),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed:
                  (_image1Bytes != null && _image2Bytes != null && !_isLoading)
                      ? _compareFaces
                      : null,
              child:
                  _isLoading
                      ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                      : const Text('Compare Faces'),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () {
                setState(() {
                  _result = null;
                  _image1Bytes = null;
                  _image2Bytes = null;
                });
              },
              child: const Text('Clear Results'),
            ),
            const SizedBox(height: 20),
            Expanded(child: _buildResultsSection()),
          ],
        ),
      ),
    );
  }

  Widget _buildImageSelectors() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _buildImageContainer(_image1Bytes, true),
        _buildImageContainer(_image2Bytes, false),
      ],
    );
  }

  Widget _buildImageContainer(Uint8List? imageBytes, bool isFirst) {
    return Column(
      children: [
        Container(
          width: 150,
          height: 150,
          decoration: BoxDecoration(border: Border.all(color: Colors.grey)),
          child:
              imageBytes != null
                  ? Image.memory(imageBytes, fit: BoxFit.cover)
                  : const Center(child: Icon(Icons.image, size: 50)),
        ),
        TextButton(
          onPressed: () => _pickImage(isFirst),
          child: Text('Capture ${isFirst ? 'First' : 'Second'} Face'),
        ),
      ],
    );
  }

  Widget _buildResultsSection() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_result == null) return const SizedBox();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Hybrid Similarity Score: ${_result!.score.toStringAsFixed(4)}',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          Text(
            'Confidence: ${(_result!.confidence * 100).toStringAsFixed(1)}%',
            style: TextStyle(
              fontSize: 16,
              color:
                  _result!.confidence > 0.7
                      ? Colors.green
                      : _result!.confidence < 0.4
                      ? Colors.red
                      : Colors.orange,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cosine similarity: ${_result!.cosine.toStringAsFixed(4)}',
                ),
                Text(
                  'Euclidean distance: ${_result!.distance.toStringAsFixed(4)}',
                ),
                Text('Hybrid score: ${_result!.score.toStringAsFixed(4)}'),
                Text(
                  'Confidence: ${(_result!.confidence * 100).toStringAsFixed(1)}%',
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _result!.explanation,
              style: const TextStyle(fontSize: 16),
            ),
          ),
          const SizedBox(height: 15),
          _buildSimilarityIndicator(_result!.score),
        ],
      ),
    );
  }

  Widget _buildSimilarityIndicator(double score) {
    return SizedBox(
      height: 30,
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.red, Colors.orange, Colors.green],
                stops: const [0.0, 0.5, 1.0],
              ),
              borderRadius: BorderRadius.circular(15),
            ),
          ),
          Positioned(
            left: (MediaQuery.of(context).size.width - 32) * score,
            child: Container(width: 4, height: 40, color: Colors.black),
          ),
        ],
      ),
    );
  }
}