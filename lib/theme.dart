import 'package:flutter/material.dart';

const Color kBg = Color(0xFF0F1115);
const Color kCard = Color(0xFF181B22);
const Color kCard2 = Color(0xFF20242D);
const Color kLine = Color(0xFF2A2F3A);
const Color kAcc = Color(0xFF5B9CFF);
const Color kDim = Color(0xFF8B93A5);

const List<Color> kSubjectColors = [
  Color(0xFF5B9CFF),
  Color(0xFFFF8A65),
  Color(0xFF4DD0E1),
  Color(0xFFBA68C8),
  Color(0xFF81C784),
  Color(0xFFFFD54F),
  Color(0xFFF06292),
  Color(0xFF9575CD),
];

ThemeData buildTheme() => ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: kAcc,
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: kBg,
      cardColor: kCard,
      dividerColor: kLine,
      fontFamily: null,
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
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: kCard,
        selectedItemColor: kAcc,
        unselectedItemColor: kDim,
        type: BottomNavigationBarType.fixed,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        isDense: true,
      ),
    );

Color colorForSubject(String s) {
  var h = 0;
  for (final c in s.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return kSubjectColors[h % kSubjectColors.length];
}

const List<String> kSubjects = [
  '语文', '数学', '英语', '物理', '化学', '生物',
  '历史', '地理', '政治', '体育', '美术', '音乐', '信息', '自习',
];
