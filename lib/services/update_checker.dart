import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../pages/agreement.dart';

/// 一个新版本的信息。
class UpdateInfo {
  final String version; // 0.6.8
  final String tag; // v0.6.8
  final String notes; // release body
  final String url; // 原始 asset 直链
  final int size;

  const UpdateInfo({
    required this.version,
    required this.tag,
    required this.notes,
    required this.url,
    required this.size,
  });

  String get sizeText => size <= 0
      ? '未知大小'
      : '${(size / 1024 / 1024).toStringAsFixed(1)} MB';
}

/// 一条下载线路的测速结果。
class Mirror {
  final String name;
  final String url;
  final bool ok;
  final double kbps; // 预估速度，KB/s

  const Mirror(this.name, this.url, this.ok, this.kbps);
}

/// 检查更新 + 选最快下载线路。
///
/// 走 GitHub 的公开 REST API（不需要 token，未登录 60 次/小时够用了）。
/// 下载本身交给原生 DownloadManager，避免在 Dart 里手写大文件落盘和
/// FileProvider。
class UpdateChecker {
  UpdateChecker._();

  static const _repo = 'qiuchen520/planbox';

  /// 加速镜像。键是显示名，值是把原始直链变成镜像链。
  ///
  /// 这些站都是公开的 GitHub 反代，谁快谁慢各时段都不一样，
  /// 所以不写死顺序，一律现场测速。
  static const Map<String, String> _mirrorPrefix = {
    'ghproxy.net': 'https://ghproxy.net/',
    'gh-proxy.com': 'https://gh-proxy.com/',
    'ghfast.top': 'https://ghfast.top/',
    'gitmirror': 'https://hub.gitmirror.com/',
  };

  /// 查询最新版本；没有新版（或网络失败）返回 null。
  /// [error] 用来区分「已是最新」和「没网/被墙」。
  static Future<UpdateInfo?> latest({void Function(String)? error}) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.getUrl(
        Uri.parse('https://api.github.com/repos/$_repo/releases?per_page=10'),
      );
      req.headers.set('Accept', 'application/vnd.github+json');
      req.headers.set('User-Agent', 'PlanBox-updater');
      final res = await req.close().timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        error?.call('GitHub 返回 ${res.statusCode}');
        return null;
      }
      final body = await res.transform(utf8.decoder).join();
      final list = jsonDecode(body);
      if (list is! List) {
        error?.call('返回格式不认识');
        return null;
      }
      UpdateInfo? best;
      for (final r in list) {
        if (r is! Map) continue;
        final tag = '${r['tag_name'] ?? ''}';
        final ver = _parseVersion(tag);
        if (ver == null) continue;
        String? url;
        var size = 0;
        for (final a in (r['assets'] as List? ?? const [])) {
          if (a is! Map) continue;
          final name = '${a['name'] ?? ''}';
          if (!name.contains('arm64')) continue;
          url = '${a['browser_download_url'] ?? ''}';
          size = (a['size'] as num?)?.toInt() ?? 0;
        }
        if (url == null || url.isEmpty) continue;
        final info = UpdateInfo(
          version: ver,
          tag: tag,
          notes: '${r['body'] ?? ''}',
          url: url,
          size: size,
        );
        if (best == null || _compare(ver, best.version) > 0) best = info;
      }
      if (best == null) return null;
      if (_compare(best.version, About.version) <= 0) return null;
      return best;
    } catch (e) {
      error?.call('$e');
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// 给所有线路测速，按速度从快到慢返回。直连也在里面。
  static Future<List<Mirror>> rank(String url) async {
    final futures = <Future<Mirror>>[
      _probe('直连', url),
      for (final e in _mirrorPrefix.entries) _probe(e.key, e.value + url),
    ];
    final all = await Future.wait(futures);
    all.sort((a, b) => b.kbps.compareTo(a.kbps));
    // 快的排前面；不通的留着当兜底（万一探测被限速但实际能下）
    return all;
  }

  /// 抓 256 KB 看看这条线跑得动吗，顺便量速度
  static Future<Mirror> _probe(String name, String url) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 6);
    final sw = Stopwatch()..start();
    var got = 0;
    try {
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set('Range', 'bytes=0-262143');
      req.headers.set('User-Agent', 'PlanBox-updater');
      final res = await req.close().timeout(const Duration(seconds: 8));
      if (res.statusCode >= 400) {
        return Mirror(name, url, false, 0);
      }
      await for (final chunk in res.timeout(const Duration(seconds: 8))) {
        got += chunk.length;
        // 够判断速度了就收手，别真下完整个包
        if (got >= 262144) break;
      }
    } catch (_) {
      return Mirror(name, url, false, 0);
    } finally {
      sw.stop();
      client.close(force: true);
    }
    final sec = sw.elapsedMilliseconds / 1000.0;
    final kbps = sec <= 0 ? 0.0 : (got / 1024.0) / sec;
    return Mirror(name, url, got >= 64 * 1024, kbps);
  }

  // ── 下载（原生 DownloadManager） ────────────────────
  static const _ch = MethodChannelCenter.channel;

  static Future<int> enqueue(String url, String fileName) async {
    final id = await _ch.invokeMethod<int>('apkEnqueue', {
      'url': url,
      'name': fileName,
    });
    return id ?? -1;
  }

  static Future<Map<String, dynamic>> status() async {
    final raw = await _ch.invokeMethod<Map>('apkStatus');
    if (raw == null) return <String, dynamic>{};
    return raw.map((k, v) => MapEntry(k.toString(), v));
  }

  /// 拉起系统安装器。
  ///
  /// 返回 ok=已拉起 / perm=缺「安装未知应用」授权（已跳设置）/ fail=失败。
  static Future<String> install() async =>
      await _ch.invokeMethod<String>('apkInstall') ?? 'fail';

  // ── 版本比较 ──────────────────────────────────────
  static String? _parseVersion(String tag) {
    var s = tag.trim();
    if (s.startsWith('v') || s.startsWith('V')) s = s.substring(1);
    // 只取前面数字点的部分：0.6.8 / 0.6.8+25 / 0.6.8-beta
    final m = RegExp(r'^(\d+(?:\.\d+)*)').firstMatch(s);
    return m?.group(1);
  }

  static int _compare(String a, String b) {
    final pa = a.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final pb = b.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final n = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < n; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x.compareTo(y);
    }
    return 0;
  }
}

/// 只为了拿 MethodChannel，避免各处重复写频道名。
class MethodChannelCenter {
  MethodChannelCenter._();
  static const channel = MethodChannel('planbox/focus');
}
