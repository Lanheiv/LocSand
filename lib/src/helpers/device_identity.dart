import 'dart:io';
import 'dart:math';

import 'package:path_provider/path_provider.dart';

class DeviceIdentity {
  static Future<String> loadOrCreateId() async {
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/device_id.txt');

    if (await file.exists()) {
      final existing = (await file.readAsString()).trim();
      if (existing.isNotEmpty) return existing;
    }

    final rnd = Random.secure();
    final id = List.generate(16, (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    await file.writeAsString(id);
    return id;
  }
}
