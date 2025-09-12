import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'dart:io';
import 'package:screen_brightness/screen_brightness.dart';

enum LivenessStep { align, blink, smile, done }

class FaceCaptureScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  final String title;

  const FaceCaptureScreen({
    super.key,
    required this.cameras,
    required this.title,
  });

  @override
  State<FaceCaptureScreen> createState() => _FaceCaptureScreenState();
}

class _FaceCaptureScreenState extends State<FaceCaptureScreen> {
  CameraController? _controller;
  bool _isInitialized = false;
  late FaceDetector _faceDetector;
  bool _faceDetected = false;
  bool _faceAligned = false;
  Size _imageSize = Size.zero;
  bool _isFrontCamera = true;
  double? _previousBrightness; // Store original brightness

  bool _blinked = false;
  bool _smileConfirmed = false;
  LivenessStep _currentStep = LivenessStep.align;

  // For dynamic rotation
  final Map<DeviceOrientation, int> _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _setMaxBrightness();
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableClassification: true,
        enableLandmarks: true,
        enableContours: false,
        performanceMode: FaceDetectorMode.fast,
      ),
    );
  }

  Future<void> _setMaxBrightness() async {
    try {
      _previousBrightness = await ScreenBrightness().current;
      await ScreenBrightness().setScreenBrightness(1.0);
      print('Brightness set to max');
    } catch (e) {
      print("Brightness error: $e");
    }
  }

  Future<void> _restoreBrightness() async {
    if (_previousBrightness != null) {
      try {
        await ScreenBrightness().setScreenBrightness(_previousBrightness!);
        print('Brightness restored to $_previousBrightness');
      } catch (e) {
        print("Restore brightness error: $e");
      }
    }
  }

  Future<void> _initializeCamera() async {
    if (widget.cameras.isEmpty) return;

    final frontCamera = widget.cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => widget.cameras.first,
    );

    _isFrontCamera = frontCamera.lensDirection == CameraLensDirection.front;

    _controller = CameraController(
      frontCamera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.nv21,
    );

    try {
      await _controller!.initialize();
      await _controller!.startImageStream(_processCameraImage);
      setState(() => _isInitialized = true);
    } catch (e) {
      print('Camera error: $e');
    }
  }

  InputImageRotation _getImageRotation() {
    final camera = _controller!.description;
    final sensorOrientation = camera.sensorOrientation;
    DeviceOrientation? deviceOrientation = _controller!.value.deviceOrientation;

    InputImageRotation? rotation;
    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else if (Platform.isAndroid) {
      int? rotationCompensation = _orientations[deviceOrientation];
      if (rotationCompensation == null) return InputImageRotation.rotation0deg;
      if (_isFrontCamera) {
        rotationCompensation = (sensorOrientation + rotationCompensation) % 360;
      } else {
        rotationCompensation =
            (sensorOrientation - rotationCompensation + 360) % 360;
      }
      rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
    }
    print(
      'Computed rotation: $rotation (sensor: $sensorOrientation, device: $deviceOrientation)',
    );
    return rotation ?? InputImageRotation.rotation270deg;
  }

  Future<void> _processCameraImage(CameraImage image) async {
    if (!mounted) return;

    try {
      final inputImage = _convertToInputImage(image);
      if (inputImage == null) {
        print('Failed to convert InputImage');
        return;
      }

      _imageSize = Size(image.width.toDouble(), image.height.toDouble());
      final faces = await _faceDetector.processImage(inputImage);

      if (mounted) {
        setState(() {
          _faceDetected = faces.isNotEmpty;

          if (faces.isNotEmpty) {
            final face = faces.first;
            final screenSize = MediaQuery.of(context).size;
            final previewSize = _controller!.value.previewSize!;
            print('Preview size: ${previewSize.width}x${previewSize.height}');

            final rotation = _getImageRotation();
            final transformedRect = _transformRect(
              face.boundingBox,
              _imageSize,
              screenSize,
              rotation,
              _isFrontCamera,
            );

            _faceAligned = _checkSimpleAlignment(transformedRect, screenSize);

            // -----------------------------
            // NEW: Step progression logic
            // -----------------------------
            if (_faceAligned) {
              switch (_currentStep) {
                case LivenessStep.align:
                  _currentStep = LivenessStep.blink;
                  break;

                case LivenessStep.blink:
                  final leftEyeOpen = face.leftEyeOpenProbability ?? 1.0;
                  final rightEyeOpen = face.rightEyeOpenProbability ?? 1.0;

                  if (!_blinked && leftEyeOpen < 0.4 && rightEyeOpen < 0.4) {
                    _blinked = true; // eyes closed
                  }

                  if (_blinked && leftEyeOpen > 0.6 && rightEyeOpen > 0.6) {
                    _currentStep = LivenessStep.smile;
                  }
                  break;

                case LivenessStep.smile:
                  final smileProb = face.smilingProbability ?? 0.0;
                  // Only proceed if a NEW smile happens
                  if (!_smileConfirmed && smileProb > 0.7) {
                    _smileConfirmed = true;
                    _currentStep = LivenessStep.done;
                  }
                  break;

                case LivenessStep.done:
                  // Ready to capture
                  break;
              }
            }
          } else {
            _faceAligned = false;
          }
        });
      }
    } catch (e) {
      print("Face detection error: $e");
    }
  }

  String _getInstruction() {
    switch (_currentStep) {
      case LivenessStep.align:
        return "Align your face in the oval";
      case LivenessStep.blink:
        return "Please blink 👀";
      case LivenessStep.smile:
        return "Now, give us a smile 😁";
      case LivenessStep.done:
        return "Perfect! Tap the button to capture";
    }
  }

  InputImage? _convertToInputImage(CameraImage image) {
    try {
      final WriteBuffer allBytes = WriteBuffer();
      for (Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      final rotation = _getImageRotation();

      final inputImageData = InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: InputImageFormat.nv21,
        bytesPerRow: image.planes.first.bytesPerRow,
      );

      return InputImage.fromBytes(bytes: bytes, metadata: inputImageData);
    } catch (e) {
      print("InputImage conversion error: $e");
      return null;
    }
  }

  Rect _transformRect(
    Rect rawRect,
    Size imageSize,
    Size screenSize,
    InputImageRotation rotation,
    bool isFrontCamera,
  ) {
    final rotatedRect = _rotateRect(rawRect, imageSize, rotation);
    final rotatedImageSize = _getRotatedSize(imageSize, rotation);
    print(
      'Image size: ${imageSize.width}x${imageSize.height}, Rotated size: ${rotatedImageSize.width}x${rotatedImageSize.height}',
    );

    final scaleX = screenSize.width / rotatedImageSize.width;
    final scaleY = screenSize.height / rotatedImageSize.height;
    final scaledRect = Rect.fromLTWH(
      rotatedRect.left * scaleX,
      rotatedRect.top * scaleY,
      rotatedRect.width * scaleX,
      rotatedRect.height * scaleY,
    );

    Rect finalRect;
    if (isFrontCamera) {
      finalRect = Rect.fromLTWH(
        screenSize.width - scaledRect.right,
        scaledRect.top,
        scaledRect.width,
        scaledRect.height,
      );
    } else {
      finalRect = scaledRect;
    }

    return finalRect;
  }

  Size _getRotatedSize(Size size, InputImageRotation rotation) {
    switch (rotation) {
      case InputImageRotation.rotation0deg:
      case InputImageRotation.rotation180deg:
        return size;
      case InputImageRotation.rotation90deg:
      case InputImageRotation.rotation270deg:
        return Size(size.height, size.width);
    }
  }

  Rect _rotateRect(Rect rect, Size imageSize, InputImageRotation rotation) {
    final width = imageSize.width;
    final height = imageSize.height;
    final left = rect.left;
    final top = rect.top;
    final right = rect.right;
    final bottom = rect.bottom;

    switch (rotation) {
      case InputImageRotation.rotation0deg:
        return rect;
      case InputImageRotation.rotation90deg:
        return Rect.fromLTWH(top, width - right, rect.height, rect.width);
      case InputImageRotation.rotation180deg:
        return Rect.fromLTWH(
          width - right,
          height - bottom,
          rect.width,
          rect.height,
        );
      case InputImageRotation.rotation270deg:
        return Rect.fromLTWH(height - bottom, left, rect.height, rect.width);
    }
  }

  bool _checkSimpleAlignment(Rect faceRect, Size screenSize) {
    final faceCenterX = faceRect.left + faceRect.width / 2;
    final faceCenterY = faceRect.top + faceRect.height / 2;

    final imageWidth = screenSize.width;
    final imageHeight = screenSize.height;

    final centerXMin = imageWidth * 0.2;
    final centerXMax = imageWidth * 0.8;
    final centerYMin = imageHeight * 0.2;
    final centerYMax = imageHeight * 0.8;

    final minSize = imageWidth * 0.15;
    final maxSize = imageWidth * 0.7;

    final isInCenter =
        faceCenterX >= centerXMin &&
        faceCenterX <= centerXMax &&
        faceCenterY >= centerYMin &&
        faceCenterY <= centerYMax;

    final isGoodSize = faceRect.width >= minSize && faceRect.width <= maxSize;

    print("Screen: ${imageWidth}x${imageHeight}");
    print("Face center: (${faceCenterX.toInt()}, ${faceCenterY.toInt()})");
    print("Face size: ${faceRect.width.toInt()}x${faceRect.height.toInt()}");
    print("In center: $isInCenter, Good size: $isGoodSize");
    print(
      "Expected center: ${centerXMin.toInt()}-${centerXMax.toInt()}, ${centerYMin.toInt()}-${centerYMax.toInt()}",
    );
    print("Expected size: ${minSize.toInt()}-${maxSize.toInt()}");
    print("---");

    return isInCenter && isGoodSize;
  }

  @override
  void dispose() {
    _restoreBrightness();
    _controller?.dispose();
    _faceDetector.close();
    super.dispose();
  }

  Future<void> _captureImage() async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    try {
      final XFile image = await _controller!.takePicture();
      final Uint8List imageBytes = await image.readAsBytes();
      Navigator.of(context).pop(imageBytes);
    } catch (e) {
      print('Capture error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body:
          _isInitialized
              ? Stack(
                children: [
                  Positioned.fill(child: CameraPreview(_controller!)),
                  Positioned.fill(
                    child: CustomPaint(
                      painter: SimpleOvalGuide(
                        isAligned: _faceAligned,
                        faceDetected: _faceDetected,
                      ),
                    ),
                  ),
                  Positioned(
                    top: 20,
                    left: 20,
                    right: 20,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _getInstruction(),
                        style: TextStyle(
                          color:
                              _faceDetected
                                  ? (_faceAligned
                                      ? Colors.green
                                      : Colors.orange)
                                  : Colors.red,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 50,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: GestureDetector(
                        onTap:
                            _currentStep == LivenessStep.done
                                ? _captureImage
                                : null,
                        child: Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color:
                                (_faceDetected && _faceAligned)
                                    ? Colors.white
                                    : Colors.grey,
                            border: Border.all(color: Colors.white, width: 4),
                          ),
                          child: Icon(
                            Icons.camera_alt,
                            size: 40,
                            color:
                                (_faceDetected && _faceAligned)
                                    ? Colors.black
                                    : Colors.white54,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              )
              : const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
    );
  }
}

class SimpleOvalGuide extends CustomPainter {
  final bool isAligned;
  final bool faceDetected;

  SimpleOvalGuide({required this.isAligned, required this.faceDetected});

  @override
  void paint(Canvas canvas, Size size) {
    // Opaque white overlay
    final overlayPaint = Paint()..color = Colors.white; // Fully opaque white

    final center = Offset(size.width / 2, size.height / 2);
    final headWidth = size.width * 0.5;
    final headHeight = size.height * 0.75;

    // Head-shaped path
    final headPath = Path();
    final headRect = Rect.fromCenter(
      center: center,
      width: headWidth,
      height: headHeight,
    );
    final top = headRect.top;
    final bottom = headRect.bottom;
    final left = headRect.left;
    final right = headRect.right;
    final cheekY = top + headHeight * 0.4;
    final chinY = bottom - headHeight * 0.1;
    final foreheadY = top + headHeight * 0.15;

    headPath.moveTo(center.dx, top);
    headPath.quadraticBezierTo(left + headWidth * 0.2, foreheadY, left, cheekY);
    headPath.quadraticBezierTo(
      left + headWidth * 0.1,
      chinY,
      center.dx,
      bottom,
    );
    headPath.quadraticBezierTo(right - headWidth * 0.1, chinY, right, cheekY);
    headPath.quadraticBezierTo(
      right - headWidth * 0.2,
      foreheadY,
      center.dx,
      top,
    );
    headPath.close();

    // Overlay: everything except head shape
    final fullPath =
        Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final overlayPath = Path.combine(
      PathOperation.difference,
      fullPath,
      headPath,
    );
    canvas.drawPath(overlayPath, overlayPaint);

    // Head border
    final borderPaint =
        Paint()
          ..color =
              faceDetected
                  ? (isAligned ? Colors.green : Colors.red)
                  : Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4.0;
    canvas.drawPath(headPath, borderPaint);

    // Center crosshairs
    final crossPaint =
        Paint()
          ..color = borderPaint.color.withOpacity(0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0;
    canvas.drawLine(
      Offset(center.dx - 30, center.dy),
      Offset(center.dx + 30, center.dy),
      crossPaint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - 30),
      Offset(center.dx, center.dy + 30),
      crossPaint,
    );
  }

  @override
  bool shouldRepaint(SimpleOvalGuide oldDelegate) {
    return oldDelegate.isAligned != isAligned ||
        oldDelegate.faceDetected != faceDetected;
  }
}
