import 'package:flutter/material.dart';

import 'data/db.dart';

/// 主题色预设
class AccentPreset {
  final String name;
  final Color color;
  /// 沉浸式辅助色（用于渐变、光晕）
  final Color glow;
  AccentPreset(this.name, this.color, this.glow);
}

List<AccentPreset> kAccentPresets = [
  AccentPreset('靛蓝', Color(0xFF5B9CFF), Color(0xFF8EC0FF)),
  AccentPreset('薄荷', Color(0xFF3ED9A4), Color(0xFF7CF6C6)),
  AccentPreset('紫罗兰', Color(0xFF9E7BFF), Color(0xFFC4ACFF)),
  AccentPreset('樱花', Color(0xFFFF7BA8), Color(0xFFFFB0CB)),
  AccentPreset('琥珀', Color(0xFFFFB340), Color(0xFFFFD089)),
  AccentPreset('青碧', Color(0xFF2BC8D9), Color(0xFF7FE4EF)),
  AccentPreset('赤霞', Color(0xFFFF6B5E), Color(0xFFFFA199)),
  AccentPreset('石青', Color(0xFF8FA3BF), Color(0xFFC2CEDE)),
];

/// 科目配色方案
class SubjectPreset {
  final String name;
  final List<Color> colors;
  SubjectPreset(this.name, this.colors);
}

List<SubjectPreset> kSubjectPresets = [
  SubjectPreset('多彩', [
    Color(0xFF5B9CFF),
    Color(0xFFFF8A65),
    Color(0xFF4DD0E1),
    Color(0xFFBA68C8),
    Color(0xFF81C784),
    Color(0xFFFFD54F),
    Color(0xFFF06292),
    Color(0xFF9575CD),
  ]),
  SubjectPreset('柔和', [
    Color(0xFF8AB4F8),
    Color(0xFFF6A98A),
    Color(0xFF7FD8DE),
    Color(0xFFC9A3D8),
    Color(0xFFA8D8A8),
    Color(0xFFF2D98A),
    Color(0xFFF2A3B8),
    Color(0xFFB0A8E0),
  ]),
  SubjectPreset('冷调', [
    Color(0xFF5B9CFF),
    Color(0xFF2BC8D9),
    Color(0xFF3ED9A4),
    Color(0xFF7B8CFF),
    Color(0xFF5ED0E0),
    Color(0xFF48B8A8),
    Color(0xFF8FA3BF),
    Color(0xFF6C7BD9),
  ]),
  SubjectPreset('暖调', [
    Color(0xFFFF8A65),
    Color(0xFFFFB340),
    Color(0xFFFFD54F),
    Color(0xFFF06292),
    Color(0xFFFF6B5E),
    Color(0xFFE8A33D),
    Color(0xFFD98AA8),
    Color(0xFFB5734A),
  ]),
  SubjectPreset('荧光', [
    Color(0xFF39FF88),
    Color(0xFF00E5FF),
    Color(0xFFFFE83D),
    Color(0xFFFF5EDB),
    Color(0xFF7CF6A0),
    Color(0xFF4DD0FF),
    Color(0xFFFF9F1C),
    Color(0xFFB388FF),
  ]),
];

/// 全局可切换配色。启动时从数据库读回，切换后通过 [rev] 通知整棵树重建。
class Pal {
  Pal._();

  static int accIdx = 0;
  static int subIdx = 0;

  /// 是否深色模式
  static bool dark = true;

  // ── 深色中性色 ──
  static Color _dBg = Color(0xFF0F1115);
  static Color _dCard = Color(0xFF181B22);
  static Color _dCard2 = Color(0xFF20242D);
  static Color _dLine = Color(0xFF2A2F3A);
  static Color _dDim = Color(0xFF8B93A5);
  static Color _dFaint = Color(0xFF5C6474);

  // ── 浅色中性色 ──
  static Color _lBg = Color(0xFFF4F6FA);
  static Color _lCard = Color(0xFFFFFFFF);
  static Color _lCard2 = Color(0xFFEDF0F6);
  static Color _lLine = Color(0xFFDCE1EB);
  static Color _lDim = Color(0xFF5F6775);
  static Color _lFaint = Color(0xFF98A0AE);

  static Color get bg => dark ? _dBg : _lBg;
  static Color get card => dark ? _dCard : _lCard;
  static Color get card2 => dark ? _dCard2 : _lCard2;
  static Color get line => dark ? _dLine : _lLine;
  static Color get dim => dark ? _dDim : _lDim;
  static Color get faint => dark ? _dFaint : _lFaint;

  // 语义色：浅色下需要压暗才能在白底上看清
  static Color get danger =>
      dark ? Color(0xFFFF5D6C) : Color(0xFFD93025);
  static Color get warn =>
      dark ? Color(0xFFFFB340) : Color(0xFFC17600);
  static Color get ok =>
      dark ? Color(0xFF3ED9A4) : Color(0xFF0F9D6B);

  /// 版本号，递增即触发重建
  static final ValueNotifier<int> rev = ValueNotifier<int>(0);

  static AccentPreset get accentPreset => kAccentPresets[accIdx];
  static SubjectPreset get subjectPreset => kSubjectPresets[subIdx];

  static Color get acc => accentPreset.color;
  static Color get accGlow => accentPreset.glow;
  static List<Color> get subjects => subjectPreset.colors;

  /// 科目 → 稳定颜色（同一科目任何时候都是同一个色）
  static Color subjectColor(String s) {
    if (s.isEmpty) return kDimNeutral;
    var h = 0;
    for (final c in s.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return subjects[h % subjects.length];
  }
  static Future<void> load() async {
    final a = int.tryParse(await DB.i.getSetting('accent_idx') ?? '0') ?? 0;
    final s = int.tryParse(await DB.i.getSetting('subject_idx') ?? '0') ?? 0;
    final d = await DB.i.getSetting('dark_mode') ?? '1';
    accIdx = a.clamp(0, kAccentPresets.length - 1);
    subIdx = s.clamp(0, kSubjectPresets.length - 1);
    dark = d != '0';
  }

  /// 切换明暗模式
  static Future<void> setDark(bool v) async {
    if (v == dark) return;
    dark = v;
    await DB.i.setSetting('dark_mode', v ? '1' : '0');
    rev.value++;
  }


  static Future<void> setAccent(int i) async {
    final v = i.clamp(0, kAccentPresets.length - 1);
    if (v == accIdx) return;
    accIdx = v;
    await DB.i.setSetting('accent_idx', '$v');
    rev.value++;
  }

  static Future<void> setSubjectPreset(int i, {bool recolor = true}) async {
    final v = i.clamp(0, kSubjectPresets.length - 1);
    if (v == subIdx) return;
    subIdx = v;
    await DB.i.setSetting('subject_idx', '$v');
    if (recolor) {
      await DB.i.recolorLessons(colorOf: (s) => subjectColor(s).toARGB32());
    }
    rev.value++;
  }
}

/// 中性灰（跟随明暗），避免 palette 依赖 theme 造成循环引用
Color get kDimNeutral => Pal.dim;
