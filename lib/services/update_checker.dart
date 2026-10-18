import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../pages/agreement.dart';

/// 一个新版本的信息。
class UpdateInfo {
  final String version; // 0.6.9
  final String tag; // v0.6.9-build73
  final String notes; // release 说明（拿不到就为空）
  final String url; // GitHub 原始直链（加速线由 rank() 拼前缀）
  final int size; // 字节，0 = 未知

  const UpdateInfo({
    required this.version,
    required this.tag,
    required this.notes,
    required this.url,
    required this.size,
  });

  String get sizeText =>
      size <= 0 ? '大小未知' : '${(size / 1024 / 1024).toStringAsFixed(1)} MB';
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
/// 刻意**不用 GitHub API**：
/// 1. 公开仓库的 Release 匿名就能下，本来就不需要 token；
/// 2. 未登录的 API 每小时只有 60 次，还容易被限；
/// 3. 最关键的是——这台平板上 `api.github.com` 直接被 DNS 拦掉
///    （SocketException: Failed host lookup），而 `github.com` 能解析。
///
/// 所以走网页那条路：
///     GET https://github.com/OWNER/REPO/releases/latest
/// 它会 302 到 /releases/tag/<tag>，从 Location 里就能读到最新 tag；
/// 资源直链是稳定格式，不用查 asset id：
///     https://github.com/OWNER/REPO/releases/download/<tag>/<asset>
class UpdateChecker {
  UpdateChecker._();

  static const _repo = 'qiuchen520/planbox';

  /// CI 打出来的 arm64 包名固定，直接按名字取，省掉列 assets 的接口。
  static const _asset = 'app-arm64-v8a-release.apk';

  /// 加速镜像。键是显示名，值是把原始直链变成镜像链。
  /// 这些都是公开的 GitHub 反代，各时段快慢不一样，所以现场测速，不写死顺序。
  static const Map<String, String> _mirrorPrefix = {
    'ghproxy.net': 'https://ghproxy.net/',
    'gh-proxy.com': 'https://gh-proxy.com/',
    'ghfast.top': 'https://ghfast.top/',
    'gitmirror': 'https://hub.gitmirror.com/',
  };

  // ── 查询最新版本 ─────────────────────────────────────

  /// 有新版返回信息，没有新版（或压根没网）返回 null。
  /// [error] 只在「本该成功却失败」时调用，用来区分「已是最新」。
  static Future<UpdateInfo?> latest({void Function(String)? error}) async {
    // 先问 releases/latest（会 302 到 /releases/tag/<tag>）；
    // 万一仓库里最新那条被标成了 prerelease，latest 会 404，
    // 那就退一步去 releases 列表页抓第一条 —— 页面里的链接格式完全一样。
    final pages = <String>[
      'https://github.com/$_repo/releases/latest',
      'https://github.com/$_repo/releases',
    ];
    String? tag;
    for (final page in pages) {
      tag = await _latestTagFrom(page);
      if (tag != null) break;
      // 直连被墙时，借用加速器去取同一个页面
      for (final p in _mirrorPrefix.values) {
        tag = await _latestTagFrom('$p$page');
        if (tag != null) break;
      }
      if (tag != null) break;
    }

    if (tag == null) {
      final r = await _apiFallback();
      if (r != null) {
        if (_compare(r.version, About.version) <= 0) return null;
        return r;
      }
      error?.call('直连、4 条加速线路、API 都没通。确认一下是不是断网了，'
          '或者过一会儿再点重试。');
      return null;
    }
    final ver = _parseVersion(tag);
    if (ver == null) {
      error?.call('读到的版本号看不懂：$tag');
      return null;
    }
    // 当前版本已经 >= 最新，就是「已是最新」，不算失败
    if (_compare(ver, About.version) <= 0) return null;
    final url = 'https://github.com/$_repo/releases/download/$tag/$_asset';
    return UpdateInfo(
      version: ver,
      tag: tag,
      notes: '',
      url: url,
      // 大小只用来画进度条，拿不到就当成未知，不影响下载
      size: await _sizeOf(url),
    );
  }
  /// 用 HEAD 问一下这个 apk 有多大。直连不行就借第一条加速线问，
  /// 全都问不到返回 0（界面上就是「大小未知」+ 不确定进度条）。
  static Future<int> _sizeOf(String url) async {
    final tries = <String>[url];
    final first = _mirrorPrefix.values.first;
    tries.add('$first$url');
    for (final u in tries) {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 5);
      try {
        final req = await client.headUrl(Uri.parse(u));
        req.headers.set('User-Agent', 'PlanBox-updater');
        final res = await req.close().timeout(const Duration(seconds: 6));
        final len = res.contentLength;
        if (len > 0) return len;
      } catch (_) {
        // 换下一个
      } finally {
        client.close(force: true);
      }
    }
    return 0;
  }

  /// 读 releases/latest 的 302 Location，从里面抠出 tag。
  static Future<String?> _latestTagFrom(String url) async {
    try {
      return await _fetchTag(url);
    } catch (_) {
      return null;
    }
  }

