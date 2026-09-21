import 'dart:io';

/// Runtime API keys.
///
/// GIF search is Giphy-only in this build. Provide a free key from
/// https://developers.giphy.com either via the GIPHY_API_KEY environment
/// variable or by writing it to ~/.config/flemozi/giphy.key (single line).
/// No rebuild is needed to change it — just edit the file and reopen Flemozi.
class Env {
  static final String giphy = _readKey('GIPHY_API_KEY', 'giphy.key');

  /// Tenor is disabled in the Giphy-only build. Drop a Google/Tenor key into
  /// ~/.config/flemozi/tenor.key (or set TENOR_API_KEY) to re-enable it.
  static final String tenor = _readKey('TENOR_API_KEY', 'tenor.key');

  static String _readKey(String envVar, String fileName) {
    final fromEnv = Platform.environment[envVar];
    if (fromEnv != null && fromEnv.trim().isNotEmpty) return fromEnv.trim();
    try {
      final home = Platform.environment['HOME'] ?? '';
      final xdg = Platform.environment['XDG_CONFIG_HOME'];
      final base = (xdg != null && xdg.isNotEmpty) ? xdg : '$home/.config';
      final f = File('$base/flemozi/$fileName');
      if (f.existsSync()) return f.readAsStringSync().trim();
    } catch (_) {}
    return '';
  }
}
