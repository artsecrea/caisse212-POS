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
  AudioPlayer? _alertPlayer;
  bool _isInitialized = false;
  bool _isSupported = true;

  int _lastButtonClick = 0;
  int _lastGestureClick = 0;
  int _lastDialogShow = 0;
  int _lastAlert = 0;
  static const int _minInterval = 80; // ms

  /// Alerts get their own, much longer window. Two online orders landing in the
  /// same second is normal at peak, and stacking chimes reads as a malfunction
  /// rather than as two orders — one chime per burst is the signal that lands.
  static const int _alertMinInterval = 1200; // ms

  SoundService() {
    _initPlayers();
  }

  Future<void> _initPlayers() async {
    if (!_isSupported) return;

    try {
      _buttonPlayer = AudioPlayer();
      _gesturePlayer = AudioPlayer();
      _dialogPlayer = AudioPlayer();
      _alertPlayer = AudioPlayer();
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

    // Separate try: the alert is the one sound that matters operationally, and
    // conversely a problem loading it must not switch off the UI clicks (the
    // catch above disables everything).
    try {
      await _alertPlayer?.setSource(AssetSource('sounds/new_order.wav'));
      await _alertPlayer?.setVolume(1.0);
    } catch (e) {
      // Log only — do NOT drop the player. play() loads the asset on demand
      // anyway, so a preload hiccup (common right after a hot reload, before
      // the new asset is in the bundle) must not mute the alert for the whole
      // session.
      debugPrint('Failed to preload alert sound: $e');
    }
  }

  /// Chime for an incoming online order. Deliberately louder and longer than
  /// the UI clicks — it has to carry across a counter to someone not looking at
  /// the screen.
  void newOrderAlert() {
    if (!_isInitialized || _alertPlayer == null) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastAlert < _alertMinInterval) return;
    _lastAlert = now;

    try {
      // stop() first so a chime already sounding restarts rather than being
      // ignored by the player as "already playing".
      _alertPlayer?.stop();
      _alertPlayer?.play(AssetSource('sounds/new_order.wav'), volume: 1.0);
    } catch (e) {
      debugPrint('Failed to play new-order alert: $e');
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