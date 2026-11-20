import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';

void main() {
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: AudioVisualizerScreen(),
  ));
}

class AudioVisualizerScreen extends StatefulWidget {
  const AudioVisualizerScreen({super.key});

  @override
  State<AudioVisualizerScreen> createState() => _AudioVisualizerScreenState();
}

class _AudioVisualizerScreenState extends State<AudioVisualizerScreen> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  final String _audioUrl =
      'https://irsv.upmusics.com/singletracks/2026/11/Ai%20-%20Kash%20Zoodtar%20Baroon%20Miomad%20UpMusics.mp3';

  bool _isPlaying = false;
  bool _isLoading = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  Uint8List? _audioBytes;

  final List<double> _baseHeights = [32, 16, 32, 16, 32, 16, 32, 16, 32, 16];
  late List<double> _currentHeights;

  @override
  void initState() {
    super.initState();
    _currentHeights = List.from(_baseHeights);
    _setupAudio();
  }

  Future<void> _setupAudio() async {
    _audioPlayer.durationStream.listen((d) {
      if (mounted && d != null) {
        setState(() => _duration = d);
      }
    });

    _audioPlayer.positionStream.listen((p) {
      if (!mounted) return;
      setState(() {
        _position = p;
        if (_isPlaying) {
          _updateRealEqualizer(p);
        }
      });
    });

    _audioPlayer.playerStateStream.listen((state) {
      if (!mounted) return;
      final playing = state.playing;
      final completed = state.processingState == ProcessingState.completed;

      setState(() {
        _isPlaying = playing && !completed;
        if (state.processingState == ProcessingState.ready || completed) {
          _isLoading = false;
        }
        if (completed) {
          _audioPlayer.seek(Duration.zero);
          _audioPlayer.pause();
          _currentHeights = List.from(_baseHeights);
        } else if (!_isPlaying) {
          _currentHeights = List.from(_baseHeights);
        }
      });
    });

    _downloadAudioBytes();
  }

  Future<void> _downloadAudioBytes() async {
    try {
      final response = await http.get(Uri.parse(_audioUrl));
      if (response.statusCode == 200 && mounted) {
        setState(() {
          _audioBytes = response.bodyBytes;
        });
      }
    } catch (e) {
      debugPrint('Audio bytes fetch error: $e');
    }
  }

  void _updateRealEqualizer(Duration currentPos) {
    if (_audioBytes == null ||
        _audioBytes!.isEmpty ||
        _duration.inMilliseconds <= 0) {
      return;
    }

    final double progress =
        (currentPos.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0);

    final int centerIndex = (progress * (_audioBytes!.length - 1024)).toInt();
    if (centerIndex < 0 || centerIndex + 1000 >= _audioBytes!.length) return;

    for (int bar = 0; bar < 10; bar++) {
      int sum = 0;
      int start = centerIndex + (bar * 80);
      for (int i = 0; i < 60; i++) {
        int val = _audioBytes![start + i] - 128;
        sum += val.abs();
      }
      double avgAmplitude = (sum / 60.0) / 128.0;

      double dynamicHeight = 8.0 + (pow(avgAmplitude, 0.75) * 32.0);
      _currentHeights[bar] = dynamicHeight.clamp(8.0, 38.0);
    }
  }

  Future<void> _togglePlayPause() async {
    try {
      if (_isPlaying) {
        await _audioPlayer.pause();
      } else {
        setState(() => _isLoading = true);
        if (_audioPlayer.audioSource == null) {
          await _audioPlayer.setUrl(_audioUrl);
        }
        await _audioPlayer.play();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطا در پخش آهنگ: $e')),
      );
    }
  }

  Future<void> _seekToBar(int index) async {
    if (_duration.inMilliseconds > 0) {
      final double targetProgress = (index + 1) / _baseHeights.length;
      final int targetMs = (_duration.inMilliseconds * targetProgress).round();
      await _audioPlayer.seek(Duration(milliseconds: targetMs));
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    double progress = 0.0;
    if (_duration.inMilliseconds > 0) {
      progress = (_position.inMilliseconds / _duration.inMilliseconds)
          .clamp(0.0, 1.0);
    }

    int activeBarsCount = (progress * _baseHeights.length).round();

    return Scaffold(
      backgroundColor: const Color(0xFFFFFFFF),
      body: Center(
        child: SizedBox(
          height: 40,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: _togglePlayPause,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    color: Color(0xFF44B678),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: _isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.2,
                            ),
                          )
                        : Icon(
                            _isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 26,
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: List.generate(_baseHeights.length, (index) {
                  final bool isActive = index < activeBarsCount;

                  return GestureDetector(
                    onTap: () => _seekToBar(index),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 90),
                      curve: Curves.easeOut,
                      width: 4,
                      height: _currentHeights[index],
                      margin: EdgeInsets.only(
                        right: index < _baseHeights.length - 1 ? 4 : 0,
                      ),
                      decoration: BoxDecoration(
                        color: isActive
                            ? const Color(0xFF44B678)
                            : const Color(0xFFF0F0F0),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  );
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
