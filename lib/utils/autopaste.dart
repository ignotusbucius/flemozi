import 'dart:io';

import 'package:flemozi/utils/platform.dart';
import 'package:window_manager/window_manager.dart';

/// Emulates the Windows `Win+.` emoji-picker behaviour on Linux/Wayland:
/// after the selected item has been placed on the clipboard, hide the picker
/// so the window you were typing in regains focus, inject Ctrl+V into it with
/// ydotool, then re-show the picker so several items can be inserted in a row.
///
/// Wayland forbids an app from typing into another window, so a kernel-level
/// virtual input device (ydotool + ydotoold, using /dev/uinput) is required.
/// On non-Linux platforms this is a no-op and the picker simply stays open.
Future<void> pasteAndKeepOpen() async {
  if (!kIsLinux) return;

  await windowManager.ungrabKeyboard();
  await windowManager.hide();

  // Give the compositor a moment to hand focus back to the previous window.
  // If Ctrl+V lands in the wrong place, raise the delay by writing a number of
  // milliseconds to ~/.config/flemozi/paste_delay_ms (or set FLEMOZI_PASTE_DELAY_MS).
  await Future.delayed(Duration(milliseconds: _focusDelayMs()));
  await _ydotoolCtrlV();
  await Future.delayed(const Duration(milliseconds: 60));

  await _reshow();
}

int _focusDelayMs() {
  const fallback = 160;
  final fromEnv = Platform.environment['FLEMOZI_PASTE_DELAY_MS'];
  final parsedEnv = fromEnv == null ? null : int.tryParse(fromEnv.trim());
  if (parsedEnv != null && parsedEnv >= 0) return parsedEnv;
  try {
    final home = Platform.environment['HOME'] ?? '';
    final xdg = Platform.environment['XDG_CONFIG_HOME'];
    final base = (xdg != null && xdg.isNotEmpty) ? xdg : '$home/.config';
    final f = File('$base/flemozi/paste_delay_ms');
    if (f.existsSync()) {
      final v = int.tryParse(f.readAsStringSync().trim());
      if (v != null && v >= 0) return v;
    }
  } catch (_) {}
  return fallback;
}

Future<void> _reshow() async {
  await windowManager.setAlwaysOnTop(true);
  await windowManager.show();
  await windowManager.focus();
  await windowManager.grabKeyboard();
  Future.delayed(const Duration(milliseconds: 100), () async {
    await windowManager.setAlwaysOnTop(false);
    await windowManager.focus();
    await windowManager.grabKeyboard();
  });
}

Future<bool> _ydotoolCtrlV() async {
  final runtime = Platform.environment['XDG_RUNTIME_DIR'];
  final envSock = Platform.environment['YDOTOOL_SOCKET'];
  final socket = (envSock != null && envSock.isNotEmpty)
      ? envSock
      : '${runtime ?? '/run/user/1000'}/.ydotool_socket';
  final env = {'YDOTOOL_SOCKET': socket};

  // LEFTCTRL=29, V=47 (Linux input event codes). Press ctrl, press+release v,
  // release ctrl.
  const args = ['key', '29:1', '47:1', '47:0', '29:0'];

  for (final bin in const ['ydotool', '/usr/bin/ydotool']) {
    try {
      final result = await Process.run(bin, args, environment: env);
      if (result.exitCode == 0) return true;
    } catch (_) {
      // try next candidate
    }
  }
  return false;
}
