class sessionData {
  static final sessionData _instance = sessionData._internal();
  factory sessionData() => _instance;
  sessionData._internal();

  String? userId;
  String? userName;
  String? userIp;

  void clear() {
    userId = null;
    userName = null;
    userIp = null;
  }
}