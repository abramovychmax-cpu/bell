/// Represents a paired Shimano DI2 (EW-WU111) BLE device.
/// The [remoteId] is the platform BLE device identifier —
/// on Android this is the MAC address, on iOS it is the CoreBluetooth UUID.
/// Storing this means the app will ONLY react to YOUR unit, not a friend's.
class Di2Device {
  final String remoteId;
  final String name;

  const Di2Device({required this.remoteId, required this.name});

  factory Di2Device.fromJson(Map<String, dynamic> json) => Di2Device(
        remoteId: json['remoteId'] as String,
        name: json['name'] as String? ?? 'DI2',
      );

  Map<String, dynamic> toJson() => {'remoteId': remoteId, 'name': name};

  Di2Device copyWith({String? remoteId, String? name}) => Di2Device(
        remoteId: remoteId ?? this.remoteId,
        name: name ?? this.name,
      );

  @override
  String toString() => 'Di2Device($name [$remoteId])';
}
