import 'package:face_compare/face_comparism_screen.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  runApp(FaceComparisonApp(cameras: cameras));
}

class FaceComparisonApp extends StatelessWidget {
  final List<CameraDescription> cameras;

  const FaceComparisonApp({super.key, required this.cameras});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Biometric Face Comparison',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: FaceComparisonScreen(cameras: cameras),
      debugShowCheckedModeBanner: false,
    );
  }
}

// Rest of your existing classes remain the same...
