class ChatMessage {
  final String text;
  final bool fromMe;
  final DateTime time;

  ChatMessage({
    required this.text, 
    required this.fromMe, 
    required this.time
  });
}