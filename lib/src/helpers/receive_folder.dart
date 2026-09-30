import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:locsand/src/helpers/settings_store.dart';

Future<Directory> receiveDirectory() async {
  final saved = await SettingsStore().getReceiveDir();
  if (saved != null) {
    final dir = Directory(saved);
    if (await dir.exists()) return dir;
  }
  try {
    final downloads = await getDownloadsDirectory();
    if (downloads != null) return downloads;
  } catch (_) {}
  return getApplicationDocumentsDirectory();
}

Future<String?> pickReceiveFolder() async {
  try {
    final path = await FilePicker.platform.getDirectoryPath();
    if (path != null) await SettingsStore().setReceiveDir(path);
    return path;
  } catch (_) {
    return null;
  }
}
