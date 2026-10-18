import 'package:flutter/material.dart';

import '../palette.dart';
import '../services/focus_guard.dart';
import '../services/focus_lock.dart';
import '../theme.dart';

/// 白名单管理。规则：最多 50 个，每天最多保存 5 次。
///
/// 交互改成「先点后存」：勾选只改本地草稿，点右上角「保存」才写库并消耗一次
/// 额度。这样点错了不用白扣次数，也避免每点一下都去写数据库。
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
  /// 正在编辑的草稿（顺序即显示顺序）
  List<WhitelistEntry> _draft = [];
  int _editsLeft = FocusGuard.dailyEdits;
  bool _loading = true;
  bool _dirty = false;
  bool _saving = false;
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final chosen = await FocusGuard.whitelist();
    final left = await FocusGuard.editsLeft();
    final apps = FocusLock.available ? await FocusLock.listApps() : <LockApp>[];
    if (!mounted) return;
    setState(() {
      _apps = apps;
      _draft = List<WhitelistEntry>.from(chosen);
      _editsLeft = left;
      _loading = false;
      _dirty = false;
    });
  }

  bool _isChosen(String pkg) => _draft.any((e) => e.package == pkg);

  void _toggle(LockApp app) {
    if (_loading) return;
    final chosen = _isChosen(app.package);
    if (!chosen && _draft.length >= FocusGuard.maxWhitelist) {
      _toast('最多 ${FocusGuard.maxWhitelist} 个，先取消几个');
      return;
    }
    setState(() {
      if (chosen) {
        _draft = _draft.where((e) => e.package != app.package).toList();
      } else {
        _draft = [..._draft, WhitelistEntry(app.package, app.label)];
      }
      _dirty = true;
    });
  }

  /// 保存：消耗一次当日额度，然后写库并下发给原生
  Future<void> _save() async {
    if (_saving) return;
    if (!_dirty) {
      Navigator.of(context).pop();
      return;
    }
    if (_editsLeft <= 0) {
      _toast('今天已经保存了 ${FocusGuard.dailyEdits} 次，明天再来');
      return;
    }
    setState(() => _saving = true);
    final ok = await FocusGuard.consumeEdit();
    if (!ok) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _editsLeft = 0;
      });
      _toast('今天已经保存了 ${FocusGuard.dailyEdits} 次，明天再来');
      return;
    }
    await FocusGuard.saveWhitelist(_draft);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _dirty = false;
      _editsLeft = _editsLeft - 1 < 0 ? 0 : _editsLeft - 1;
    });
    _toast('已保存');
  }

  void _toast(String s) {
    if (!mounted) return;
    final m = ScaffoldMessenger.maybeOf(context);
    if (m == null) return;
    m.clearSnackBars();
    m.showSnackBar(
      // 不要自己设 backgroundColor：主题里 SnackBar 的文字是白色的，
      // 背景改成 kCard 会变成白底白字，看起来就是一个空白的白框。
      SnackBar(
        content: Text(s),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// 有未保存改动时确认一下再走
  Future<bool> _confirmLeave() async {
    if (!_dirty) return true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard,
        title: Text('还没保存', style: TextStyle(color: kFg)),
        content: Text('刚才的勾选不会生效，确定离开吗？',
            style: TextStyle(color: kDim, height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('继续编辑', style: TextStyle(color: kAcc)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('离开', style: TextStyle(color: kDim)),
          ),
        ],
      ),
    );
    return leave == true;
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
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final ok = await _confirmLeave();
        if (ok && mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: kBg,
        appBar: AppBar(
          backgroundColor: kBg,
          elevation: 0,
          foregroundColor: kFg,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('专注白名单',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: kFg)),
              Text(
                '${_draft.length}/${FocusGuard.maxWhitelist} · 今天还能保存 $_editsLeft 次',
                style: TextStyle(fontSize: 10.5, color: kDim),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: _saving ? null : _save,
              child: Text(
                _saving ? '保存中' : '保存',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: _dirty ? kAcc : kDim,
                ),
              ),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: Column(
          children: [
            if (_draft.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final e in _draft)
                        InputChip(
                          label: Text(e.label,
                              style: TextStyle(fontSize: 11, color: kFg)),
                          backgroundColor: kAcc.withValues(alpha: 0.12),
                          side: BorderSide(color: kAcc.withValues(alpha: 0.3)),
                          onDeleted: () => _toggle(LockApp(e.package, e.label, null)),
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
                                      // 图标解码失败时退回一个占位图标，
                                      // 不要让异常冒到界面上
                                      errorBuilder: (_, __, ___) => Icon(
                                        Icons.android,
                                        size: 30,
                                        color: kDim,
                                      ),
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
                                color:
                                    on ? kAcc : kDim.withValues(alpha: 0.5),
                              ),
                              onTap: () => _toggle(a),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}