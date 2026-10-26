import 'package:flutter/material.dart';

/// Paleta inspirada na referência do cliente: fundo creme, cartões com
/// contorno escuro, cabeçalhos em tons pastel e barra inferior amarela.
class AppColors {
  static const cream = Color(0xFFFBF6EE);
  static const surface = Color(0xFFFFFCF7);
  static const ink = Color(0xFF2A2623);
  static const muted = Color(0xFF7D746D);
  static const hairline = Color(0xFFE6DDD2);

  static const green = Color(0xFFA9D8B8);
  static const greenSoft = Color(0xFFDCEFE2);
  static const salmon = Color(0xFFF2A394);
  static const salmonSoft = Color(0xFFFADDD6);
  static const purple = Color(0xFFCDB8E6);
  static const purpleSoft = Color(0xFFECE3F6);
  static const yellow = Color(0xFFF6C453);
  static const yellowSoft = Color(0xFFFCEBC0);
  static const blue = Color(0xFFAFCDEB);
  static const blueSoft = Color(0xFFDFEBF7);

  static const danger = Color(0xFFC8443C);
  static const dangerSoft = Color(0xFFF8D9D5);
  static const ok = Color(0xFF3E8E5E);
  static const okSoft = Color(0xFFDCEFE2);
  static const warn = Color(0xFFB7791F);
  static const warnSoft = Color(0xFFFCEBC0);

  /// Cores disponíveis para linhas de cuidado.
  static const careLinePalette = <Color>[
    Color(0xFFF2A394),
    Color(0xFF8FC9A3),
    Color(0xFFB9A2DE),
    Color(0xFFF6C453),
    Color(0xFF8DB8E3),
    Color(0xFFE79BC0),
    Color(0xFF9FD3D0),
    Color(0xFFD3B58F),
  ];
}

/// Cor de destaque de cada seção (forte para o cabeçalho, suave para fundos).
class Accent {
  const Accent(this.strong, this.soft);
  final Color strong;
  final Color soft;

  static const agenda = Accent(AppColors.green, AppColors.greenSoft);
  static const patients = Accent(AppColors.salmon, AppColors.salmonSoft);
  static const reminders = Accent(AppColors.purple, AppColors.purpleSoft);
  static const dashboard = Accent(AppColors.blue, AppColors.blueSoft);
  static const settings = Accent(AppColors.yellow, AppColors.yellowSoft);
}

const kRadius = 20.0;
const kBorder = BorderSide(color: AppColors.ink, width: 1.5);

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.yellow,
    brightness: Brightness.light,
    primary: AppColors.ink,
    onPrimary: Colors.white,
    surface: AppColors.surface,
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.cream,
  );
  final inputBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: const BorderSide(color: AppColors.ink, width: 1.3),
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: AppColors.ink,
      displayColor: AppColors.ink,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.cream,
      foregroundColor: AppColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        color: AppColors.ink,
        fontSize: 15,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.2,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: inputBorder,
      enabledBorder: inputBorder,
      focusedBorder: inputBorder.copyWith(
        borderSide: const BorderSide(color: AppColors.ink, width: 2.2),
      ),
      errorBorder: inputBorder.copyWith(
        borderSide: const BorderSide(color: AppColors.danger, width: 1.6),
      ),
      labelStyle: const TextStyle(color: AppColors.muted),
      floatingLabelStyle: const TextStyle(
        color: AppColors.ink,
        fontWeight: FontWeight.w600,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.ink,
        foregroundColor: Colors.white,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.ink,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        side: kBorder,
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.ink,
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.yellow,
      foregroundColor: AppColors.ink,
      elevation: 2,
      shape: StadiumBorder(side: kBorder),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.ink,
    ),
    dividerTheme: const DividerThemeData(color: AppColors.hairline, space: 1),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? AppColors.ink
            : AppColors.hairline,
      ),
      thumbColor: WidgetStateProperty.all(Colors.white),
    ),
  );
}
