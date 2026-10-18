import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';

/// 一个已安装的可启动应用（名字 + 图标）
class LockApp {
  final String package;
  final String label;
  final Uint8List? icon;

  const LockApp(this.package, this.label, this.icon);

  static LockApp? fromMap(dynamic raw) {
    if (raw is! Map) return null;
    final p = raw['package'] as String?;
    if (p == null || p.isEmpty) return null;
    final label = (raw['label'] as String?) ?? p;
    Uint8List? bytes;
    final b64 = raw['icon'] as String?;
    if (b64 != null && b64.isNotEmpty) {
      try {
        bytes = base64Decode(b64);
      } catch (_) {
        bytes = null;
      }
    }
    return LockApp(p, label, bytes);
  }
}

/// 专注锁的原生能力封装（安卓端实现见 android_src/OverlayService.kt）。
///
/// 全部方法都做了兜底：插件不存在 / 平台报错时返回安全默认值，
/// 这样在非安卓环境（测试、桌面）里调用不会炸。
class FocusLock {
  static const MethodChannel _ch = MethodChannel('planbox/focus');
  static bool _nativeOk = true;

  /// 原生侧是否是可用状态（被调过一次并失败就置 false，后续直接短路）
  static bool get available => _nativeOk;

  static Future<T?> _call<T>(String method, [Map<String, dynamic>? args]) async {
    if (!_nativeOk) return null;
    try {
      return await _ch.invokeMethod<T>(method, args);
    } on MissingPluginException {
      _nativeOk = false;
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// 「使用情况访问」权限是否已授予
  static Future<bool> canUsage() async => await _call<bool>('canUsage') ?? false;

  /// 「显示在其他应用上层」权限是否已授予
  static Future<bool> canOverlay() async => await _call<bool>('canOverlay') ?? false;

  static Future<void> openUsageSettings() => _call<bool>('openUsage');

  /// 是否已加入电池优化白名单（不加的话后台服务容易被定制 ROM 掐掉）
  static Future<bool> ignoringBattery() async =>
      await _call<bool>('ignoringBattery') ?? true;

  static Future<void> openBatterySettings() => _call<bool>('openBattery');

  /// 打开系统里的「应用信息」页，权限入口不好找时当最后兜底
  static Future<void> openAppDetails() => _call<bool>('openAppDetails');

  static Future<void> openOverlaySettings() => _call<bool>('openOverlay');

  static Future<void> start(int minutes) =>
      _call<bool>('start', {'minutes': minutes});

  static Future<void> stop() => _call<bool>('stop');

  static Future<bool> isRunning() async => await _call<bool>('isRunning') ?? false;

  /// 自检：服务在不在跑、权限到底认不认、最近看到的前台是哪个
  static Future<Map<String, dynamic>> diag() async {
    final raw = await _call<Map>('diag');
    if (raw == null) return <String, dynamic>{};
    return raw.map((k, v) => MapEntry(k.toString(), v));
  }

  static Future<void> setWhitelist(List<String> packages) =>
      _call<bool>('setWhitelist', {'packages': packages});

  /// 已安装应用清单（含图标）。第一次调用会比较慢（要逐个取图标）。
  static Future<List<LockApp>> listApps() async {
    final raw = await _call<List<dynamic>>('listApps') ?? const [];
    final out = <LockApp>[];
    for (final e in raw) {
      final a = LockApp.fromMap(e);
      if (a != null) out.add(a);
    }
    return out;
  }
}