  /// 返回 tag；没有重定向就试着从网页正文里找。
  static Future<String?> _fetchTag(String url) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client.getUrl(Uri.parse(url));
      req.followRedirects = false;
      req.headers.set('User-Agent', 'Mozilla/5.0 PlanBox-updater');
      req.headers.set('Accept', 'text/html,application/xhtml+xml');
      final res = await req.close().timeout(const Duration(seconds: 12));
      final loc = res.headers.value('location') ?? '';
      final body = await res.transform(utf8.decoder).join();
      return _tagFromText(loc) ?? _tagFromText(body);
    } on SocketException {
      // 域名解析不了：直接问 DoH 要 IP，然后拿 IP 连、Host 头写回原域名
      final host = Uri.parse(url).host;
      final ip = await _dohLookup(host);
      if (ip == null) rethrow;
      return _fetchTagViaIp(url, ip);
    } finally {
      client.close(force: true);
    }
  }

  static Future<String?> _fetchTagViaIp(String url, String ip) async {
    final u = Uri.parse(url);
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      // 用 IP 直连时证书必然对不上域名，这里放行；只用于读公开的发布页
      ..badCertificateCallback = (_, __, ___) => true;
    try {
      final req = await client.getUrl(u.replace(host: ip));
      req.followRedirects = false;
      req.headers.set(HttpHeaders.hostHeader, u.host);
      req.headers.set('User-Agent', 'Mozilla/5.0 PlanBox-updater');
      req.headers.set('Accept', 'text/html,application/xhtml+xml');
      final res = await req.close().timeout(const Duration(seconds: 12));
      final loc = res.headers.value('location') ?? '';
      final body = await res.transform(utf8.decoder).join();
      return _tagFromText(loc) ?? _tagFromText(body);
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// 从任意文本里找出**版本最高**的那个 tag。
  /// 列表页上会出现好几个版本，按版本号比一遍，别被页面上别的链接带偏。
  static String? _tagFromText(String text) {
    String? best;
    var from = 0;
    while (true) {
      final i = text.indexOf('/releases/tag/', from);
      if (i < 0) break;
      from = i + '/releases/tag/'.length;
      var rest = text.substring(from);
      for (final stop in ['"', "'", ' ', '\n', '\r', '?', '#', '<']) {
        final j = rest.indexOf(stop);
        if (j >= 0) rest = rest.substring(0, j);
      }
      final tag = Uri.decodeComponent(rest.trim());
      if (tag.isEmpty) continue;
      final v = _parseVersion(tag);
      if (v == null) continue;
      final bv = best == null ? null : _parseVersion(best);
      if (best == null || bv == null || _compare(v, bv) > 0) best = tag;
    }
    return best;
  }

  /// DNS over HTTPS：本地 DNS 不给答案时用，绕开污染。
  static Future<String?> _dohLookup(String host) async {
    const endpoints = [
      'https://223.5.5.5/resolve?name=@&type=A', // 阿里
      'https://1.12.12.12/resolve?name=@&type=A', // DNSPod
    ];
    for (final ep in endpoints) {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 6);
      try {
        final req = await client.getUrl(Uri.parse(ep.replaceAll('@', host)));
        req.headers.set('Accept', 'application/dns-json');
        final res = await req.close().timeout(const Duration(seconds: 8));
        if (res.statusCode != 200) continue;
        final body = await res.transform(utf8.decoder).join();
        final j = jsonDecode(body);
        final ans = (j is Map ? j['Answer'] : null) as List? ?? const [];
        for (final a in ans) {
          if (a is Map && a['type'] == 1 && a['data'] is String) {
            return a['data'] as String;
          }
        }
      } catch (_) {
        // 换下一个 DoH
      } finally {
        client.close(force: true);
      }
    }
    return null;
  }

  /// 最后的兜底：万一 github.com 不通而 API 通（有些网络正好反向），走一次 API。
  static Future<UpdateInfo?> _apiFallback() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.getUrl(
        Uri.parse('https://api.github.com/repos/$_repo/releases?per_page=10'),
      );
      req.headers.set('Accept', 'application/vnd.github+json');
      req.headers.set('User-Agent', 'PlanBox-updater');
      final res = await req.close().timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return null;
      final body = await res.transform(utf8.decoder).join();
      final list = jsonDecode(body);
      if (list is! List) return null;
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
      return best;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  // ── 测速 ─────────────────────────────────────────────

  /// 给所有线路测速，按速度从快到慢返回。直连也在里面。
  static Future<List<Mirror>> rank(String url) async {
    final futures = <Future<Mirror>>[
      _probe('直连', url),
      for (final e in _mirrorPrefix.entries) _probe(e.key, e.value + url),
    ];
    final all = await Future.wait(futures);
    all.sort((a, b) => b.kbps.compareTo(a.kbps));
    return all;
  }

  /// 抓 256 KB 看看这条线跑不跑得动，顺便量速度
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
      if (res.statusCode >= 400) return Mirror(name, url, false, 0);
      await for (final chunk in res.timeout(const Duration(seconds: 8))) {
        got += chunk.length;
        if (got >= 262144) break; // 够判断速度就收手
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

  // ── 下载（原生 DownloadManager） ─────────────────────

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
  /// 返回 ok=已拉起 / perm=缺「安装未知应用」授权（已跳设置）/ fail=失败。
  static Future<String> install() async =>
      await _ch.invokeMethod<String>('apkInstall') ?? 'fail';

  // ── 版本号解析与比较 ─────────────────────────────────

  /// 只取开头「数字.数字…」那一段。
  ///
  /// CI 的 tag 形如 `v0.6.9-build73`，减号后面是构建号，不属于版本；
  /// 老的 `v0.5.0-build71` 会被解析成 0.5.0，正确地小于 0.6.x，
  /// 所以不会把开发构建误判成新版本。
  static String? _parseVersion(String tag) {
    var s = tag.trim();
    if (s.startsWith('v') || s.startsWith('V')) s = s.substring(1);
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