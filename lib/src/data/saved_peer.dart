class SavedPeer {
  final String deviceId;
  final String name;
  final String lastKnownIp;
  final int lastKnownPort;
  final DateTime savedAt;

  SavedPeer({
    required this.deviceId,
    required this.name,
    required this.lastKnownIp,
    required this.lastKnownPort,
    required this.savedAt,
  });

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'name': name,
        'lastKnownIp': lastKnownIp,
        'lastKnownPort': lastKnownPort,
        'savedAt': savedAt.toIso8601String(),
      };

  factory SavedPeer.fromJson(Map<String, dynamic> json) => SavedPeer(
        deviceId: json['deviceId'] as String,
        name: json['name'] as String,
        // Tolerate records saved before these fields existed.
        lastKnownIp: json['lastKnownIp'] as String? ?? '',
        lastKnownPort: json['lastKnownPort'] as int? ?? 0,
        savedAt: DateTime.parse(json['savedAt'] as String),
      );
}