final RegExp _windowsReserved =
    RegExp(r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])$', caseSensitive: false);

/// Turns a file name received from the network into something that is safe to
/// create on every supported platform: no path parts, no control characters,
/// no Windows reserved names, no trailing dots/spaces and a bounded length.
String safeFileName(String raw, {int maxLength = 120}) {
  final parts = raw.split(RegExp(r'[\\/]')).where((s) => s.isNotEmpty);
  var name = parts.isEmpty ? '' : parts.last;
  name = name.replaceAll(RegExp(r'[<>:"|?*\x00-\x1f]'), '_').trim();
  name = name.replaceAll(RegExp(r'[. ]+$'), '');
  if (name.isEmpty || name == '.' || name == '..') return 'received_file';

  final dot = name.lastIndexOf('.');
  var base = dot > 0 ? name.substring(0, dot) : name;
  var ext = dot > 0 ? name.substring(dot) : '';
  if (ext.length > 16) ext = ext.substring(0, 16);

  if (_windowsReserved.hasMatch(base.split('.').first)) base = '_$base';

  final room = maxLength - ext.length;
  if (base.length > room) base = base.substring(0, room < 1 ? 1 : room);
  return '$base$ext';
}
