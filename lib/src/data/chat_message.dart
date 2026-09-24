class ChatMessage {
  final String text;
  final bool fromMe;
  final DateTime time;

  ChatMessage({
    required this.text, 
    required this.fromMe, 
    required this.time
  });

  Map<String, dynamic> toJson() => {
        'text': text,
        'fromMe': fromMe,
        'time': time.toIso8601String(),
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        text: json['text'] as String? ?? '',
        fromMe: json['fromMe'] as bool? ?? false,
        time: DateTime.tryParse(json['time'] as String? ?? '') ?? DateTime.now(),
      );
}
