import 'package:flutter/material.dart';

import '../palette.dart';
import '../services/focus_guard.dart';
import '../services/focus_lock.dart';
import '../theme.dart';

/// 白名单管理。规则：最多 50 个，每天最多改 5 次。
///
/// 应用清单和图标都由原生侧给（走 planbox/focus 通道），
/// 所以不需要 device_apps 之类的插件，少一个原生依赖就少一份构建风险。
class WhitelistPage extends StatefulWidget {
  const WhitelistPage({super.key});

  static Future<void> open(BuildContext context) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const WhitelistPage()),
    );
  }

  @override
  State<WhitelistPage> createState() => _WhitelistPageState();
}

class _WhitelistPageState extends State<WhitelistPage> {
  List<LockApp> _apps = const [];
  List<WhitelistEntry> _chosen = const [];
  int _editsLeft = FocusGuard.dailyEdits;
  bool _loading = true;
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final chosen = await FocusGuard.whitelist();
    final left = await FocusGuard.editsLeft();
    List<LockApp> apps;
    if (FocusLock.available) {
      apps = await FocusLock.listApps();
    } else {
      apps = const [];
    }
    if (!mounted) return;
    setState(() {
      _apps = apps;
      _chosen = chosen;
      _editsLeft = left;
      _loading = false;
    });
  }

  bool _isChosen(String pkg) => _chosen.any((e) => e.package == pkg);

  Future<void> _toggle(LockApp app) async {
    if (_loading) return;
    final chosen = _isChosen(app.package);
    if (!chosen && _chosen.length >= FocusGuard.maxWhitelist) {
      _toast('白名单最多 ${FocusGuard.maxWhitelist} 个，先删掉几个吧');
      return;
    }
    if (_editsLeft <= 0) {
      _toast('今天已经改了 ${FocusGuard.dailyEdits} 次，明天再来');
      return;
    }
    if (!await FocusGuard.consumeEdit()) {
      if (!mounted) return;
      setState(() => _editsLeft = 0);
      _toast('今天已经改了 ${FocusGuard.dailyEdits} 次，明天再来');
      return;
    }
    final next = List<WhitelistEntry>.from(_chosen);
    if (chosen) {
      next.removeWhere((e) => e.package == app.package);
    } else {
      next.add(WhitelistEntry(app.package, app.label));
    }
    await FocusGuard.saveWhitelist(next);
    if (!mounted) return;
    setState(() {
      _chosen = next;
      _editsLeft = _editsLeft - 1 < 0 ? 0 : _editsLeft - 1;
    });
  }

  void _toast(String s) {
    if (!mounted) return;
    final m = ScaffoldMessenger.maybeOf(context);
    m?.clearSnackBars();
    m?.showSnackBar(
      SnackBar(
        content: Text(s),
        behavior: SnackBarBehavior.floating,
        backgroundColor: kCard,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = _filter.isEmpty
        ? _apps
        : _apps
            .where((a) =>
                a.label.toLowerCase().contains(_filter.toLowerCase()) ||
                a.package.toLowerCase().contains(_filter.toLowerCase()))
            .toList();
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        elevation: 0,
        foregroundColor: kFg,
        title: Text('专注白名单',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: kFg)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                '${_chosen.length}/${FocusGuard.maxWhitelist}',
                style: TextStyle(fontSize: 12, color: kDim),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 14, color: kDim),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '专注时这些应用不会被拦。今天还能改 $_editsLeft 次',
                    style: TextStyle(fontSize: 11.5, color: kDim),
                  ),
                ),
              ],
            ),
          ),
          if (_chosen.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final e in _chosen)
                      InputChip(
                        label: Text(e.label,
                            style: TextStyle(fontSize: 11, color: kFg)),
                        backgroundColor: kAcc.withValues(alpha: 0.12),
                        side: BorderSide(color: kAcc.withValues(alpha: 0.3)),
                        onDeleted: _editsLeft <= 0
                            ? null
                            : () async {
                                final app = LockApp(e.package, e.label, null);
                                await _toggle(app);
                              },
                      ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: TextField(
              style: TextStyle(fontSize: 13, color: kFg),
              decoration: InputDecoration(
                isDense: true,
                hintText: '搜应用名或包名',
                hintStyle: TextStyle(fontSize: 13, color: kDim),
                prefixIcon: Icon(Icons.search, size: 18, color: kDim),
                filled: true,
                fillColor: kCard.withValues(alpha: 0.6),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (v) => setState(() => _filter = v.trim()),
            ),
          ),
          Expanded(
            child: _loading
                ? Center(child: CircularProgressIndicator(color: kAcc))
                : list.isEmpty
                    ? Center(
                        child: Text(
                          _apps.isEmpty
                              ? '读不到应用列表（需要在本体 App 里运行）'
                              : '没有匹配的应用',
                          style: TextStyle(fontSize: 12.5, color: kDim),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 24),
                        itemCount: list.length,
                        itemBuilder: (_, i) {
                          final a = list[i];
                          final on = _isChosen(a.package);
                          return ListTile(
                            dense: true,
                            leading: a.icon != null
                                ? Image.memory(
                                    a.icon!,
                                    width: 34,
                                    height: 34,
                                    gaplessPlayback: true,
                                  )
                                : Icon(Icons.android, size: 30, color: kDim),
                            title: Text(
                              a.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 13.5, color: kFg),
                            ),
                            subtitle: Text(
                              a.package,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 10.5, color: kDim),
                            ),
                            trailing: Icon(
                              on
                                  ? Icons.check_circle
                                  : Icons.radio_button_unchecked,
                              size: 20,
                              color: on ? kAcc : kDim.withValues(alpha: 0.5),
                            ),
                            onTap: () => _toggle(a),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}