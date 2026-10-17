import 'package:flutter/material.dart';

import 'palette.dart';

// ── 中性表面色（跟随明暗模式）───────────────────────
// 注意：这些必须是 getter 而不是 const，
// 否则切换明暗后已构建的 widget 不会变色。
Color get kBg => Pal.bg;
Color get kCard => Pal.card;
Color get kCard2 => Pal.card2;
Color get kLine => Pal.line;
Color get kDim => Pal.dim;
Color get kFaint => Pal.faint;

// ── 语义色 ──────────────────────────────────────────
Color get kDanger => Pal.danger;
Color get kWarn => Pal.warn;
Color get kOk => Pal.ok;

/// 当前主题色。用 getter 而不是常量，这样切换配色后所有引用自动生效。
Color get kAcc => Pal.acc;

/// 主色上的前景色：深色主题用近黑，浅色主题用白
Color get kOnAcc => Pal.dark ? Color(0xFF08111F) : Colors.white;

/// 正文前景色
Color get kFg => Pal.dark ? Color(0xFFE9ECF2) : Color(0xFF111827);

/// 当前科目色板
List<Color> get kSubjectColors => Pal.subjects;

ThemeData buildTheme() {
  final acc = Pal.acc;
  final dark = Pal.dark;
  final fg = kFg;

  final scheme = ColorScheme.fromSeed(
    seedColor: acc,
    brightness: dark ? Brightness.dark : Brightness.light,
  ).copyWith(
    primary: acc,
    secondary: acc,
    surface: kCard,
    onSurface: fg,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: dark ? Brightness.dark : Brightness.light,
    colorScheme: scheme,
    scaffoldBackgroundColor: kBg,
    cardColor: kCard,
    dividerColor: kLine,
    canvasColor: kCard,
    iconTheme: IconThemeData(color: fg),
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: kBg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      iconTheme: IconThemeData(color: fg),
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: fg,
      ),
    ),
    cardTheme: CardThemeData(
      color: kCard,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: kLine),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: kCard,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
          fontSize: 18, fontWeight: FontWeight.w700, color: fg),
      contentTextStyle: TextStyle(fontSize: 14, color: fg),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: kCard,
      surfaceTintColor: Colors.transparent,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: acc,
      foregroundColor: kOnAcc,
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: kCard,
      selectedItemColor: acc,
      unselectedItemColor: kDim,
      type: BottomNavigationBarType.fixed,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: kCard,
      indicatorColor: acc.withValues(alpha: dark ? 0.18 : 0.14),
      elevation: 0,
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          color: s.contains(WidgetState.selected) ? acc : kDim,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: kLine),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: kLine),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: acc, width: 1.4),
      ),
      labelStyle: TextStyle(color: kDim),
      hintStyle: TextStyle(color: kFaint),
      isDense: true,
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      side: BorderSide(color: kDim, width: 1.6),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: dark ? kCard2 : Color(0xFF2B303B),
      contentTextStyle: TextStyle(color: Colors.white, fontSize: 13),
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
      textStyle: TextStyle(fontSize: 14, color: fg),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: kDim,
      textColor: fg,
    ),
    dividerTheme: DividerThemeData(color: kLine, thickness: 1, space: 1),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: acc,
        foregroundColor: kOnAcc,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: acc),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12.5)),
        side: WidgetStatePropertyAll(BorderSide(color: kLine)),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? acc : kDim,
        ),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: acc),
  );
}

Color colorForSubject(String s) => Pal.subjectColor(s);

List<String> kSubjects = [
  '语文', '数学', '英语', '物理', '化学', '生物',
  '历史', '地理', '政治', '体育', '美术', '音乐', '信息', '自习',
];
