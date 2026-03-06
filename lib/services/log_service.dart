import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Singleton append-only logger that writes to a text file inside the app's
/// documents directory so the file can be shared / e-mailed for debugging.
///
/// Usage:
///   Log.i('BLE', 'Connected to Shimano EW-WU111');
///   Log.w('BLE', 'No D-Fly service found — raw notify still active');
///   Log.e('Call', 'MethodChannel failed: $e');
///   Log.raw('BLE', 'packet hex', data);
class Log {
  Log._();

  static File? _file;
  static IOSink? _sink;
  static bool _ready = false;

  // ── Init ──────────────────────────────────────────────────────────────────

  static Future<void> init() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      _file = File('${dir.path}/bell_debug.log');
      _sink = _file!.openWrite(mode: FileMode.append);
      _ready = true;
      _write('LOG', 'INFO', '─── Bell session start ───────────────────────');
    } catch (e) {
      debugPrint('[Log] init failed: $e');
    }
  }

  /// Returns the path so the UI can display / share it.
  static String? get filePath => _file?.path;

  static Future<void> close() async {
    await _sink?.flush();
    await _sink?.close();
    _ready = false;
  }

  // ── Public helpers ────────────────────────────────────────────────────────

  static void i(String tag, String msg) => _write(tag, 'INFO ', msg);
  static void w(String tag, String msg) => _write(tag, 'WARN ', msg);
  static void e(String tag, String msg) => _write(tag, 'ERROR', msg);

  /// Log raw BLE packet bytes as hex for packet-level debugging.
  static void raw(String tag, String label, List<int> data) {
    final hex = data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    _write(tag, 'RAW  ', '$label [$hex]  len=${data.length}');
  }

  // ── Internal ──────────────────────────────────────────────────────────────

  static void _write(String tag, String level, String msg) {
    final ts = DateTime.now().toIso8601String();
    final line = '$ts  $level  [$tag]  $msg\n';
    debugPrint(line.trimRight()); // also shows in IDE console
    if (_ready && _sink != null) {
      _sink!.write(line);
    }
  }
}
