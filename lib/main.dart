import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/theme.dart';
import 'data/app_data.dart';
import 'data/local_db.dart';
import 'services/lock_service.dart';
import 'services/notification_service.dart';
import 'services/privacy_service.dart';
import 'services/settings.dart';
import 'services/sync_service.dart';
import 'ui/home_shell.dart';
import 'ui/lock_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  final settings = await AppSettings.load();
  unawaited(PrivacyService.setScreenProtection(settings.screenProtection));

  final db = LocalDb();
  final data = AppData(db);
  try {
    await db.open();
    await data.ensureDefaults();
    await data.load();
  } catch (e) {
    // Nada é apagado: o app mostra o erro e o arquivo fica intacto.
    runApp(StartupErrorApp(error: e));
    return;
  }

  if (SupabaseConfig.isConfigured) {
    await Supabase.initialize(url: SupabaseConfig.url, publishableKey: SupabaseConfig.anonKey);
  }

  final notifications = NotificationService();
  await notifications.init();

  final sync = SyncService(db, data, settings);
  data.onLocalWrite = sync.scheduleSync;

  // Reagenda as notificações sempre que os dados ou a antecedência mudam.
  Timer? debounce;
  void refreshNotifications() {
    debounce?.cancel();
    debounce = Timer(const Duration(seconds: 2), () {
      notifications.reschedule(
        data.reminders,
        settings.leadDays,
        showNames: settings.notificationNames,
      );
    });
  }

  var screenProtection = settings.screenProtection;
  settings.addListener(() {
    if (settings.screenProtection == screenProtection) return;
    screenProtection = settings.screenProtection;
    PrivacyService.setScreenProtection(screenProtection);
  });

  data.addListener(refreshNotifications);
  settings.addListener(refreshNotifications);
  refreshNotifications();
  unawaited(sync.start());

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: data),
        ChangeNotifierProvider.value(value: sync),
        Provider.value(value: notifications),
        Provider(create: (_) => LockService()),
      ],
      child: const ConsultorioApp(),
    ),
  );
}

class ConsultorioApp extends StatelessWidget {
  const ConsultorioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Consultório',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => LockGate(child: child ?? const SizedBox()),
      home: const HomeShell(),
    );
  }
}

/// Mostrada quando o banco local não abre por um motivo que não é a chave
/// (ex.: armazenamento cheio ou cofre do sistema indisponível).
class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({super.key, required this.error});
  final Object error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Consultório',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: Scaffold(
        backgroundColor: AppColors.cream,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.error_outline_rounded, size: 56, color: AppColors.danger),
                const SizedBox(height: 16),
                const Text(
                  'Não foi possível abrir os dados',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Nenhum dado foi apagado. Feche o app e abra de novo; se o erro '
                  'continuar, reinicie o aparelho e verifique se há espaço livre.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 18),
                SelectableText(
                  '$error',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
