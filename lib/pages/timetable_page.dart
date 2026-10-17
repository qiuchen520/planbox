import 'package:flutter/material.dart';

import '../data/db.dart';
import '../models.dart';
import '../palette.dart';
import '../responsive.dart';
import '../theme.dart';

/// 单元格最终展示内容（已叠加临时调课）
class _CellView {
  final String subject;
  final String room;
  final Color color;
  final String badge;
  final bool cancelled;
  final bool modified;
  final Lesson base;
  _CellView(this.subject, this.room, this.color, this.badge, this.cancelled,
      this.modified, this.base);
}

/// 竖向合并后的色块（连续同一门课）
class _Block {
  final int start;
  final int span;
  final _CellView v;
  _Block(this.start, this.span, this.v);
}

class TimetablePage extends StatefulWidget {
  TimetablePage({super.key});

  @override
  State<TimetablePage> createState() => _TimetablePageState();
}

class _TimetablePageState extends State<TimetablePage> {
  static List<String> _days = ['一', '二', '三', '四', '五', '六', '日'];
  static const int _periods = 12;

  int _viewWeek = 1;
  int _currentWeek = 1;
  int _total = 20;
  List<Lesson> _all = [];
  List<Override> _ovs = [];
  bool _loading = true;

  // ── 多选批量 ──
  bool _selectMode = false;
  final Set<int> _sel = {};

  static int _key(int wd, int p) => wd * 100 + p;

  @override
  void initState() {
    super.initState();
    Pal.rev.addListener(_onPalette);
    _load();
  }

  void _onPalette() {
    if (!mounted) return;
    _reload();
  }

  @override
  void dispose() {
    Pal.rev.removeListener(_onPalette);
    super.dispose();
  }

  Future<void> _load() async {
    final cur = await DB.i.currentWeek();
    final total = await DB.i.totalWeeks();
    final all = await DB.i.lessons();
    final ovs = await DB.i.overrides();
    if (!mounted) return;
    setState(() {
      _currentWeek = cur;
      _total = total;
      _all = all;
      _ovs = ovs;
      _viewWeek = cur;
      _loading = false;
    });
  }

  Future<void> _reload() async {
    final cur = await DB.i.currentWeek();
    final total = await DB.i.totalWeeks();
    final all = await DB.i.lessons();
    final ovs = await DB.i.overrides();
    if (!mounted) return;
    setState(() {
      _currentWeek = cur;
      _total = total;
      _all = all;
      _ovs = ovs;
    });
  }

  int get _todayWd => DateTime.now().weekday;

  /// 合并用的内容签名：科目/地点/教师/单双周/周区间/颜色都一样才算同一块
  String _sigOf(Lesson l) =>
      '${l.subject}|${l.room}|${l.teacher}|${l.weekType}|${l.startWeek}|${l.endWeek}|${l.color}';

  Override? _ovFor(int? lessonId, int week) {
    if (lessonId == null) return null;
    for (final o in _ovs) {
      if (o.lessonId == lessonId && o.weekNo == week) return o;
    }
    return null;
  }

  _CellView? _resolve(int wd, int p) {
    final cands = _all.where((l) => l.weekday == wd && l.period == p).toList();
    if (cands.isEmpty) return null;
    final active = cands.where((l) => l.activeInWeek(_viewWeek)).toList()
      // 单/双周优先于全周，避免同一格两条记录时选错
      ..sort((a, b) =>
          (a.weekType == 0 ? 1 : 0).compareTo(b.weekType == 0 ? 1 : 0));
    if (active.isEmpty) return null;
    final base = active.first;
    final ov = _ovFor(base.id, _viewWeek);
    if (ov == null) {
      return _CellView(base.subject, base.room, Color(base.color), base.badge,
          false, false, base);
    }
    if (ov.cancelled) {
      return _CellView(base.subject, '', kDim, '', true, true, base);
    }
    final s = ov.subject.isEmpty ? base.subject : ov.subject;
    return _CellView(s, ov.room.isEmpty ? base.room : ov.room, Color(base.color),
        base.badge, false, true, base);
  }

