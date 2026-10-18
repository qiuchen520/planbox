import 'dart:convert';

import '../data/db.dart';
import 'focus_lock.dart';

/// 白名单条目（包名 + 显示名）。图标不存库，用的时候现取。
class WhitelistEntry {
  final String package;
  final String label;

  const WhitelistEntry(this.package, this.label);
}

/// 专注守护的状态机。数据全部落在 setting 表里（跟着备份一起走）。
///
/// 三条关键记录：
/// - `focus_active`    = '1' 表示「有一轮专注本该在守护中」
/// - `focus_active_at` = 开始时间戳，用来识别「忘了收尾」的老记录
/// - `focus_violation` = 检测到的违规原因，等下次打开 App 弹惩罚页
class FocusGuard {
  /// 白名单上限
  static const int maxWhitelist = 50;

  /// 每天允许改动白名单的次数
  static const int dailyEdits = 5;

  static const _kActive = 'focus_active';
  static const _kActiveAt = 'focus_active_at';
  static const _kViolation = 'focus_violation';
  static const _kWhitelist = 'focus_whitelist';
  static const _kDay = 'focus_wl_day';
  static const _kCount = 'focus_wl_count';

  // ── 会话启停 ─────────────────────────────────────────

  /// 开始一轮守护。权限不齐时返回 false，调用方应先去引导授权。
  static Future<bool> begin(int minutes) async {
    final usage = await FocusLock.canUsage();
    final overlay = await FocusLock.canOverlay();
    if (!usage || !overlay) return false;
    await DB.i.setSetting(_kActive, '1');
    await DB.i.setSetting(
      _kActiveAt,
      '${DateTime.now().millisecondsSinceEpoch}',
    );
    await pushWhitelist();
    await FocusLock.start(minutes);
    return true;
  }

  /// 正常收工：清标记 + 停服务
  static Future<void> end() async {
    await DB.i.setSetting(_kActive, '0');
    await FocusLock.stop();
  }

  /// 当前这轮还在守护中吗（页面回来时用）
  static Future<bool> isActive() async =>
      (await DB.i.getSetting(_kActive)) == '1';

  // ── 白名单 ───────────────────────────────────────────

  static Future<List<WhitelistEntry>> whitelist() async {
    final raw = await DB.i.getSetting(_kWhitelist);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return [];
      final out = <WhitelistEntry>[];
      for (final e in list) {
        if (e is! Map) continue;
        final p = '${e['p'] ?? ''}';
        if (p.isEmpty) continue;
        out.add(WhitelistEntry(p, '${e['l'] ?? p}'));
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveWhitelist(List<WhitelistEntry> list) async {
    final capped = list.take(maxWhitelist).toList();
    await DB.i.setSetting(
      _kWhitelist,
      jsonEncode([
        for (final e in capped) {'p': e.package, 'l': e.label}
      ]),
    );
    await pushWhitelist();
  }

  /// 把白名单下发给原生（服务起来前、改完白名单后都要调）
  static Future<void> pushWhitelist() async {
    final list = await whitelist();
    await FocusLock.setWhitelist([for (final e in list) e.package]);
  }

  // ── 每日改动次数 ─────────────────────────────────────

  static String _todayKey() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-'
        '${n.day.toString().padLeft(2, '0')}';
  }

  /// 今天还剩几次可改
  static Future<int> editsLeft() async {
    final day = await DB.i.getSetting(_kDay);
    if (day != _todayKey()) return dailyEdits;
    final used = int.tryParse(await DB.i.getSetting(_kCount) ?? '0') ?? 0;
    final left = dailyEdits - used;
    return left < 0 ? 0 : left;
  }

  /// 消耗一次改动额度；返回 false 表示今天已经用完了
  static Future<bool> consumeEdit() async {
    final day = await DB.i.getSetting(_kDay);
    var used = 0;
    if (day == _todayKey()) {
      used = int.tryParse(await DB.i.getSetting(_kCount) ?? '0') ?? 0;
    }
    if (used >= dailyEdits) return false;
    await DB.i.setSetting(_kDay, _todayKey());
    await DB.i.setSetting(_kCount, '${used + 1}');
    return true;
  }

  // ── 违规检测 ─────────────────────────────────────────

  /// 回到 App 时调用。返回违规原因（'killed' / 'permission'），没有则 null。
  ///
  /// 判定逻辑：标记还是「守护中」，但原生服务已经不在跑了 —— 要么被杀，
  /// 要么权限被撤（服务会自己退出），两种都算偷偷溜走。
  static Future<String?> pollViolation() async {
    if ((await DB.i.getSetting(_kActive)) != '1') return null;

    final at = int.tryParse(await DB.i.getSetting(_kActiveAt) ?? '') ?? 0;
    // 超过 3 小时的老账不追究，免得隔天打开就挨骂
    if (at > 0 &&
        DateTime.now().millisecondsSinceEpoch - at > 3 * 3600 * 1000) {
      await DB.i.setSetting(_kActive, '0');
      return null;
    }

    // 长按幕布紧急退出是设计好的正规出口，不能算「偷跑」。
    // 原生落过时间戳，只要这轮开始时间不晚于它，就认这轮是主动结束的。
    final emergencyAt = await FocusLock.emergencyAt();
    if (emergencyAt > 0 &&
        DateTime.now().millisecondsSinceEpoch - emergencyAt < 6 * 3600 * 1000 &&
        (at == 0 || emergencyAt >= at)) {
      await DB.i.setSetting(_kActive, '0');
      await DB.i.setSetting(_kViolation, '');
      return null;
    }
    if (await FocusLock.isRunning()) return null;

    final usage = await FocusLock.canUsage();
    final overlay = await FocusLock.canOverlay();
    await DB.i.setSetting(_kActive, '0');
    final reason = (!usage || !overlay) ? 'permission' : 'killed';
    await DB.i.setSetting(_kViolation, reason);
    return reason;
  }

  /// 待处理的违规（上次没处理完的）
  static Future<String?> pendingViolation() => DB.i.getSetting(_kViolation);

  static Future<void> clearViolation() async {
    await DB.i.setSetting(_kViolation, '');
  }

  /// 两个特殊权限是否都齐了
  static Future<bool> hasAllPermissions() async {
    final usage = await FocusLock.canUsage();
    if (!usage) return false;
    return FocusLock.canOverlay();
  }

  /// 依次引导开两个权限
  static Future<void> openPermissionFlow() async {
    if (!await FocusLock.canUsage()) {
      await FocusLock.openUsageSettings();
      return;
    }
    if (!await FocusLock.canOverlay()) {
      await FocusLock.openOverlaySettings();
    }
  }
}