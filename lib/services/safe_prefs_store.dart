import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:loggecrea/loggecrea.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

import 'prefs_recovery_service.dart';

/// The desktop settings store, replacing the shared_preferences plugin's own
/// on Windows and Linux. Same file, same JSON, but it closes the ways the
/// plugin loses settings:
///
/// * The plugin truncates the file and rewrites it in place on every single
///   `set`, so a power cut or a killed process mid-save leaves it broken and
///   the next launch falls back to the launch-time copy, losing every change
///   made since. Here a save goes to a temp file, is flushed, and is renamed
///   over the real one: the file is always either the old or the new version.
/// * Each process rewrites the whole file from its own cached copy, so two
///   tills on one machine (another Windows account, the sandbox) silently undo
///   each other's changes. Here a save re-reads the file when someone else
///   changed it and lays only this process's changes on top.
/// * A save that fails (no write access) only ever printed to the debug
///   console, so a setting looked saved until the next restart. It is logged.
/// * The last good copy is refreshed every few minutes instead of only at
///   launch, so a restore never goes back further than that.
class SafePrefsStore extends SharedPreferencesStorePlatform {
  SafePrefsStore(this.directory);

  final String directory;

  static const lastGoodEvery = Duration(minutes: 5);

  File get _file => File(p.join(directory, PrefsRecoveryService.fileName));
  File get _lastGood =>
      File(p.join(directory, PrefsRecoveryService.lastGoodName));

  Map<String, Object>? _cache;
  // What the file looked like when this process last read or wrote it.
  DateTime? _seenModified;
  int? _seenSize;
  // This process's edits not yet on disk; null value = removed.
  final Map<String, Object?> _pending = {};
  Future<bool> _writing = Future.value(true);
  // Recovery has just written it at launch.
  DateTime _lastGoodAt = DateTime.now();

  /// Takes over from the plugin. Run after [PrefsRecoveryService.repair] and
  /// before the first `SharedPreferences.getInstance()`.
  static Future<void> install() async {
    if (!(Platform.isWindows || Platform.isLinux)) return;
    final dir = await getApplicationSupportDirectory();
    SharedPreferencesStorePlatform.instance = SafePrefsStore(dir.path);
  }

  Map<String, Object> _load() {
    final cache = _cache;
    final stat = _file.statSync();
    if (cache != null &&
        stat.modified == _seenModified &&
        stat.size == _seenSize) {
      return cache;
    }
    final fresh = _readDisk(stat) ?? cache ?? <String, Object>{};
    _cache = fresh;
    return fresh;
  }

  Map<String, Object>? _readDisk(FileStat stat) {
    if (stat.type == FileSystemEntityType.notFound) {
      _seenModified = null;
      _seenSize = null;
      return <String, Object>{};
    }
    try {
      final text = _file.readAsStringSync();
      _seenModified = stat.modified;
      _seenSize = stat.size;
      if (text.trim().isEmpty) return <String, Object>{};
      final data = json.decode(text);
      if (data is! Map) return null;
      return data.map((k, v) => MapEntry(k as String, _typed(v)));
    } catch (e) {
      Logger.instance.error('Settings file unreadable, keeping memory copy: $e');
      return null;
    }
  }

  // JSON gives back List<dynamic>; callers expect List<String>.
  static Object _typed(Object? v) =>
      v is List ? v.cast<String>().toList() : v as Object;

  Future<bool> _persist() {
    return _writing = _writing.then((_) async {
      if (_pending.isEmpty) return true;
      final edits = Map<String, Object?>.of(_pending);
      _pending.clear();
      try {
        final merged = Map<String, Object>.of(_load());
        edits.forEach((k, v) => v == null ? merged.remove(k) : merged[k] = v);
        final bytes = utf8.encode(json.encode(merged));
        await _replace(_file, bytes);
        final stat = _file.statSync();
        _seenModified = stat.modified;
        _seenSize = stat.size;
        _cache = merged;
        if (DateTime.now().difference(_lastGoodAt) >= lastGoodEvery) {
          _lastGoodAt = DateTime.now();
          await _replace(_lastGood, bytes);
        }
        return true;
      } catch (e) {
        // Put them back so the next save tries again.
        edits.forEach((k, v) => _pending.putIfAbsent(k, () => v));
        Logger.instance.error('Settings NOT saved (${edits.keys.join(', ')}): $e');
        return false;
      }
    });
  }

  /// Writes [target] so that it is never seen half-written.
  static Future<void> _replace(File target, List<int> bytes) async {
    final tmp = File('${target.path}.$pid.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    // Antivirus or a backup tool can hold the file for a moment.
    for (var attempt = 1;; attempt++) {
      try {
        await tmp.rename(target.path);
        return;
      } on FileSystemException {
        if (attempt >= 5) break;
        await Future<void>.delayed(Duration(milliseconds: 40 * attempt));
      }
    }
    // Still locked: an in-place write beats losing the change.
    await target.writeAsBytes(bytes, flush: true);
    try {
      await tmp.delete();
    } catch (_) {}
  }

  bool _matches(String key, PreferencesFilter filter) =>
      key.startsWith(filter.prefix) &&
      (filter.allowList == null || filter.allowList!.contains(key));

  Map<String, Object> _view() {
    final view = Map<String, Object>.of(_load());
    _pending.forEach((k, v) => v == null ? view.remove(k) : view[k] = v);
    return view;
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) {
    _pending[key] = value;
    return _persist();
  }

  @override
  Future<bool> remove(String key) {
    _pending[key] = null;
    return _persist();
  }

  @override
  Future<bool> clear() =>
      clearWithParameters(ClearParameters(filter: PreferencesFilter(prefix: 'flutter.')));

  @override
  Future<bool> clearWithParameters(ClearParameters parameters) {
    for (final key in _view().keys) {
      if (_matches(key, parameters.filter)) _pending[key] = null;
    }
    return _persist();
  }

  @override
  Future<Map<String, Object>> getAll() =>
      getAllWithParameters(GetAllParameters(filter: PreferencesFilter(prefix: 'flutter.')));

  @override
  Future<Map<String, Object>> getAllWithParameters(
      GetAllParameters parameters) async {
    return Map.of(_view())
      ..removeWhere((key, _) => !_matches(key, parameters.filter));
  }
}
