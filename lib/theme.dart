import 'package:flutter/material.dart';

import 'palette.dart';

// ── 中性表面色（固定，不随主题色变化）────────────────
const Color kBg = Color(0xFF0F1115);
const Color kCard = Color(0xFF181B22);
const Color kCard2 = Color(0xFF20242D);
const Color kLine = Color(0xFF2A2F3A);
const Color kDim = Color(0xFF8B93A5);
const Color kFaint = Color(0xFF5C6474);

// ── 语义色 ──────────────────────────────────────────
const Color kDanger = Color(0xFFFF5D6C);
const Color kWarn = Color(0xFFFFB340);
const Color kOk = Color(0xFF3ED9A4);

/// 当前主题色。用 getter 而不是常量，这样切换配色后所有引用自动生效。
Color get kAcc => Pal.acc;

/// 当前科目色板
List<Color> get kSubjectColors => Pal.subjects;

ThemeData buildTheme() {
  final acc = Pal.acc;
  final scheme = ColorScheme.fromSeed(
    seedColor: acc,
    brightness: Brightness.dark,
  ).copyWith(
    primary: acc,
    secondary: acc,
    surface: kCard,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: kBg,
    cardColor: kCard,
    dividerColor: kLine,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: const AppBarTheme(
      backgroundColor: kBg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: Colors.white,
      ),
    ),
    cardTheme: CardThemeData(
      color: kCard,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: kLine),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: kCard,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: kCard,
      surfaceTintColor: Colors.transparent,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: acc,
      foregroundColor: const Color(0xFF08111F),
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: kCard,
      selectedItemColor: acc,
      unselectedItemColor: kDim,
      type: BottomNavigationBarType.fixed,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: kCard,
      indicatorColor: acc.withValues(alpha: 0.18),
      elevation: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kLine),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kLine),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: acc, width: 1.4),
      ),
      isDense: true,
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      side: const BorderSide(color: kDim, width: 1.6),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: kCard2,
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: 13),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: acc,
      selectionColor: acc.withValues(alpha: 0.3),
      selectionHandleColor: acc,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: kCard2,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: acc,
        foregroundColor: const Color(0xFF08111F),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: acc),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 12.5)),
        side: const WidgetStatePropertyAll(BorderSide(color: kLine)),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: acc),
  );
}

Color colorForSubject(String s) => Pal.subjectColor(s);

const List<String> kSubjects = [
  '语文', '数学', '英语', '物理', '化学', '生物',
  '历史', '地理', '政治', '体育', '美术', '音乐', '信息', '自习',
];
