import 'package:flutter/material.dart';

import '../data/db.dart';
import '../models.dart';
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

class TimetablePage extends StatefulWidget {
  const TimetablePage({super.key});

  @override
  State<TimetablePage> createState() => _TimetablePageState();
}

class _TimetablePageState extends State<TimetablePage> {
  static const List<String> _days = ['一', '二', '三', '四', '五', '六', '日'];
  static const int _periods = 12;

  int _viewWeek = 1;
  int _currentWeek = 1;
  int _total = 20;
  List<Lesson> _all = [];
  List<Override> _ovs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
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

  /// 重新只刷新数据，不重置当前浏览的周
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

  Override? _ovFor(int? lessonId, int week) {
    if (lessonId == null) return null;
    for (final o in _ovs) {
      if (o.lessonId == lessonId && o.weekNo == week) return o;
    }
    return null;
  }

  /// 该格在 week 周要显示什么
  _CellView? _resolve(int wd, int p) {
    final cands =
        _all.where((l) => l.weekday == wd && l.period == p).toList();
    if (cands.isEmpty) return null;
    final active = cands.where((l) => l.activeInWeek(_viewWeek)).toList();
    if (active.isEmpty) return null;
    final base = active.first;
    final ov = _ovFor(base.id, _viewWeek);
    if (ov == null) {
      return _CellView(base.subject, base.room, Color(base.color), base.badge,
          false, false, base);
    }
    if (ov.cancelled) {
      return _CellView('本周不上', '', kDim, '', true, true, base);
    }
    final s = ov.subject.isEmpty ? base.subject : ov.subject;
    return _CellView(s, ov.room.isEmpty ? base.room : ov.room, Color(base.color),
        base.badge, false, true, base);
  }

  /// 该格原始记录（用于编辑）
  Lesson? _any(int wd, int p) {
    final list = _all.where((l) => l.weekday == wd && l.period == p).toList();
    if (list.isEmpty) return null;
    final active = list.where((l) => l.activeInWeek(_viewWeek));
    return active.isNotEmpty ? active.first : list.first;
  }

  void _moveWeek(int delta) {
    final v = _viewWeek + delta;
    if (v < 1 || v > _total) return;
    setState(() => _viewWeek = v);
  }

