import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/di2_device.dart';

/// Persists user settings and paired DI2 device identity.
class StorageService {
  static const _keyDevice        = 'paired_di2_device';
  static const _keyMessage       = 'call_message';
  static const _keyHoldMs        = 'hold_duration_ms';
  static const _keyAutoReconnect = 'auto_reconnect';
  static const _keyClimbAEnabled = 'climb_a_enabled';
  static const _keyClimbBEnabled = 'climb_b_enabled';

  late final SharedPreferences _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // ── Paired device ──────────────────────────────────────────────────────────

  Di2Device? get pairedDevice {
    final raw = _prefs.getString(_keyDevice);
    if (raw == null) return null;
    return Di2Device.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> savePairedDevice(Di2Device device) =>
      _prefs.setString(_keyDevice, jsonEncode(device.toJson()));

  Future<void> clearPairedDevice() => _prefs.remove(_keyDevice);

  // ── Message shown on Wahoo screen (= fake caller name) ────────────────────

  String get callMessage => _prefs.getString(_keyMessage) ?? 'Rider Alert';

  Future<void> saveCallMessage(String msg) =>
      _prefs.setString(_keyMessage, msg);

  // ── How long (ms) the button must be held to trigger ─────────────────────

  int get holdDurationMs => _prefs.getInt(_keyHoldMs) ?? 800;

  Future<void> saveHoldDuration(int ms) => _prefs.setInt(_keyHoldMs, ms);

  // ── Auto-reconnect after drop ─────────────────────────────────────────────

  bool get autoReconnect => _prefs.getBool(_keyAutoReconnect) ?? true;

  Future<void> saveAutoReconnect(bool v) =>
      _prefs.setBool(_keyAutoReconnect, v);

  // ── Which climb buttons are active triggers ───────────────────────────────
  // Defaults: A = on, B = off.

  bool get climbAEnabled => _prefs.getBool(_keyClimbAEnabled) ?? true;
  bool get climbBEnabled => _prefs.getBool(_keyClimbBEnabled) ?? false;

  Future<void> saveClimbAEnabled(bool v) =>
      _prefs.setBool(_keyClimbAEnabled, v);
  Future<void> saveClimbBEnabled(bool v) =>
      _prefs.setBool(_keyClimbBEnabled, v);
}
