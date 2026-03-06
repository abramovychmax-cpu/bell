/// Action types reported by the `ad0a1002` Switch characteristic.
enum Di2Action {
  /// A single short press.
  singleClick,

  /// Two presses in quick succession.
  doubleClick,

  /// A sustained press (hardware-classified by the Di2 system).
  longPress;

  String get displayName => switch (this) {
        Di2Action.singleClick => 'Single click',
        Di2Action.doubleClick => 'Double click',
        Di2Action.longPress   => 'Long press',
      };
}

/// Result of parsing one `ad0a1002` switch event packet.
class SwitchEvent {
  /// Which button fired the event (null if unrecognised switch ID).
  final Di2Button? button;

  /// What the user did (null if unrecognised action byte).
  final Di2Action? action;

  const SwitchEvent({required this.button, required this.action});

  @override
  String toString() =>
      'SwitchEvent(button=${button?.shortName}, action=${action?.displayName})';
}

/// The two customisable "A" buttons on the Shimano ST-R8170 lever hoods.
/// In your E-TUBE app these are assigned as D-FLY Ch.1 (left) and Ch.4 (right).
/// There are no satellite switches (SW-R9160) in this setup.
enum Di2Button {
  /// Left lever A-button — D-FLY Ch. 1 (ST-R8170-L)
  climbA,

  /// Right lever A-button — D-FLY Ch. 4 (ST-R8170-R)
  climbB,

  /// Both lever A-buttons pressed at the same time
  both;

  String get displayName => switch (this) {
        Di2Button.climbA => 'Left lever A-button (D-FLY Ch.1)',
        Di2Button.climbB => 'Right lever A-button (D-FLY Ch.4)',
        Di2Button.both   => 'Both A-buttons together',
      };

  String get shortName => switch (this) {
        Di2Button.climbA => 'Left A (Ch.1)',
        Di2Button.climbB => 'Right A (Ch.4)',
        Di2Button.both   => 'Both',
      };
}

/// Parses BLE notification payloads from Shimano Di2 devices.
///
/// ── Legacy D-Fly characteristic (`a026e002`) ─────────────────────────────
/// Multi-byte packet (EW-WU111 / older junction boxes):
///
///   Byte 0 : message length
///   Byte 1 : message class  (0x03 = shift/button event for levers)
///   Byte 2 : message type   (varies: 0x09 shift, 0x0C D-FLY custom button)
///   Byte 3 : component ID
///              0x04 = ST-R8170 left lever  (D-FLY Ch.1 = A-button)
///              0x05 = Left satellite switch SW-R9160 (not present here)
///              0x06 = ST-R8170 right lever (D-FLY Ch.4 = A-button)
///              0x07 = Right satellite switch SW-R9160 (not present here)
///   Byte 4 : button bitmap  (0x00 = button up, any non-zero = button active)
///   Byte 5+: additional state / varies by firmware
///
/// ── Shimano proprietary Switch characteristic (`ad0a1002`) ───────────────
/// 2-byte switch event (RD-R8150, 12-speed Di2):
///
///   Byte 0 : Switch ID  — 0x03 = Left top button  (D-FLY Ch.1)
///                         0x04 = Right top button (D-FLY Ch.4)
///   Byte 1 : Action     — 0x01 = single click
///                         0x02 = double click
///                         0x03 = long press
class Di2Parser {
  // ── Legacy D-Fly component IDs (byte 3 of multi-byte packet) ──────────────
  static const int _compLeftLever  = 0x04; // ST-R8170-L → D-FLY Ch.1
  static const int _compRightLever = 0x06; // ST-R8170-R → D-FLY Ch.4
  // Also accept satellite-switch component IDs for backwards compatibility.
  static const int _compLeftSat    = 0x05;
  static const int _compRightSat   = 0x07;

  // ── 1002 Switch characteristic constants ───────────────────────────────────
  static const int _switchIdLeft  = 0x03; // Left top button  (D-FLY Ch.1)
  static const int _switchIdRight = 0x04; // Right top button (D-FLY Ch.4)
  static const int _actionSingleClick = 0x01;
  static const int _actionDoubleClick = 0x02;
  static const int _actionLongPress   = 0x03;

  /// Returns true when [data] is a valid button-DOWN packet.
  ///
  /// NOTE: We intentionally do NOT filter on bytes 1/2 (message class/type)
  /// because D-FLY custom-button events on ST-R8170 levers use different
  /// class/type values than the classic shift-event 0x03/0x09 originally
  /// documented for satellite switches. Accepting any 5-byte packet with a
  /// non-zero button byte is safe here because we filter by component ID.
  static bool isButtonDown(List<int> data) {
    if (data.length < 5) return false;
    return data[4] != 0x00;
  }

  /// Returns true when at least one of the enabled buttons is active in [data].
  static bool isEnabledActive(
    List<int> data, {
    required bool climbA,
    required bool climbB,
  }) {
    if (!isButtonDown(data)) return false;
    final comp = data[3];
    if (climbA && (comp == _compLeftLever  || comp == _compLeftSat))  return true;
    if (climbB && (comp == _compRightLever || comp == _compRightSat)) return true;
    return false;
  }

  /// Returns true when [data] reports that [button] is pressed.
  static bool isButtonActive(List<int> data, Di2Button button) {
    if (!isButtonDown(data)) return false;
    final comp = data[3];
    return switch (button) {
      Di2Button.climbA => comp == _compLeftLever  || comp == _compLeftSat,
      Di2Button.climbB => comp == _compRightLever || comp == _compRightSat,
      Di2Button.both   => (comp == _compLeftLever  || comp == _compLeftSat) &&
                          (comp == _compRightLever || comp == _compRightSat),
    };
  }

  /// Returns the set of buttons currently active in [data] (legacy char).
  static Set<Di2Button> activeButtons(List<int> data) {
    if (!isButtonDown(data)) return {};
    final comp = data[3];
    return {
      if (comp == _compLeftLever  || comp == _compLeftSat)  Di2Button.climbA,
      if (comp == _compRightLever || comp == _compRightSat) Di2Button.climbB,
    };
  }

  // ── 1002 Switch characteristic parser ─────────────────────────────────────

  /// Parses a 2-byte payload from the `ad0a1002` Switch characteristic.
  ///
  /// Returns a [SwitchEvent] with the fields that could be decoded.
  /// Returns null only if the packet is too short to contain anything useful.
  static SwitchEvent? parseSwitchEvent(List<int> data) {
    if (data.length < 2) return null;

    final switchId   = data[0];
    final actionByte = data[1];

    final button = switch (switchId) {
      _switchIdLeft  => Di2Button.climbA,
      _switchIdRight => Di2Button.climbB,
      _              => null,
    };

    final action = switch (actionByte) {
      _actionSingleClick => Di2Action.singleClick,
      _actionDoubleClick => Di2Action.doubleClick,
      _actionLongPress   => Di2Action.longPress,
      _                  => null,
    };

    return SwitchEvent(button: button, action: action);
  }
}
