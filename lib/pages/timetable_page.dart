import 'package:flutter/material.dart';

import '../data/db.dart';
import '../models.dart';
import '../theme.dart';

class TimetablePage extends StatefulWidget {
  const TimetablePage({super.key});

  @override
  State<TimetablePage> createState() => _TimetablePageState();
}

class _TimetablePageState extends State<TimetablePage> {
  static const List<String> _days = ['一', '二', '三', '四', '五', '六', '日'];
  static const int _periods = 12;

  int _week = 1;
  List<Lesson> _all = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final w = await DB.i.weekNo();
    final all = await DB.i.lessons();
    if (!mounted) return;
    setState(() {
      _week = w;
      _all = all;
      _loading = false;
    });
  }

  Future<void> _moveWeek(int delta) async {
    final v = _week + delta;
    if (v < 1) return;
    await DB.i.setWeekNo(v);
    _load();
  }

  /// 该格本周应显示的课
  Lesson? _pick(int wd, int p) {
    final list = _all.where((l) => l.weekday == wd && l.period == p).toList();
    if (list.isEmpty) return null;
    final specific = list.where((l) => l.weekType != 0 && l.matchesWeek(_week));
    if (specific.isNotEmpty) return specific.first;
    final every = list.where((l) => l.weekType == 0).toList();
    return every.isEmpty ? null : every.first;
  }

  /// 该格任意记录（用于编辑本周不上、但下周要上的课）
  Lesson? _any(int wd, int p) {
    final list = _all.where((l) => l.weekday == wd && l.period == p).toList();
    return list.isEmpty ? null : list.first;
  }

  int get _todayWd => DateTime.now().weekday;

  Future<void> _edit(int wd, int p) async {
    final cur = _pick(wd, p) ?? _any(wd, p);
    final subj = TextEditingController(text: cur?.subject ?? '');
    final room = TextEditingController(text: cur?.room ?? '');
    final teacher = TextEditingController(text: cur?.teacher ?? '');
    int wt = cur?.weekType ?? 0;

    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text('周${_days[wd - 1]} · 第 $p 节'),
          content: SizedBox(
            width: 430,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: subj,
                    autofocus: cur == null,
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
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 0, label: Text('每周')),
                      ButtonSegment(value: 1, label: Text('单周')),
                      ButtonSegment(value: 2, label: Text('双周')),
                    ],
                    selected: {wt},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) => setDlg(() => wt = s.first),
                  ),
                  const SizedBox(height: 14),
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
                ],
              ),
            ),
          ),
          actions: [
            if (cur != null)
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'delete'),
                child: const Text('删除', style: TextStyle(color: Color(0xFFFF5D6C))),
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

    if (res == 'delete' && cur != null) {
      if (cur.id != null) await DB.i.deleteLesson(cur.id!);
      await _load();
    } else if (res == 'save') {
      final s = subj.text.trim();
      if (s.isEmpty) {
        await DB.i.deleteLessonCell(wd, p, wt);
      } else {
        await DB.i.saveLesson(Lesson(
          weekday: wd,
          period: p,
          subject: s,
          room: room.text.trim(),
          teacher: teacher.text.trim(),
          weekType: wt,
          color: colorForSubject(s).toARGB32(),
        ));
      }
      await _load();
    }
  }

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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Row(
        children: [
          const Text('课表',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(width: 14),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () => _moveWeek(-1),
            icon: const Icon(Icons.chevron_left),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: kAcc.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '第 $_week 周 · ${_week.isOdd ? "单周" : "双周"}',
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: kAcc),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () => _moveWeek(1),
            icon: const Icon(Icons.chevron_right),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: () {
              final now = DateTime.now();
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('使用提示'),
                  content: Text(
                    '· 点格子即可编辑科目、地点、教师\n'
                    '· 每格可选「每周 / 单周 / 双周」\n'
                    '· 顶部箭头切换周次，单双周会自动过滤\n'
                    '· 今天：周${_days[now.weekday - 1]}',
                  ),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('知道了')),
                  ],
                ),
              );
            },
            icon: const Icon(Icons.help_outline, size: 18),
            label: const Text('帮助', style: TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _buildDayHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          const SizedBox(width: 40),
          for (var i = 1; i <= 7; i++)
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                padding: const EdgeInsets.symmetric(vertical: 6),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: i == _todayWd
                      ? kAcc.withValues(alpha: 0.14)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  i == _todayWd ? '周${_days[i - 1]}·今' : '周${_days[i - 1]}',
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
          width: 40,
          child: Center(
            child: Text('$p',
                style: const TextStyle(fontSize: 11, color: kDim)),
          ),
        ),
        for (var wd = 1; wd <= 7; wd++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: _cell(wd, p),
            ),
          ),
      ],
    );
  }

  Widget _cell(int wd, int p) {
    final l = _pick(wd, p);
    final today = wd == _todayWd;
    final c = l == null ? null : Color(l.color);
    return Material(
      color: l == null
          ? (today ? kCard2 : kCard)
          : (c ?? kAcc).withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _edit(wd, p),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: l == null ? kLine : (c ?? kAcc).withValues(alpha: 0.55),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: l == null
              ? const SizedBox.shrink()
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      l.subject,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: c,
                      ),
                    ),
                    if (l.room.isNotEmpty || l.weekType != 0)
                      Text(
                        [
                          if (l.room.isNotEmpty) l.room,
                          if (l.weekType != 0) l.weekLabel,
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 9, color: kDim),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}