  /// 某一列竖排合并后的色块
  List<_Block> _blocksFor(int wd) {
    final out = <_Block>[];
    String? curSig;
    _Block? cur;
    for (var p = 1; p <= _periods; p++) {
      final v = _resolve(wd, p);
      if (v == null) {
        cur = null;
        curSig = null;
        continue;
      }
      final sig = '${_sigOf(v.base)}|${v.cancelled}|${v.modified}';
      if (cur != null && curSig == sig && cur.start + cur.span == p) {
        cur = _Block(cur.start, cur.span + 1, cur.v);
        out[out.length - 1] = cur;
      } else {
        cur = _Block(p, 1, v);
        curSig = sig;
        out.add(cur);
      }
    }
    return out;
  }

  /// 与 base 连成一片的原始记录（用于整体替换/删除）
  List<Lesson> _membersOf(Lesson? base) {
    if (base == null) return [];
    final sig = _sigOf(base);
    final rows = _all
        .where((l) => l.weekday == base.weekday && _sigOf(l) == sig)
        .toList();
    var s = base.period;
    var e = base.period;
    bool has(int x) => rows.any((l) => l.period == x);
    while (s > 1 && has(s - 1)) {
      s--;
    }
    while (e < _periods && has(e + 1)) {
      e++;
    }
    return rows.where((l) => l.period >= s && l.period <= e).toList();
  }

  void _moveWeek(int delta) {
    final v = _viewWeek + delta;
    if (v < 1 || v > _total) return;
    setState(() => _viewWeek = v);
  }

  // ── 多选 ────────────────────────────────────────────
  void _toggleSel(int wd, int p) {
    final k = _key(wd, p);
    setState(() {
      if (!_sel.remove(k)) _sel.add(k);
    });
  }

  void _enterSel(int wd, int p) {
    setState(() {
      _selectMode = true;
      if (!_sel.contains(_key(wd, p))) _sel.add(_key(wd, p));
    });
  }

  void _exitSel() {
    setState(() {
      _selectMode = false;
      _sel.clear();
    });
  }

  void _toast(String msg) {
    if (!mounted) return;
    final m = ScaffoldMessenger.maybeOf(context);
    m?.clearSnackBars();
    m?.showSnackBar(SnackBar(
      content: Text(msg),
      duration: Duration(milliseconds: 1600),
    ));
  }

