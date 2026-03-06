/// The two hidden satellite switch buttons on the Shimano SW-R9160.
/// These are mounted on the bar tops and have no shifting function,
/// so they can never be triggered accidentally during a ride.
enum Di2Button {
  /// SW-R9160 satellite switch — button A (bar top, left side)
  climbA,

  /// SW-R9160 satellite switch — button B (bar top, right side)
  climbB,

  /// Both climb switches pressed at the same time
  both;

  String get displayName => switch (this) {
        Di2Button.climbA => 'Climb switch A (bar top, left)',
        Di2Button.climbB => 'Climb switch B (bar top, right)',
        Di2Button.both   => 'Both climb switches together',
      };

  String get shortName => switch (this) {
        Di2Button.climbA => 'Climb A',
        Di2Button.climbB => 'Climb B',
        Di2Button.both   => 'Both',
      };
}

/// Parses BLE notification payloads from the Shimano EW-WU111.
///
/// D-Fly packet layout (community reverse-engineering: openD2J, project-d2):
///
///   Byte 0 : message length (includes this byte)
///   Byte 1 : message class  0x03 = button/sensor event
///   Byte 2 : message type   0x09 = shift event
///   Byte 3 : component ID   0x03 = junction-A, 0x05 = climb switch …
///   Byte 4 : button bitmap
///              bit 0 (0x01) = Climb switch A
///              bit 1 (0x02) = Climb switch B
///              bit 2 (0x04) = Left lever front derailleur
///              bit 3 (0x08) = Right lever upshift
///              bit 4 (0x10) = Right lever downshift
///   Byte 5+: additional state / varies by firmware
class Di2Parser {
  static const int _classButtonEvent = 0x03;
  static const int _typeShiftEvent   = 0x09;

  // Byte-4 button bitmap masks — only climb switches retained.
  static const int _maskClimbA = 0x01;
  static const int _maskClimbB = 0x02;

  /// Returns true when [data] is a valid button-DOWN packet.
  static bool isButtonDown(List<int> data) {
    if (data.length < 5) return false;
    if (data[1] != _classButtonEvent) return false;
    if (data[2] != _typeShiftEvent)   return false;
    return data[4] != 0x00;
  }

  /// Returns true when at least one of the enabled buttons is active in [data].
  /// This is the main method called by BleService.
  static bool isEnabledActive(
    List<int> data, {
    required bool climbA,
    required bool climbB,
  }) {
    if (!isButtonDown(data)) return false;
    final bitmap = data[4];
    if (climbA && (bitmap & _maskClimbA) != 0) return true;
    if (climbB && (bitmap & _maskClimbB) != 0) return true;
    return false;
  }

  /// Returns true when [data] reports that [button] is pressed.
  /// For [Di2Button.both] both A and B must be active simultaneously.
  static bool isButtonActive(List<int> data, Di2Button button) {
    if (!isButtonDown(data)) return false;
    final bitmap = data[4];
    return switch (button) {
      Di2Button.climbA => (bitmap & _maskClimbA) != 0,
      Di2Button.climbB => (bitmap & _maskClimbB) != 0,
      Di2Button.both   => (bitmap & _maskClimbA) != 0 &&
                          (bitmap & _maskClimbB) != 0,
    };
  }

  /// Returns the set of climb buttons currently active in [data].
  static Set<Di2Button> activeButtons(List<int> data) {
    if (!isButtonDown(data)) return {};
    final bitmap = data[4];
    return {
      if ((bitmap & _maskClimbA) != 0) Di2Button.climbA,
      if ((bitmap & _maskClimbB) != 0) Di2Button.climbB,
    };
  }
}
