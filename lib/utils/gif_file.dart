import 'dart:io';
import 'dart:typed_data';

/// Writes [bytes] of the GIF at [url] to ~/Downloads/.flemozi/ and returns the
/// file, so it can be put on the clipboard as a file (text/uri-list).
///
/// ~/Downloads is readable by Flatpak browsers (xdg-download), unlike most
/// other folders. Files older than a day are pruned on each copy.
Future<File> saveGifForPaste(String url, Uint8List bytes) async {
  final home = Platform.environment['HOME'] ?? '';
  final dir = Directory('$home/Downloads/.flemozi');
  await dir.create(recursive: true);

  _pruneOld(dir);

  // Giphy URLs look like .../media/<id>/200w.gif, so the id makes a stable,
  // unique name. Fall back to a hash for anything else.
  final segments = Uri.tryParse(url)?.pathSegments ?? const <String>[];
  final mediaIdx = segments.indexOf('media');
  final id = (mediaIdx >= 0 && mediaIdx + 1 < segments.length)
      ? segments[mediaIdx + 1]
      : url.hashCode.toUnsigned(32).toRadixString(16);
  final safeId = id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

  final file = File('${dir.path}/$safeId.gif');
  await file.writeAsBytes(bytes, flush: true);
  return file;
}

void _pruneOld(Directory dir) {
  final cutoff = DateTime.now().subtract(const Duration(days: 1));
  try {
    for (final e in dir.listSync()) {
      if (e is File && e.path.endsWith('.gif') &&
          e.statSync().modified.isBefore(cutoff)) {
        e.deleteSync();
      }
    }
  } catch (_) {}
}
