import 'dart:io';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:sensors_plus/sensors_plus.dart';
import '../services/storage_service.dart';
import '../models/media_item.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isInitialized = false;
  bool _isRecording = false;
  bool _isFrontCamera = false;
  bool _isVideoMode = false; // false = photo mode, true = video mode
  bool _showFlash = false;
  final StorageService _storageService = StorageService();

  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  int _deviceOrientation = 0; // 0, 90, 180, 270
  String _orientationString = 'Portrait (0°)';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
    _storageService.initialize();
    _startOrientationDetection();
  }

  void _startOrientationDetection() {
    _accelerometerSubscription = accelerometerEventStream().listen((AccelerometerEvent event) {
      final int newOrientation = _calculateOrientation(event.x, event.y);
      if (newOrientation != _deviceOrientation) {
        setState(() {
          _deviceOrientation = newOrientation;
          _orientationString = _getOrientationStringFromDegrees(newOrientation);
        });
      }
    });
  }

  int _calculateOrientation(double x, double y) {
    // Calculate orientation based on accelerometer values
    // x and y represent tilt in those directions
    final angle = math.atan2(y, x) * 180 / math.pi;

    // Convert angle to orientation (inverted by 180°, so we flip the mapping)
    if (angle >= -135 && angle < -45) {
      return 180; // Portrait down (upside down)
    } else if (angle >= -45 && angle < 45) {
      return 90; // Landscape left (device rotated left)
    } else if (angle >= 45 && angle < 135) {
      return 0; // Portrait up (normal)
    } else {
      return 270; // Landscape right (device rotated right)
    }
  }

  String _getOrientationStringFromDegrees(int degrees) {
    switch (degrees) {
      case 0:
        return 'Portrait (0°)';
      case 90:
        return 'Landscape Left (90°)';
      case 180:
        return 'Portrait Down (180°)';
      case 270:
        return 'Landscape Right (270°)';
      default:
        return 'Unknown ($degrees°)';
    }
  }

  double _getPreviewRotation() {
    // No rotation needed - camera handles orientation internally
    return 0.0;
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();

      if (_cameras!.isEmpty) {
        return;
      }

      await _setupCamera(_isFrontCamera ? 1 : 0);
    } catch (e) {
      debugPrint('Error initializing camera: $e');
    }
  }

  Future<void> _setupCamera(int cameraIndex) async {
    if (_cameras == null || _cameras!.isEmpty) return;

    // Ensure index is valid
    if (cameraIndex >= _cameras!.length) {
      cameraIndex = 0;
    }

    _controller = CameraController(
      _cameras![cameraIndex],
      ResolutionPreset.high,
      enableAudio: true,
    );

    try {
      await _controller!.initialize();
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      debugPrint('Error setting up camera: $e');
    }
  }

  Future<void> _takePicture() async {
    if (_controller == null || !_controller!.value.isInitialized) {
      return;
    }

    // Show flash immediately for visual feedback
    setState(() {
      _showFlash = true;
    });

    // Hide flash after brief delay
    Future.delayed(const Duration(milliseconds: 150), () {
      if (mounted) {
        setState(() {
          _showFlash = false;
        });
      }
    });

    try {
      final tempDir = await getTemporaryDirectory();
      final filePath = path.join(
        tempDir.path,
        '${DateTime.now().millisecondsSinceEpoch}.jpg',
      );

      final image = await _controller!.takePicture();
      final file = File(image.path);

      // Save encrypted
      await _storageService.saveMedia(
        file: file,
        type: MediaType.photo,
      );

      // Delete temp file
      await file.delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Photo saved securely')),
        );
      }
    } catch (e) {
      debugPrint('Error taking picture: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _toggleRecording() async {
    if (_controller == null || !_controller!.value.isInitialized) {
      return;
    }

    try {
      // Check actual camera state, not just our flag
      if (_controller!.value.isRecordingVideo) {
        // Stop recording
        final video = await _controller!.stopVideoRecording();
        final file = File(video.path);

        setState(() {
          _isRecording = false;
        });

        // Save encrypted
        await _storageService.saveMedia(
          file: file,
          type: MediaType.video,
        );

        // Delete temp file
        await file.delete();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Video saved securely')),
          );
        }
      } else {
        // Start recording
        setState(() {
          _isRecording = true;
        });

        await _controller!.startVideoRecording();
      }
    } catch (e) {
      debugPrint('Error recording video: $e');
      setState(() {
        _isRecording = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras == null || _cameras!.length < 2) return;

    setState(() {
      _isFrontCamera = !_isFrontCamera;
      _isInitialized = false;
    });

    await _controller?.dispose();
    await _setupCamera(_isFrontCamera ? 1 : 0);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _accelerometerSubscription?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      _controller?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _setupCamera(_isFrontCamera ? 1 : 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Camera'),
        actions: [
          if (_cameras != null && _cameras!.length > 1)
            IconButton(
              icon: const Icon(Icons.flip_camera_android),
              onPressed: _switchCamera,
            ),
        ],
      ),
      body: _isInitialized
          ? Stack(
              children: [
                // Camera preview with orientation correction
                SizedBox.expand(
                  child: Transform.rotate(
                    angle: _getPreviewRotation() * math.pi / 180,
                    child: CameraPreview(_controller!),
                  ),
                ),

                // Flash overlay
                if (_showFlash)
                  Positioned.fill(
                    child: Container(
                      color: Colors.white.withOpacity(0.6),
                    ),
                  ),

                // Recording indicator
                if (_isVideoMode && _isRecording)
                  Positioned(
                    top: 16,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.fiber_manual_record, color: Colors.white),
                            SizedBox(width: 8),
                            Text(
                              'Recording',
                              style: TextStyle(color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),


                // Mode indicator
                Positioned(
                  bottom: 120,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _isVideoMode ? 'VIDEO MODE' : 'PHOTO MODE',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),

                // Controls
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(32),
                    color: Colors.black54,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // Mode switcher button
                        IconButton(
                          icon: Icon(
                            _isVideoMode ? Icons.photo_camera : Icons.videocam,
                            color: Colors.white,
                            size: 32,
                          ),
                          onPressed: _isRecording ? null : () {
                            setState(() {
                              _isVideoMode = !_isVideoMode;
                            });
                          },
                        ),

                        // Main capture button
                        GestureDetector(
                          onTap: _isVideoMode ? _toggleRecording : _takePicture,
                          child: Container(
                            width: 70,
                            height: 70,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 4),
                              color: Colors.transparent,
                            ),
                            child: Container(
                              margin: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                shape: _isRecording ? BoxShape.rectangle : BoxShape.circle,
                                color: _isRecording ? Colors.red : Colors.white,
                                borderRadius: _isRecording ? BorderRadius.circular(4) : null,
                              ),
                            ),
                          ),
                        ),

                        // Spacer for symmetry
                        const SizedBox(width: 32),
                      ],
                    ),
                  ),
                ),
              ],
            )
          : const Center(
              child: CircularProgressIndicator(),
            ),
    );
  }
}
