import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final soundServiceProvider = Provider<SoundService>((ref) {
  final service = SoundService();
  return service;
});

class SoundService {
  AudioPlayer? _buttonPlayer;
  AudioPlayer? _gesturePlayer;
  AudioPlayer? _dialogPlayer;
  bool _isInitialized = false;
  bool _isSupported = true;

  int _lastButtonClick = 0;
  int _lastGestureClick = 0;
  int _lastDialogShow = 0;
  static const int _minInterval = 80; // ms

  SoundService() {
    _initPlayers();
  }

  Future<void> _initPlayers() async {
    if (!_isSupported) return;

    try {
      _buttonPlayer = AudioPlayer();
      _gesturePlayer = AudioPlayer();
      _dialogPlayer = AudioPlayer();
      _isInitialized = true;
    } catch (e) {
      debugPrint('Failed to initialize audio players: $e');
      _isSupported = false;
    }
  }

  Future<void> preload() async {
    if (!_isSupported || !_isInitialized) return;

    try {
      await _buttonPlayer?.setSource(AssetSource('sounds/button_tap.mp3'));
      await _gesturePlayer?.setSource(AssetSource('sounds/button_tap.mp3'));
      await _dialogPlayer?.setSource(AssetSource('sounds/button_tap.mp3'));
    } catch (e) {
      debugPrint('Failed to preload sounds: $e');
      _isSupported = false;
    }
  }

  void buttonTap() {
    if (!_isSupported || !_isInitialized) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastButtonClick < _minInterval) return;
    _lastButtonClick = now;

    try {
      _buttonPlayer?.play(AssetSource('sounds/button_tap.mp3'));
    } catch (e) {
      debugPrint('Failed to play button sound: $e');
    }
  }

  void gestureTap() {
    if (!_isSupported || !_isInitialized) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastGestureClick < _minInterval) return;
    _lastGestureClick = now;

    try {
      _gesturePlayer?.play(AssetSource('sounds/button_tap.mp3'));
    } catch (e) {
      debugPrint('Failed to play gesture sound: $e');
    }
  }

  void dialogShow() {
    if (!_isSupported || !_isInitialized) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastDialogShow < _minInterval) return;
    _lastDialogShow = now;

    try {
      _dialogPlayer?.play(AssetSource('sounds/button_tap.mp3'));
    } catch (e) {
      debugPrint('Failed to play dialog sound: $e');
    }
  }
}