  Future<void> _edit(int wd, int p) async {
    final base = _any(wd, p);
    final view = _resolve(wd, p);
    final ov = _ovFor(base?.id, _viewWeek);

    final subj = TextEditingController(
        text: view == null || view.cancelled ? (base?.subject ?? '') : view.subject);
    final room = TextEditingController(
        text: view == null || view.cancelled ? (base?.room ?? '') : view.room);
    final teacher = TextEditingController(text: base?.teacher ?? '');

    int pStart = base?.period ?? p;
    int pEnd = base?.period ?? p;
    int wStart = base?.startWeek ?? 1;
    int wEnd = base?.endWeek ?? _total;
    int wt = base?.weekType ?? 0;
    bool onlyThisWeek = false;
    bool cancelledThisWeek = ov?.cancelled ?? false;

    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text('周${_days[wd - 1]} · 第 $p 节 · 第 $_viewWeek 周'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: subj,
                    autofocus: base == null,
                    decoration: const InputDecoration(labelText: '科目'),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: room,
                          decoration: const InputDecoration(labelText: '地点'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: teacher,
                          decoration: const InputDecoration(labelText: '教师'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _label('连堂节次'),
                  Row(
                    children: [
                      Expanded(
                        child: _numDd(
                          label: '起',
                          value: pStart,
                          max: _periods,
                          suffix: '节',
                          onChanged: (v) => setDlg(() {
                            pStart = v;
                            if (pEnd < pStart) pEnd = pStart;
                          }),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _numDd(
                          label: '止',
                          value: pEnd,
                          max: _periods,
                          suffix: '节',
                          onChanged: (v) => setDlg(() {
                            pEnd = v;
                            if (pEnd < pStart) pStart = pEnd;
                          }),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _label('上课周次'),
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
                      const SizedBox(width: 10),
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
                  const SizedBox(height: 14),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 0, label: Text('全周')),
                      ButtonSegment(value: 1, label: Text('单周')),
                      ButtonSegment(value: 2, label: Text('双周')),
                    ],
                    selected: {wt},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) => setDlg(() => wt = s.first),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final s in kSubjects)
                        ActionChip(
                          label: Text(s, style: const TextStyle(fontSize: 12)),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => setDlg(() => subj.text = s),
                        ),
                    ],
                  ),
                  const Divider(height: 24),
                  if (base != null)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      value: onlyThisWeek,
                      onChanged: (v) => setDlg(() => onlyThisWeek = v),
                      title: Text('仅修改第 $_viewWeek 周',
                          style: const TextStyle(fontSize: 14)),
                      subtitle: const Text('不影响其它周次',
                          style: TextStyle(fontSize: 11, color: kDim)),
                    ),
                  if (onlyThisWeek)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      value: cancelledThisWeek,
                      onChanged: (v) => setDlg(() => cancelledThisWeek = v),
                      title: const Text('本周不上', style: TextStyle(fontSize: 14)),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            if (base != null)
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'delete'),
                child: const Text('删除',
                    style: TextStyle(color: Color(0xFFFF5D6C))),
              ),
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, 'save'),
                child: const Text('保存')),
          ],
        ),
      ),
    );

    if (res == 'delete' && base != null) {
      if (base.id != null) {
        await DB.i.deleteLesson(base.id!);
      } else {
        await DB.i.deleteLessonCell(wd, p, base.weekType);
      }
      await _reload();
      return;
    }
    if (res != 'save') return;

    final s = subj.text.trim();
    if (onlyThisWeek && base != null && base.id != null) {
      if (cancelledThisWeek) {
        await DB.i.saveOverride(Override(
            lessonId: base.id!, weekNo: _viewWeek, cancelled: true));
      } else if (s.isEmpty) {
        await DB.i.deleteOverride(base.id!, _viewWeek);
      } else {
        await DB.i.saveOverride(Override(
          lessonId: base.id!,
          weekNo: _viewWeek,
          subject: s == base.subject ? '' : s,
          room: room.text.trim() == base.room ? '' : room.text.trim(),
          teacher: teacher.text.trim() == base.teacher ? '' : teacher.text.trim(),
        ));
      }
      await _reload();
      return;
    }

    if (s.isEmpty) {
      await DB.i.deleteLessonCell(wd, p, wt);
      await _reload();
      return;
    }

    // 跨度变短时，清掉原来多出来的格子
    if (base != null && base.period > pEnd) {
      await DB.i.deleteLessonCell(wd, base.period, base.weekType);
    }
    for (var i = pEnd + 1; i <= _periods; i++) {
      final leftover = _all.where((l) =>
          l.weekday == wd &&
          l.period == i &&
          l.weekType == wt &&
          l.subject == base?.subject);
      if (leftover.isNotEmpty && base != null && pEnd < base.period) {
        await DB.i.deleteLessonCell(wd, i, wt);
      }
    }

    await DB.i.saveSpan(
      Lesson(
        weekday: wd,
        period: pStart,
        subject: s,
        room: room.text.trim(),
        teacher: teacher.text.trim(),
        weekType: wt,
        startWeek: wStart,
        endWeek: wEnd,
        color: colorForSubject(s).toARGB32(),
      ),
      pStart,
      pEnd,
    );
    if (base?.id != null) {
      await DB.i.deleteOverride(base!.id!, _viewWeek);
    }
    await _reload();
  }

  Widget _label(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(s, style: const TextStyle(fontSize: 12, color: kDim)),
      );

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
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                        style: const TextStyle(fontSize: 13))),
            ],
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildTopBar(),
        _buildDayHeader(),
        const SizedBox(height: 4),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: Column(
                    children: [
                      for (var p = 1; p <= _periods; p++)
                        Expanded(child: _row(p)),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildTopBar() {
    final isCurrent = _viewWeek == _currentWeek;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 4),
      child: Row(
        children: [
          const Text('课表',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(width: 12),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () => _moveWeek(-1),
            icon: const Icon(Icons.chevron_left),
          ),
          GestureDetector(
            onTap: () async {
              await _jumpWeek();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: kAcc.withValues(alpha: isCurrent ? 0.18 : 0.10),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: kAcc.withValues(alpha: isCurrent ? 0.5 : 0.2)),
              ),
              child: Text(
                '第 $_viewWeek 周 · ${_viewWeek.isOdd ? "单" : "双"}',
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: kAcc),
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () => _moveWeek(1),
            icon: const Icon(Icons.chevron_right),
          ),
          if (!isCurrent)
            TextButton(
              onPressed: () => setState(() => _viewWeek = _currentWeek),
              child: const Text('本周', style: TextStyle(fontSize: 12)),
            ),
          const Spacer(),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: '使用提示',
            onPressed: _showHelp,
            icon: const Icon(Icons.help_outline, size: 20),
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
        title: const Text('跳到第几周'),
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
            child: const Text('回本周'),
          ),
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              final n = int.tryParse(ctrl.text.trim());
              Navigator.pop(ctx, n);
            },
            child: const Text('确定'),
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
        title: const Text('课表怎么用'),
        content: const Text(
          '· 点格子编辑科目、地点、教师\n'
          '· 设置「起始周 / 结束周」可做半学期结课\n'
          '· 选「单周 / 双周」自动交替，格子上有角标\n'
          '· 点开已有课程可勾「仅修改第 X 周」，做临时调课或本周不上\n'
          '· 顶部箭头翻周，点中间胶囊直接跳周\n'
          '· 周次按「开学日期」自动计算，可在「我的」里设置',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('知道了')),
        ],
      ),
    );
  }

  Widget _buildDayHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          const SizedBox(width: 34),
          for (var i = 1; i <= 7; i++)
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                padding: const EdgeInsets.symmetric(vertical: 5),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: i == _todayWd
                      ? kAcc.withValues(alpha: 0.14)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  i == _todayWd ? '${_days[i - 1]}·今' : _days[i - 1],
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: i == _todayWd ? kAcc : kDim,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _row(int p) {
    return Row(
      children: [
        SizedBox(
          width: 34,
          child: Center(
            child: Text('$p', style: const TextStyle(fontSize: 11, color: kDim)),
          ),
        ),
        for (var wd = 1; wd <= 7; wd++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: _cell(wd, p),
            ),
          ),
      ],
    );
  }

  Widget _cell(int wd, int p) {
    final v = _resolve(wd, p);
    final today = wd == _todayWd;
    final c = v?.color ?? kAcc;
    final bg = v == null
        ? (today ? kCard2 : kCard)
        : (v.cancelled
            ? kCard2
            : c.withValues(alpha: 0.16));
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(7),
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: () => _edit(wd, p),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: v == null
                  ? kLine
                  : (v.cancelled ? kLine : c.withValues(alpha: 0.5)),
              width: v != null && v.modified ? 1.4 : 1,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: v == null
              ? const SizedBox.shrink()
              : Row(
                  children: [
                    Expanded(
                      child: Text(
                        v.subject,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.1,
                          fontWeight: FontWeight.w600,
                          color: v.cancelled ? kDim : c,
                          decoration:
                              v.cancelled ? TextDecoration.lineThrough : null,
                        ),
                      ),
                    ),
                    if (v.badge.isNotEmpty)
                      Text(v.badge,
                          style: TextStyle(
                              fontSize: 8,
                              height: 1,
                              color: c.withValues(alpha: 0.85))),
                    if (v.modified && !v.cancelled)
                      Text('·',
                          style: TextStyle(fontSize: 12, color: c)),
                  ],
                ),
        ),
      ),
    );
  }
}
