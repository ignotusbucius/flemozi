import 'dart:convert';
import 'dart:io';

import 'package:fl_query/fl_query.dart';
import 'package:flemozi/api/api.dart';
import 'package:flemozi/intents/close_window.dart';
import 'package:flemozi/models/shortcut_def.dart';
import 'package:flemozi/pages/root.dart';
import 'package:flemozi/providers/shortcut.dart';
import 'package:flemozi/utils/platform.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:system_theme/system_theme.dart';
import 'package:window_manager/window_manager.dart';
import 'package:window_size/window_size.dart' as window_size;
import 'package:path_provider/path_provider.dart';

Future<void> main(List<String> args) async {
  final isHeadless = args.contains("--headless");

  _installSystemCa();

  WidgetsFlutterBinding.ensureInitialized();

  await windowManager.ensureInitialized();

  SystemTheme.fallbackColor = Colors.blue;
  await SystemTheme.accentColor.load();

  window_size.setWindowMinSize(const Size(400, 300));
  window_size.setWindowMaxSize(const Size(720, 480));

  final packageInfo = await PackageInfo.fromPlatform();

  launchAtStartup.setup(
    appName: packageInfo.appName,
    appPath: Platform.resolvedExecutable,
    args: <String>["--headless"],
  );

  await launchAtStartup.enable();

  WindowOptions windowOptions = const WindowOptions(
    minimumSize: Size(400, 300),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
    title: "Flemoji",
    maximumSize: Size(720, 480),
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    final localStorage = await SharedPreferences.getInstance();
    final rawSize = localStorage.getString('window_size');
    final savedSize = rawSize != null ? json.decode(rawSize) : null;
    final double? height = savedSize?["height"];
    final double? width = savedSize?["width"];
    if (height != null && width != null) {
      await windowManager.setSize(Size(width, height));
    }
    await windowManager.setAsFrameless();

    if (isHeadless) return;
    await windowManager.show();
    await windowManager.focus();
  });

  /// No shortcut for wayland as it's not supported (yet)
  if (kIsWayland) {
    try {
      await get(Uri.parse("http://localhost:42069/show"));
      exit(0);
    } catch (e) {
      await api();
    }
  }

  final appDataDir = await getApplicationSupportDirectory();

  await QueryClient.initialize(
    cachePrefix: 'flemoji',
    cacheDir: appDataDir.path,
  );
  await Hive.openBox('flemozi.config');
  runApp(const ProviderScope(child: Flemozi()));
}

/// Flutter Linux builds do not ship a trusted-root store, so HTTPS calls fail
/// with CERTIFICATE_VERIFY_FAILED on distros whose CA bundle Dart cannot find
/// (e.g. a binary built on Ubuntu running on Fedora). Load the system CA bundle
/// explicitly and route all HttpClients through it so GIF fetching works.
class _SystemCaHttpOverrides extends HttpOverrides {
  final SecurityContext _ctx;
  _SystemCaHttpOverrides(this._ctx);
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context ?? _ctx);
}

void _installSystemCa() {
  const candidates = [
    '/etc/ssl/certs/ca-certificates.crt',
    '/etc/pki/tls/certs/ca-bundle.crt',
    '/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem',
    '/etc/ssl/cert.pem',
  ];
  for (final path in candidates) {
    try {
      if (!File(path).existsSync()) continue;
      final ctx = SecurityContext(withTrustedRoots: true);
      ctx.setTrustedCertificates(path);
      HttpOverrides.global = _SystemCaHttpOverrides(ctx);
      return;
    } catch (_) {
      // try next candidate
    }
  }
}

final navigatorKey = GlobalKey<NavigatorState>();

class Flemozi extends StatefulHookConsumerWidget {
  const Flemozi({super.key});

  @override
  ConsumerState<Flemozi> createState() => _FlemoziState();
}

class _FlemoziState extends ConsumerState<Flemozi> with WidgetsBindingObserver {
  Size? prevSize;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() async {
    super.didChangeMetrics();
    final localStorage = await SharedPreferences.getInstance();
    final size = await windowManager.getSize();
    final windowSameDimension =
        prevSize?.width == size.width && prevSize?.height == size.height;

    if (windowSameDimension) return;
    localStorage.setString(
      'window_size',
      jsonEncode({
        'width': size.width,
        'height': size.height,
      }),
    );
    prevSize = size;
  }

  @override
  Widget build(BuildContext context) {
    final shortcutsNotifier = ref.watch(ShortcutNotifier.provider.notifier);
    final shortcuts = ref.watch(ShortcutNotifier.provider);

    useEffect(() {
      shortcutsNotifier.initialize(context);
      return null;
    }, const []);

    return QueryClientProvider(
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.dark,
        navigatorKey: navigatorKey,
        theme: ThemeData.light(useMaterial3: true),
        darkTheme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorSchemeSeed: SystemTheme.accentColor.accent,
          splashFactory: NoSplash.splashFactory,
          scaffoldBackgroundColor: Colors.transparent,
          tabBarTheme: TabBarTheme(
            indicatorSize: TabBarIndicatorSize.tab,
            dividerColor: Colors.transparent,
            indicator: BoxDecoration(
              color: Colors.grey[850],
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(5),
                topRight: Radius.circular(5),
              ),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: Colors.grey[850]?.withOpacity(.5),
          ),
        ),
        builder: (context, child) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          return HookBuilder(builder: (context) {
            final appShortcuts = useFuture(useMemoized(
              () => Future.wait(shortcuts.entries
                  .where((entry) => entry.key.type == ShortcutType.application)
                  .map(
                (entry) async {
                  return MapEntry(
                    await entry.value.toSingleActivator(),
                    () => entry.key.action(
                      ref.read,
                      navigatorKey.currentContext ?? context,
                    ),
                  );
                },
              )),
              [shortcuts],
            ));

            return CallbackShortcuts(
              bindings: {
                ...Map.fromEntries(appShortcuts.data ?? []),
                LogicalKeySet(LogicalKeyboardKey.escape): () =>
                    CloseWindowAction().invoke(const CloseWindowIntent())
              },
              child: Container(
                margin: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.grey[900]!.withOpacity(.5)
                      : Colors.white60,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: DragToResizeArea(child: child!),
              ),
            );
          });
        },
        home: const RootPage(),
        shortcuts: {
          ...WidgetsApp.defaultShortcuts,
          LogicalKeySet(LogicalKeyboardKey.escape): const CloseWindowIntent(),
        },
        actions: {
          ...WidgetsApp.defaultActions,
          CloseWindowIntent: CloseWindowAction(),
        },
      ),
    );
  }
}
