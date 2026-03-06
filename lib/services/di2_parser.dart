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

/// Parses BLE notification payloads from the Shimano EW-WU111 (D-Fly).
///
/// D-Fly packet layout (community reverse-engineering: openD2J, project-d2):
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
class Di2Parser {
  // Component IDs for ST-R8170 levers.
  static const int _compLeftLever  = 0x04; // ST-R8170-L → D-FLY Ch.1
  static const int _compRightLever = 0x06; // ST-R8170-R → D-FLY Ch.4
  // Also accept satellite-switch component IDs for backwards compatibility.
  static const int _compLeftSat    = 0x05;
  static const int _compRightSat   = 0x07;

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

  /// Returns the set of buttons currently active in [data].
  static Set<Di2Button> activeButtons(List<int> data) {
    if (!isButtonDown(data)) return {};
    final comp = data[3];
    return {
      if (comp == _compLeftLever  || comp == _compLeftSat)  Di2Button.climbA,
      if (comp == _compRightLever || comp == _compRightSat) Di2Button.climbB,
    };
  }
}