  /// 批量给选中的格子铺课
  Future<void> _batchAdd() async {
    if (_sel.isEmpty) {
      _toast('先点几个格子');
      return;
    }
    final n = _sel.length;
    final subj = TextEditingController();
    final room = TextEditingController();
    int wStart = 1;
    int wEnd = _total;
    int wt = 0;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text('批量加课 · 已选 $n 格'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: subj,
                    autofocus: true,
                    decoration: InputDecoration(
                        labelText: '科目', hintText: '语文 / 数学 / 英语'),
                  ),
                  SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final s in kSubjects)
                        ActionChip(
                          label: Text(s, style: TextStyle(fontSize: 12)),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => setDlg(() => subj.text = s),
                        ),
                    ],
                  ),
                  SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _numDd(
                          label: '起始周',
                          value: wStart,
                          max: _total,
                          suffix: '周',
                          onChanged: (v) => setDlg(() {
                            wStart = v;
                            if (wEnd < wStart) wEnd = wStart;
                          }),
                        ),
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: _numDd(
                          label: '结束周',
                          value: wEnd,
                          max: _total,
                          suffix: '周',
                          onChanged: (v) => setDlg(() {
                            wEnd = v;
                            if (wEnd < wStart) wStart = wEnd;
                          }),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 12),
                  SegmentedButton<int>(
                    segments: [
                      ButtonSegment(value: 0, label: Text('全周')),
                      ButtonSegment(value: 1, label: Text('单周')),
                      ButtonSegment(value: 2, label: Text('双周')),
                    ],
                    selected: {wt},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) => setDlg(() => wt = s.first),
                  ),
                  SizedBox(height: 12),
                  TextField(
                    controller: room,
                    decoration: InputDecoration(labelText: '地点（可空）'),
                  ),
                  SizedBox(height: 8),
                  Text('选中的格子若已有课会被覆盖',
                      style: TextStyle(fontSize: 11, color: kDim)),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('铺上去')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final s = subj.text.trim();
    if (s.isEmpty) {
      _toast('科目不能为空');
      return;
    }
    final color = colorForSubject(s).toARGB32();
    final keys = List<int>.from(_sel);
    for (final k in keys) {
      final wd = k ~/ 100;
      final p = k % 100;
      for (final old in _all.where((l) => l.weekday == wd && l.period == p)) {
        if (old.id != null) await DB.i.deleteLesson(old.id!);
      }
      await DB.i.saveSpan(
        Lesson(
          weekday: wd,
          period: p,
          subject: s,
          room: room.text.trim(),
          teacher: '',
          weekType: wt,
          startWeek: wStart,
          endWeek: wEnd,
          color: color,
        ),
        p,
        p,
      );
    }
    _exitSel();
    await _reload();
    _toast('已铺 $s 到 $n 格');
  }

  // ── 编辑 ────────────────────────────────────────────

  Future<void> _openEditor(int wd, int p, Lesson? base) async {
    final isNew = base == null;
    final view = _resolve(wd, p);
    final ov = isNew ? null : _ovFor(base.id, _viewWeek);

    final subj = TextEditingController(text: view?.subject ?? '');
    final room = TextEditingController(text: view?.room ?? '');
    final teacher = TextEditingController(text: base?.teacher ?? '');

    int wStart = base?.startWeek ?? 1;
    int wEnd = base?.endWeek ?? _total;
    int wt = base?.weekType ?? 0;
    int span = 1;
    if (!isNew) {
      final blk = _blocksFor(wd).where((b) => b.start == p).toList();
      span = blk.isEmpty ? 1 : blk.first.span;
    }
    final maxSpan = _periods - p + 1;
    if (span > maxSpan) span = maxSpan;
    // 段数选择上限：默认 4，但必须容得下当前块的长度，否则选中项会不存在
    var segMax = 4;
    if (segMax > maxSpan) segMax = maxSpan;
    if (segMax < span) segMax = span;
    bool onlyThisWeek = false;
    bool cancelledThisWeek = ov?.cancelled ?? false;

    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text(isNew
              ? '周${_days[wd - 1]} · 第 $p 节'
              : '周${_days[wd - 1]} · 第 $p 节 · ${view?.subject ?? ''}'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: subj,
                    autofocus: isNew,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                        labelText: '科目', hintText: '语文 / 数学 / 英语'),
                  ),
                  SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final s in kSubjects)
                        ActionChip(
                          label: Text(s, style: TextStyle(fontSize: 12)),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => setDlg(() => subj.text = s),
                        ),
                    ],
                  ),
                  SizedBox(height: 14),
                  Text('上几节（连堂直接选 2 节以上）',
                      style: TextStyle(fontSize: 12, color: kDim)),
                  SizedBox(height: 8),
                  SegmentedButton<int>(
                    segments: [
                      for (var i = 1; i <= segMax; i++)
                        ButtonSegment(
                            value: i, label: Text(i == 1 ? '1 节' : '$i 节')),
                    ],
                    selected: {span},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) => setDlg(() => span = s.first),
                  ),
                  SizedBox(height: 6),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: EdgeInsets.zero,
                    title: Text('更多设置',
                        style: TextStyle(fontSize: 13, color: kDim)),
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: room,
                              decoration:
                                  InputDecoration(labelText: '地点'),
                            ),
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: teacher,
                              decoration:
                                  InputDecoration(labelText: '教师'),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _numDd(
                              label: '起始周',
                              value: wStart,
                              max: _total,
                              suffix: '周',
                              onChanged: (v) => setDlg(() {
                                wStart = v;
                                if (wEnd < wStart) wEnd = wStart;
                              }),
                            ),
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: _numDd(
                              label: '结束周',
                              value: wEnd,
                              max: _total,
                              suffix: '周',
                              onChanged: (v) => setDlg(() {
                                wEnd = v;
                                if (wEnd < wStart) wStart = wEnd;
                              }),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 12),
                      SegmentedButton<int>(
                        segments: [
                          ButtonSegment(value: 0, label: Text('全周')),
                          ButtonSegment(value: 1, label: Text('单周')),
                          ButtonSegment(value: 2, label: Text('双周')),
                        ],
                        selected: {wt},
                        showSelectedIcon: false,
                        onSelectionChanged: (s) => setDlg(() => wt = s.first),
                      ),
                      if (!isNew) ...[
                        Divider(height: 20),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          value: onlyThisWeek,
                          onChanged: (v) => setDlg(() => onlyThisWeek = v),
                          title: Text('仅修改第 $_viewWeek 周',
                              style: TextStyle(fontSize: 14)),
                          subtitle: Text('临时调课，不影响其它周',
                              style: TextStyle(fontSize: 11, color: kDim)),
                        ),
                        if (onlyThisWeek)
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            value: cancelledThisWeek,
                            onChanged: (v) =>
                                setDlg(() => cancelledThisWeek = v),
                            title: Text('本周不上',
                                style: TextStyle(fontSize: 14)),
                          ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            if (!isNew)
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'delete'),
                child: Text('删除',
                    style: TextStyle(color: kDanger)),
              ),
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, 'save'),
                child: Text(isNew ? '添加' : '保存')),
          ],
        ),
      ),
    );

    if (res == 'delete' && base != null) {
      for (final m in _membersOf(base)) {
        if (m.id != null) await DB.i.deleteLesson(m.id!);
      }
      await _reload();
      return;
    }
    if (res != 'save') return;

    final s = subj.text.trim();

    // 仅改本周 → 写入临时调课
    if (!isNew && onlyThisWeek && base.id != null) {
      if (cancelledThisWeek) {
        await DB.i.saveOverride(
            Override(lessonId: base.id!, weekNo: _viewWeek, cancelled: true));
      } else if (s.isEmpty || s == base.subject) {
        await DB.i.deleteOverride(base.id!, _viewWeek);
      } else {
        await DB.i.saveOverride(Override(
          lessonId: base.id!,
          weekNo: _viewWeek,
          subject: s,
          room: room.text.trim(),
          teacher: teacher.text.trim(),
        ));
      }
      await _reload();
      return;
    }

    // 正常保存：先清掉原来那一片，再按新设置铺回去
    for (final m in _membersOf(base)) {
      if (m.id != null) await DB.i.deleteLesson(m.id!);
    }
    if (s.isEmpty) {
      await _reload();
      return;
    }
    await DB.i.saveSpan(
      Lesson(
        weekday: wd,
        period: p,
        subject: s,
        room: room.text.trim(),
        teacher: teacher.text.trim(),
        weekType: wt,
        startWeek: wStart,
        endWeek: wEnd,
        color: colorForSubject(s).toARGB32(),
      ),
      p,
      p + span - 1,
    );
    await _reload();
  }

  Widget _numDd({
    required String label,
    required int value,
    required int max,
    required String suffix,
    required void Function(int) onChanged,
  }) =>
      InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          contentPadding:
              EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<int>(
            value: value,
            isExpanded: true,
            isDense: true,
            items: [
              for (var i = 1; i <= max; i++)
                DropdownMenuItem(
                    value: i,
                    child: Text('$i $suffix',
                        style: TextStyle(fontSize: 13))),
            ],
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ),
      );

  // ── 界面 ────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildTopBar(),
        _buildDayHeader(),
        SizedBox(height: 2),
        Expanded(
          child: ContentWidth(
            maxWidth: BP.grid,
            child: _loading
                ? Center(child: CircularProgressIndicator())
                : LayoutBuilder(builder: (ctx, cons) {
                    // 行高只用来定字号，布局完全由 flex 决定，不会错位
                    final h = cons.maxHeight / _periods;
                    return Padding(
                      padding: EdgeInsets.fromLTRB(6, 0, 8, 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: 22,
                            child: Column(
                              children: [
                                for (var p = 1; p <= _periods; p++)
                                  Expanded(
                                    child: Center(
                                      child: Text('$p',
                                          style: TextStyle(
                                              fontSize: 10, color: kDim)),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          for (var wd = 1; wd <= 7; wd++)
                            Expanded(
                              child: Padding(
                                padding:
                                    EdgeInsets.symmetric(horizontal: 1.5),
                                child: _dayColumn(wd, h),
                              ),
                            ),
                        ],
                      ),
                    );
                  }),
          ),
        ),
        if (_selectMode) _buildSelBar(),
      ],
    );
  }

  /// 一列：色块和空格子都进同一个 Column 的 Expanded，
  /// 色块跨几节就 flex 几份，所以永远不会和行错位。
  Widget _dayColumn(int wd, double h) {
    final blocks = _blocksFor(wd);
    final byStart = {for (final b in blocks) b.start: b};
    final slots = <Widget>[];
    var p = 1;
    while (p <= _periods) {
      final b = byStart[p];
      if (b != null) {
        slots.add(_blockSlot(wd, b, h));
        p += b.span;
      } else {
        slots.add(_emptySlot(wd, p, h));
        p += 1;
      }
    }
    return Column(children: slots);
  }

  Widget _emptySlot(int wd, int p, double h) {
    final k = _key(wd, p);
    final selected = _sel.contains(k);
    final isToday = wd == _todayWd;
    return Expanded(
      flex: 1,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 1),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () =>
                _selectMode ? _toggleSel(wd, p) : _openEditor(wd, p, null),
            onLongPress: () => _enterSel(wd, p),
            child: Container(
              decoration: BoxDecoration(
                color: selected
                    ? kAcc.withValues(alpha: 0.18)
                    : isToday
                        ? kAcc.withValues(alpha: 0.06)
                        : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: selected
                      ? kAcc
                      : isToday
                          ? kAcc.withValues(alpha: 0.30)
                          : kLine,
                  width: selected ? 1.6 : 1,
                ),
              ),
              child: selected
                  ? Center(
                      child: Icon(Icons.check,
                          size: (h * 0.30).clamp(10.0, 16.0), color: kAcc),
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }

  Widget _blockSlot(int wd, _Block b, double h) {
    var selCount = 0;
    for (var i = 0; i < b.span; i++) {
      if (_sel.contains(_key(wd, b.start + i))) selCount++;
    }
    final full = selCount == b.span;
    return Expanded(
      flex: b.span,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 1),
        child: _blockWidget(wd, b, h, selCount > 0, full),
      ),
    );
  }

  Widget _blockWidget(int wd, _Block b, double h, bool selected, bool full) {
    final v = b.v;
    final c = v.color;
    final big = b.span >= 2;
    // 字号跟着行高走：平板行高大，字也应该变大，否则色块里空一大片
    final fs = (h * 0.24).clamp(10.5, 17.0);
    final subFs = (fs * 0.72).clamp(8.0, 12.0);
    return Material(
      color: v.cancelled ? kCard2 : c.withValues(alpha: 0.20),
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () {
          if (_selectMode) {
            setState(() {
              for (var i = 0; i < b.span; i++) {
                final k = _key(wd, b.start + i);
                if (full) {
                  _sel.remove(k);
                } else {
                  _sel.add(k);
                }
              }
            });
          } else {
            _openEditor(wd, b.start, v.base);
          }
        },
        onLongPress: () {
          if (!_selectMode) _enterSel(wd, b.start);
        },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: selected
                  ? kAcc
                  : v.cancelled
                      ? kLine
                      : c.withValues(alpha: 0.55),
              width: selected ? 1.8 : (v.modified ? 1.6 : 1),
            ),
          ),
          padding: EdgeInsets.symmetric(horizontal: 3, vertical: 3),
          child: Stack(
            children: [
              Align(
                alignment: Alignment.topCenter,
                child: Text(
                  v.subject,
                  textAlign: TextAlign.center,
                  maxLines: big ? 3 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: big ? fs * 1.05 : fs,
                    height: 1.15,
                    fontWeight: FontWeight.w700,
                    color: v.cancelled ? kDim : c,
                    decoration:
                        v.cancelled ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
              if (v.badge.isNotEmpty)
                Align(
                  alignment: Alignment.topRight,
                  child: Text(v.badge,
                      style: TextStyle(
                          fontSize: subFs * 0.85,
                          height: 1,
                          color: c.withValues(alpha: 0.9))),
                ),
              if (v.room.isNotEmpty && big)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Text(
                    v.room,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: subFs, color: c.withValues(alpha: 0.8)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSelBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(14, 6, 10, 10),
      decoration: BoxDecoration(
        color: kCard2,
        border: Border(top: BorderSide(color: kLine)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Icon(Icons.checklist_rounded, size: 18, color: kAcc),
            SizedBox(width: 8),
            Text('已选 ${_sel.length} 格',
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600)),
            SizedBox(width: 10),
            Text('点格子加/减',
                style: TextStyle(fontSize: 11, color: kDim)),
            Spacer(),
            TextButton(
              onPressed:
                  _sel.isEmpty ? null : () => setState(() => _sel.clear()),
              child: Text('清空', style: TextStyle(fontSize: 12)),
            ),
            SizedBox(width: 6),
            TextButton(
              onPressed: _exitSel,
              child: Text('退出', style: TextStyle(fontSize: 12)),
            ),
            SizedBox(width: 6),
            FilledButton.icon(
              onPressed: _batchAdd,
              icon: Icon(Icons.playlist_add_check, size: 17),
              label: Text('批量加课',
                  style:
                      TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    final isCurrent = _viewWeek == _currentWeek;
    return Padding(
      padding: EdgeInsets.fromLTRB(14, 6, 8, 2),
      child: Row(
        children: [
          Text('课表',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700)),
          SizedBox(width: 10),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: '上一周',
            onPressed: () => _moveWeek(-1),
            icon: Icon(Icons.chevron_left, size: 20),
          ),
          GestureDetector(
            onTap: _jumpWeek,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 11, vertical: 4),
              decoration: BoxDecoration(
                color: kAcc.withValues(alpha: isCurrent ? 0.18 : 0.10),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: kAcc.withValues(alpha: isCurrent ? 0.5 : 0.2)),
              ),
              child: Text(
                '第 $_viewWeek 周 · ${_viewWeek.isOdd ? "单" : "双"}',
                style: TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w600, color: kAcc),
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: '下一周',
            onPressed: () => _moveWeek(1),
            icon: Icon(Icons.chevron_right, size: 20),
          ),
          if (!isCurrent)
            TextButton(
              onPressed: () => setState(() => _viewWeek = _currentWeek),
              child: Text('本周', style: TextStyle(fontSize: 12)),
            ),
          Spacer(),
          TextButton.icon(
            onPressed: () {
              if (_selectMode) {
                _exitSel();
              } else {
                setState(() => _selectMode = true);
              }
            },
            icon: Icon(_selectMode ? Icons.close : Icons.checklist_rounded,
                size: 17),
            label: Text(_selectMode ? '退出多选' : '批量',
                style: TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(
              foregroundColor: _selectMode ? kDanger : kAcc,
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: '使用提示',
            onPressed: _showHelp,
            icon: Icon(Icons.help_outline, size: 19),
          ),
        ],
      ),
    );
  }

  Future<void> _jumpWeek() async {
    final ctrl = TextEditingController(text: '$_viewWeek');
    final v = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('跳到第几周'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(
              labelText: '1 - $_total', helperText: '本周是第 $_currentWeek 周'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, _currentWeek),
            child: Text('回本周'),
          ),
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, int.tryParse(ctrl.text.trim())),
            child: Text('确定'),
          ),
        ],
      ),
    );
    if (v != null && v >= 1 && v <= _total) {
      setState(() => _viewWeek = v);
    }
  }

  void _showHelp() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('课表怎么用'),
        content: Text(
          '· 点空格子直接加课，选「上几节」就能一次铺满连堂\n'
          '· 相邻的同一门课会自动黏成一块，点一下改整块\n'
          '· 长按任意格子进入多选，再点别的格子加/减，\n'
          '  底部「批量加课」一次把科目铺到所有选中格\n'
          '· 顶部「批量」按钮也能手动进多选\n'
          '· 「更多设置」里可以改地点、教师、周区间、单双周\n'
          '· 勾「仅修改第 X 周」做临时调课或本周不上\n'
          '· 顶部箭头翻周，点中间胶囊直接跳周\n'
          '· 周次按「开学日期」自动算，在「我的」里设置',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text('知道了')),
        ],
      ),
    );
  }

  Widget _buildDayHeader() {
    return Padding(
      padding: EdgeInsets.fromLTRB(6, 2, 8, 2),
      child: Row(
        children: [
          SizedBox(width: 22),
          for (var i = 1; i <= 7; i++)
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 1.5),
                child: Container(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i == _todayWd
                        ? kAcc.withValues(alpha: 0.14)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    i == _todayWd ? '${_days[i - 1]}今' : _days[i - 1],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: i == _todayWd ? kAcc : kDim,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
