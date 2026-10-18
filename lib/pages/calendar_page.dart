import 'package:flutter/material.dart';

import '../data/db.dart';
import '../models.dart';
import '../palette.dart';
import '../responsive.dart';
import '../theme.dart';

import '../services/occurrence_actions.dart';

/// 计划日历：按月看「哪一天有要做的事」，点某一天看当天清单。
/// 做的事和 Tasks 页共用一张表，两边改完都会重新读库。
class CalendarPage extends StatefulWidget {
  CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  List<Task> _tasks = [];
  bool _loading = true;

  late DateTime _month; // 当前显示的月份（当月 1 号）
  late DateTime _selected; // 选中的那一天

  static const List<String> _weekCn = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _month = DateTime(n.year, n.month);
    _selected = DateTime(n.year, n.month, n.day);
    Pal.rev.addListener(_onPalette);
    _load();
  }

  void _onPalette() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    Pal.rev.removeListener(_onPalette);
    super.dispose();
  }

  Future<void> _load() async {
    final t = await DB.i.tasks();
    if (!mounted) return;
    setState(() {
      _tasks = t;
      _loading = false;
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

  // ── 日期工具 ───────────────────────────────────────
  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static int _daysInMonth(int y, int m) => DateTime(y, m + 1, 0).day;

  List<Task> _tasksOn(DateTime day) {
    final list = _tasks.where((t) => t.occursOn(day)).toList();
    list.sort((a, b) {
      if (a.done != b.done) return a.done ? 1 : -1;
      if (a.priority != b.priority) return b.priority - a.priority;
      return (a.startAt ?? 0).compareTo(b.startAt ?? 0);
    });
    return list;
  }

  void _shiftMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
    });
  }

  void _gotoToday() {
    final n = DateTime.now();
    setState(() {
      _month = DateTime(n.year, n.month);
      _selected = DateTime(n.year, n.month, n.day);
    });
  }

  String _dateLabel(DateTime d) {
    final s = '${d.month}月${d.day}日 · 周${_weekCn[d.weekday - 1]}';
    if (_sameDay(d, DateTime.now())) return '$s · 今天';
    return s;
  }

  static String _hm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  // ── 交互 ──────────────────────────────────────────
  Future<void> _toggle(Task t) async {
    await DB.i.toggleTask(t);
    await _load();
  }

  Future<void> _delete(Task t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除这条计划？'),
        content: Text(t.title, maxLines: 3, overflow: TextOverflow.ellipsis),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true), child: Text('删除')),
        ],
      ),
    );
    if (ok != true || t.id == null) return;
    await DB.i.deleteTask(t.id!);
    await _load();
    _toast('已删除');
  }

  Future<void> _addTask(DateTime day) async {
    final title = TextEditingController();
    String subject = '';
    var hasTime = true;
    var hour = 20;
    var minute = 0;
    var priority = 1;
    var repeatKind = 0;
    var repeatDays = 0;
    var repeatInterval = 1;
    DateTime? repeatUntil;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text('${day.month}月${day.day}日 · 加一条计划'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: title,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: '要做什么',
                      hintText: '例：数学练习册 P32',
                    ),
                  ),
                  SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final s in kSubjects)
                        ChoiceChip(
                          label: Text(s, style: TextStyle(fontSize: 12)),
                          selected: subject == s,
                          onSelected: (_) =>
                              setDlg(() => subject = subject == s ? '' : s),
                        ),
                    ],
                  ),
                  SizedBox(height: 12),
                  Row(
                    children: [
                      Switch(
                        value: hasTime,
                        onChanged: (v) => setDlg(() => hasTime = v),
                      ),
                      SizedBox(width: 4),
                      Text(
                        hasTime
                            ? '${hour.toString().padLeft(2, '0')}:'
                                '${minute.toString().padLeft(2, '0')}'
                            : '不设时间',
                        style: TextStyle(fontSize: 13, color: kDim),
                      ),
                      Spacer(),
                      if (hasTime)
                        TextButton(
                          onPressed: () async {
                            final t = await showTimePicker(
                              context: ctx,
                              initialTime:
                                  TimeOfDay(hour: hour, minute: minute),
                            );
                            if (t != null) {
                              setDlg(() {
                                hour = t.hour;
                                minute = t.minute;
                              });
                            }
                          },
                          child: Text('选时间'),
                        ),
                    ],
                  ),
                  SizedBox(height: 6),
                  Row(
                    children: [
                      Text('优先级',
                          style: TextStyle(fontSize: 12, color: kDim)),
                      SizedBox(width: 10),
                      Expanded(
                        child: SegmentedButton<int>(
                          segments: [
                            ButtonSegment(value: 0, label: Text('低')),
                            ButtonSegment(value: 1, label: Text('中')),
                            ButtonSegment(value: 2, label: Text('高')),
                          ],
                          selected: {priority},
                          showSelectedIcon: false,
                          onSelectionChanged: (s) =>
                              setDlg(() => priority = s.first),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 12),
                  // 重复规则 —— 这一块以前完全没有，导致日历里加的计划
                  // 永远只是一次性的，没法安排「每周三 19:00」这种。
                  Text('重复', style: TextStyle(fontSize: 12, color: kDim)),
                  SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final e in const [
                        MapEntry(0, '不重复'),
                        MapEntry(1, '每天'),
                        MapEntry(2, '工作日'),
                        MapEntry(3, '每周'),
                        MapEntry(4, '每月'),
                        MapEntry(5, '每年'),
                      ])
                        ChoiceChip(
                          label: Text(e.value, style: TextStyle(fontSize: 12)),
                          selected: repeatKind == e.key,
                          onSelected: (_) => setDlg(() {
                            repeatKind = e.key;
                            repeatInterval = 1;
                            if (repeatKind == 3) {
                              repeatDays = 1 << (day.weekday - 1);
                            }
                          }),
                        ),
                    ],
                  ),
                  if (repeatKind == 3) ...[
                    SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        ChoiceChip(
                          label: Text('周末', style: TextStyle(fontSize: 12)),
                          selected: repeatDays == 0x60,
                          onSelected: (_) => setDlg(() => repeatDays = 0x60),
                        ),
                        for (var i = 0; i < 7; i++)
                          ChoiceChip(
                            label: Text(
                              '周${['一', '二', '三', '四', '五', '六', '日'][i]}',
                              style: TextStyle(fontSize: 12),
                            ),
                            selected: repeatDays & (1 << i) != 0,
                            onSelected: (_) =>
                                setDlg(() => repeatDays ^= (1 << i)),
                          ),
                      ],
                    ),
                  ],
                  if (repeatKind == 1 ||
                      repeatKind == 3 ||
                      repeatKind == 4 ||
                      repeatKind == 5) ...[
                    SizedBox(height: 6),
                    Row(
                      children: [
                        Text('每', style: TextStyle(fontSize: 12, color: kDim)),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          onPressed: repeatInterval <= 1
                              ? null
                              : () => setDlg(() => repeatInterval -= 1),
                          icon: Icon(Icons.remove_circle_outline, size: 17),
                        ),
                        Text('$repeatInterval',
                            style: TextStyle(fontSize: 13)),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          onPressed: repeatInterval >= 30
                              ? null
                              : () => setDlg(() => repeatInterval += 1),
                          icon: Icon(Icons.add_circle_outline, size: 17),
                        ),
                        Text(
                          repeatKind == 1
                              ? '天一次'
                              : repeatKind == 3
                                  ? '周一次'
                                  : repeatKind == 4
                                      ? '个月一次'
                                      : '年一次',
                          style: TextStyle(fontSize: 12, color: kDim),
                        ),
                      ],
                    ),
                  ],
                  if (repeatKind != 0) ...[
                    SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          repeatUntil == null
                              ? '一直重复'
                              : '重复到 ${repeatUntil!.year}/'
                                  '${repeatUntil!.month}/${repeatUntil!.day}',
                          style: TextStyle(fontSize: 12, color: kDim),
                        ),
                        Spacer(),
                        TextButton(
                          onPressed: () async {
                            final d = await showDatePicker(
                              context: ctx,
                              initialDate:
                                  repeatUntil ?? day.add(Duration(days: 60)),
                              firstDate: day,
                              lastDate: DateTime(2100),
                            );
                            if (d != null) setDlg(() => repeatUntil = d);
                          },
                          child: Text('结束日期',
                              style: TextStyle(fontSize: 12)),
                        ),
                        if (repeatUntil != null)
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            onPressed: () => setDlg(() => repeatUntil = null),
                            icon: Icon(Icons.close, size: 15),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false), child: Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true), child: Text('添加')),
          ],
        ),
      ),
    );

    if (ok != true) return;
    final s = title.text.trim();
    if (s.isEmpty) {
      _toast('先写点什么');
      return;
    }
    final start = DateTime(day.year, day.month, day.day, hour, minute);
    var mask = repeatDays;
    if (repeatKind == 3 && mask == 0) mask = 1 << (day.weekday - 1);
    final t = Task(
      title: s,
      subject: subject,
      startAt: start.millisecondsSinceEpoch,
      priority: priority,
      repeatKind: repeatKind,
      repeatDays: repeatKind == 3 ? mask : 0,
      repeatInterval: repeatKind == 0 ? 1 : repeatInterval,
      repeatAnchor: repeatKind == 0 ? null : start.millisecondsSinceEpoch,
      repeatUntil: repeatUntil?.millisecondsSinceEpoch,
    );
    await DB.i.saveTask(t);
    await _load();
    _toast('已加进 ${day.month}月${day.day}日');
  }

  // ── 界面 ──────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildTopBar(),
        Expanded(
          child: ContentWidth(
            maxWidth: BP.grid,
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(8, 0, 8, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildWeekHeader(),
                  ..._buildWeekRows(context),
                  SizedBox(height: 14),
                  _buildDayPanel(),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTopBar() {
    final monthCount = [
      for (var d = 1; d <= _daysInMonth(_month.year, _month.month); d++)
        d
    ].where((d) => _tasksOn(DateTime(_month.year, _month.month, d))
        .any((t) => !t.done)).length;

    return Padding(
      padding: EdgeInsets.fromLTRB(10, 10, 10, 6),
      child: Row(
        children: [
          Text('计划日历',
              style: TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w700, color: kFg)),
          SizedBox(width: 12),
          Text('${_month.year} 年 ${_month.month} 月',
              style: TextStyle(fontSize: 13, color: kDim)),
          SizedBox(width: 10),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: kAcc.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('$monthCount 天有安排',
                style: TextStyle(
                    fontSize: 11, color: kAcc, fontWeight: FontWeight.w600)),
          ),
          Spacer(),
          TextButton(onPressed: _gotoToday, child: Text('今天')),
          IconButton(
            tooltip: '上个月',
            onPressed: () => _shiftMonth(-1),
            icon: Icon(Icons.chevron_left, color: kFg),
          ),
          IconButton(
            tooltip: '下个月',
            onPressed: () => _shiftMonth(1),
            icon: Icon(Icons.chevron_right, color: kFg),
          ),
        ],
      ),
    );
  }

  Widget _buildWeekHeader() {
    return Padding(
      padding: EdgeInsets.fromLTRB(2, 2, 2, 4),
      child: Row(
        children: [
          for (var i = 0; i < 7; i++)
            Expanded(
              child: Center(
                child: Text(
                  _weekCn[i],
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: i >= 5 ? kFaint : kDim,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildWeekRows(BuildContext context) {
    final wide = isWideScreen(context);
    final cellH = wide ? 96.0 : 62.0;
    final first = DateTime(_month.year, _month.month, 1);
    final lead = first.weekday - 1; // 周一为 1
    final total = _daysInMonth(_month.year, _month.month);
    final rows = ((lead + total) + 6) ~/ 7;
    final out = <Widget>[];

    for (var r = 0; r < rows; r++) {
      final cells = <Widget>[];
      for (var c = 0; c < 7; c++) {
        final idx = r * 7 + c - lead + 1;
        final day = DateTime(_month.year, _month.month, idx);
        final inMonth = idx >= 1 && idx <= total;
        cells.add(Expanded(child: _dayCell(day, inMonth, cellH, wide)));
      }
      out.add(Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: cells,
      ));
    }
    return out;
  }

  Widget _dayCell(DateTime day, bool inMonth, double h, bool wide) {
    final tasks = inMonth ? _tasksOn(day) : <Task>[];
    final undone = tasks.where((t) => !t.done).toList();
    final sel = _sameDay(day, _selected);
    final today = _sameDay(day, DateTime.now());

    return Padding(
      padding: EdgeInsets.all(2),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() => _selected = day),
        child: Container(
          height: h,
          padding: EdgeInsets.fromLTRB(5, 4, 5, 4),
          decoration: BoxDecoration(
            color: !inMonth
                ? kCard2.withValues(alpha: 0.35)
                : sel
                    ? kAcc.withValues(alpha: 0.16)
                    : kCard,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: sel ? kAcc : kLine,
              width: sel ? 1.4 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: today ? kAcc : Colors.transparent,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${day.day}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: today
                            ? kOnAcc
                            : inMonth
                                ? kFg
                                : kFaint,
                      ),
                    ),
                  ),
                  Spacer(),
                  if (undone.isNotEmpty)
                    Text(
                      '${undone.length}',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: kAcc,
                      ),
                    ),
                ],
              ),
              SizedBox(height: 2),
              for (final t in undone.take(wide ? 3 : 2))
                Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: Row(
                    children: [
                      Container(
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          color: colorForSubject(t.subject),
                          shape: BoxShape.circle,
                        ),
                      ),
                      SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          t.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 10, color: kDim),
                        ),
                      ),
                    ],
                  ),
                ),
              Spacer(),
              if (tasks.isNotEmpty && undone.isEmpty)
                Text('全部完成',
                    style: TextStyle(fontSize: 9.5, color: kOk)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDayPanel() {
    final list = _tasksOn(_selected);
    final left = list.where((t) => !t.done).length;

    return Container(
      padding: EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(_dateLabel(_selected),
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: kFg)),
              SizedBox(width: 8),
              Text(
                list.isEmpty ? '没有安排' : '$left 项待办 / 共 ${list.length} 项',
                style: TextStyle(fontSize: 11.5, color: kDim),
              ),
              Spacer(),
              FilledButton.icon(
                onPressed: () => _addTask(_selected),
                icon: Icon(Icons.add, size: 16),
                label: Text('加计划'),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  textStyle: TextStyle(fontSize: 12.5),
                ),
              ),
            ],
          ),
          SizedBox(height: 6),
          if (_loading)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (list.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text('这一天还没有计划。点右上角「加计划」直接写一条。',
                  style: TextStyle(fontSize: 12, color: kFaint)),
            )
          else
            for (final t in list) _taskRow(t),
        ],
      ),
    );
  }

  Widget _taskRow(Task t) {
    final d = t.startDt ?? t.dueDt;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      // 重复计划长按：只改「这一天」的这一次；普通计划还是长按删除
      onLongPress: t.isRepeating && t.id != null
          ? () async {
              final ok = await OccurrenceActions.showMenu(
                context,
                t,
                focusDay: _selected,
              );
              if (ok) await _load();
            }
          : () => _delete(t),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              iconSize: 20,
              tooltip: t.done ? '取消完成' : '完成',
              onPressed: () => _toggle(t),
              icon: Icon(
                t.done ? Icons.check_circle : Icons.radio_button_unchecked,
                color: t.done ? kOk : kDim,
              ),
            ),
            Container(
              width: 3,
              height: 26,
              decoration: BoxDecoration(
                color: colorForSubject(t.subject),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: t.done ? kFaint : kFg,
                      decoration:
                          t.done ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  SizedBox(height: 1),
                  Row(
                    children: [
                      if (t.subject.isNotEmpty)
                        Text(t.subject,
                            style: TextStyle(fontSize: 10.5, color: kDim)),
                      if (t.subject.isNotEmpty && d != null)
                        Text(' · ', style: TextStyle(color: kFaint)),
                      if (d != null)
                        Text(_hm(d),
                            style: TextStyle(fontSize: 10.5, color: kDim)),
                      if (t.isRepeating) ...[
                        Text(' · ', style: TextStyle(color: kFaint)),
                        Text(t.repeatLabel,
                            style: TextStyle(fontSize: 10.5, color: kAcc)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (t.priority == 2)
              Padding(
                padding: EdgeInsets.only(left: 6),
                child: Icon(Icons.flag, size: 13, color: kWarn),
              ),
          ],
        ),
      ),
    );
  }
}
