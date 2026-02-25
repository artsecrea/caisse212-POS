import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final soundServiceProvider = Provider<SoundService>((ref) {
  final service = SoundService();
  return service;
});

class SoundService {
  final AudioPlayer _buttonPlayer = AudioPlayer();
  final AudioPlayer _gesturePlayer = AudioPlayer();
  final AudioPlayer _dialogPlayer = AudioPlayer();

  int _lastButtonClick = 0;
  int _lastGestureClick = 0;
  int _lastDialogShow = 0;
  static const int _minInterval = 80; // ms

  Future<void> preload() async {
    await _buttonPlayer.setSource(AssetSource('sounds/button_tap.mp3'));
    await _gesturePlayer.setSource(AssetSource('sounds/button_tap.mp3'));
    await _dialogPlayer.setSource(AssetSource('sounds/button_tap.mp3'));
  }

  void buttonTap() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastButtonClick < _minInterval) return;
    _lastButtonClick = now;

    _buttonPlayer.play(AssetSource('sounds/button_tap.mp3'));
  }

  void gestureTap() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastGestureClick < _minInterval) return;
    _lastGestureClick = now;

    _gesturePlayer.play(AssetSource('sounds/button_tap.mp3'));
  }

  void dialogShow() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastDialogShow < _minInterval) return;
    _lastDialogShow = now;

    _dialogPlayer.play(AssetSource('sounds/button_tap.mp3'));
  }
}