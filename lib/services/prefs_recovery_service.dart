import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Keeps the desktop settings file from bricking the till.
///
/// On Windows and Linux, shared_preferences stores everything in one JSON
/// file and saves by truncating and rewriting it in place. A power cut during
/// a save leaves it half-written or full of NUL bytes, and from then on every
/// launch dies in `SharedPreferences.getInstance()` with a FormatException
/// ("Please restart the application" — which never helps).
///
/// Run [repair] before `getInstance()`: a healthy file is copied aside as the
/// last good one; a broken one is moved aside and the last good copy put back.
class PrefsRecoveryService {
  static const fileName = 'shared_preferences.json';
  static const lastGoodName = 'shared_preferences.lastgood.json';

  /// Returns a description of what was repaired, or null when nothing was.
  static Future<String?> repair() async {
    if (!(Platform.isWindows || Platform.isLinux)) return null;
    // Same directory the plugin resolves (company/product from the runner).
    final dir = await getApplicationSupportDirectory();
    return repairIn(dir);
  }

  static String? repairIn(Directory dir) {
    final file = File(p.join(dir.path, fileName));
    final lastGood = File(p.join(dir.path, lastGoodName));

    // Missing is a fresh install or a deliberate reset, not corruption.
    if (!file.existsSync()) return null;

    if (isValid(file)) {
      _writeAtomically(lastGood, file.readAsBytesSync());
      return null;
    }

    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '')
        .replaceAll('.', '');
    final corruptPath = p.join(dir.path, 'shared_preferences.corrupt-$stamp.json');
    file.renameSync(corruptPath);

    if (lastGood.existsSync() && isValid(lastGood)) {
      _writeAtomically(file, lastGood.readAsBytesSync());
      return 'Settings file was corrupt; restored the last good copy '
          '(broken file kept as $corruptPath)';
    }
    return 'Settings file was corrupt and no good copy exists; starting with '
        'empty settings (broken file kept as $corruptPath)';
  }

  /// Well-formed JSON object. `{}` counts: the plugin writes it after a
  /// clear, and restoring over a deliberate clear would undo it. A zero-byte
  /// file does not: the plugin never writes one, only a crash mid-save does.
  static bool isValid(File file) {
    try {
      final text = utf8.decode(file.readAsBytesSync());
      if (text.trim().isEmpty) return false;
      return json.decode(text) is Map;
    } catch (_) {
      return false;
    }
  }

  static void _writeAtomically(File target, List<int> bytes) {
    final tmp = File('${target.path}.tmp');
    tmp.writeAsBytesSync(bytes, flush: true);
    tmp.renameSync(target.path);
  }
}
