import 'package:flutter/material.dart';

import '../data/db.dart';
import '../models.dart';
import '../theme.dart';

class TasksPage extends StatefulWidget {
  const TasksPage({super.key});

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  List<Task> _tasks = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final t = await DB.i.tasks();
    if (!mounted) return;
    setState(() {
      _tasks = t;
      _loading = false;
    });
  }

  Future<void> _toggle(Task t) async {
    t.done = !t.done;
    await DB.i.saveTask(t);
    _load();
  }

  String _fmt(DateTime d) =>
      '${d.month}/${d.day} ${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';

  Future<DateTime?> _pickDateTime(BuildContext ctx, DateTime? init) async {
    final d = await showDatePicker(
      context: ctx,
      initialDate: init ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (!ctx.mounted || d == null) return null;
    final t = await showTimePicker(
      context: ctx,
      initialTime: TimeOfDay(hour: init?.hour ?? 20, minute: init?.minute ?? 0),
    );
    return DateTime(d.year, d.month, d.day, t?.hour ?? 20, t?.minute ?? 0);
  }

  Future<void> _edit([Task? t]) async {
    final title = TextEditingController(text: t?.title ?? '');
    String subject = t?.subject ?? '';
    int priority = t?.priority ?? 1;
    bool inPool = (t?.inPool ?? 0) == 1;
    DateTime? start = t?.startDt;
    DateTime? due = t?.dueDt;

    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text(t == null ? '新建计划' : '编辑计划'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: title,
                    autofocus: t == null,
                    decoration: const InputDecoration(
                        labelText: '做什么', hintText: '数学卷子 P32-35'),
                  ),
                  const SizedBox(height: 12),
                  const Text('科目（可选）',
                      style: TextStyle(fontSize: 12, color: kDim)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final s in kSubjects)
                        ChoiceChip(
                          label: Text(s, style: const TextStyle(fontSize: 12)),
                          selected: subject == s,
                          visualDensity: VisualDensity.compact,
                          onSelected: (v) => setDlg(() => subject = v ? s : ''),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: inPool,
                    onChanged: (v) => setDlg(() {
                      inPool = v;
                      if (v) start = null;
                    }),
                    title: const Text('放进计划池（不排时间）',
                        style: TextStyle(fontSize: 14)),
                    subtitle: const Text('周末或空闲时再挑出来做',
                        style: TextStyle(fontSize: 11, color: kDim)),
                  ),
                  const Divider(height: 18),
                  _timeRow(
                    ctx: ctx,
                    icon: Icons.play_circle_outline,
                    label: '开始',
                    value: inPool ? null : start,
                    enabled: !inPool,
                    text: inPool
                        ? '计划池不排开始时间'
                        : (start == null ? '未安排开始时间' : _fmt(start!)),
                    onPick: () async {
                      final d = await _pickDateTime(ctx, start);
                      if (d != null) setDlg(() => start = d);
                    },
                    onClear: () => setDlg(() => start = null),
                  ),
                  const SizedBox(height: 8),
                  _timeRow(
                    ctx: ctx,
                    icon: Icons.flag_outlined,
                    label: '截止',
                    value: due,
                    enabled: true,
                    text: due == null ? '未设置截止时间' : _fmt(due!),
                    onPick: () async {
                      final d = await _pickDateTime(ctx, due);
                      if (d != null) setDlg(() => due = d);
                    },
                    onClear: () => setDlg(() => due = null),
                  ),
                  const SizedBox(height: 12),
                  const Text('优先级', style: TextStyle(fontSize: 12, color: kDim)),
                  const SizedBox(height: 6),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 0, label: Text('低')),
                      ButtonSegment(value: 1, label: Text('中')),
                      ButtonSegment(value: 2, label: Text('高')),
                    ],
                    selected: {priority},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) => setDlg(() => priority = s.first),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            if (t != null)
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

    if (res == 'delete' && t != null) {
      await DB.i.deleteTask(t.id!);
      await _load();
      return;
    }
    if (res != 'save') return;

    final name = title.text.trim();
    if (name.isEmpty) return;
    final target = t ??
        Task(
          title: name,
          subject: subject,
          startAt: start?.millisecondsSinceEpoch,
          dueAt: due?.millisecondsSinceEpoch,
          priority: priority,
          inPool: inPool ? 1 : 0,
        );
    target
      ..title = name
      ..subject = subject
      ..priority = priority
      ..inPool = inPool ? 1 : 0
      ..startAt = inPool ? null : start?.millisecondsSinceEpoch
      ..dueAt = due?.millisecondsSinceEpoch;
    await DB.i.saveTask(target);
    await _load();
  }

  Widget _timeRow({
    required BuildContext ctx,
    required IconData icon,
    required String label,
    required DateTime? value,
    required bool enabled,
    required String text,
    required Future<void> Function() onPick,
    required VoidCallback onClear,
  }) =>
      Row(
        children: [
          Icon(icon, size: 17, color: enabled ? kDim : kLine),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: TextStyle(fontSize: 13, color: enabled ? null : kDim)),
          ),
          TextButton(
            onPressed: enabled ? () => onPick() : null,
            child: const Text('选择'),
          ),
          if (value != null)
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: onClear,
              icon: const Icon(Icons.close, size: 16),
            ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final todo = _tasks.where((t) => !t.done && t.inPool == 0).toList();
    final pool = _tasks.where((t) => !t.done && t.inPool == 1).toList();
    final done = _tasks.where((t) => t.done).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        backgroundColor: kAcc,
        foregroundColor: const Color(0xFF08111F),
        icon: const Icon(Icons.add),
        label: const Text('新建计划',
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 96),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('计划',
                        style: TextStyle(
                            fontSize: 24, fontWeight: FontWeight.w700)),
                    const SizedBox(width: 10),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text('${todo.length + pool.length} 项待做',
                          style: const TextStyle(fontSize: 13, color: kDim)),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_tasks.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: Column(
                          children: [
                            const Text('还没有计划',
                                style: TextStyle(fontSize: 15, color: kDim)),
                            const SizedBox(height: 6),
                            Text('点右下角「新建计划」开始',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: kDim.withValues(alpha: 0.75))),
                          ],
                        ),
                      ),
                    ),
                  )
                else ...[
                  if (todo.isNotEmpty) ...[
                    const _SectionTitle('待完成'),
                    Card(
                      child: Column(
                        children: [
                          for (var i = 0; i < todo.length; i++) ...[
                            _tile(todo[i]),
                            if (i != todo.length - 1) const Divider(height: 1),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                  ],
                  if (pool.isNotEmpty) ...[
                    const _SectionTitle('计划池 · 没排时间'),
                    Card(
                      child: Column(
                        children: [
                          for (var i = 0; i < pool.length; i++) ...[
                            _tile(pool[i]),
                            if (i != pool.length - 1) const Divider(height: 1),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                  ],
                  if (done.isNotEmpty) ...[
                    _SectionTitle('已完成 · ${done.length}'),
                    Card(
                      child: Column(
                        children: [
                          for (var i = 0; i < done.length; i++) ...[
                            _tile(done[i]),
                            if (i != done.length - 1) const Divider(height: 1),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ],
            ),
    );
  }

  Widget _tile(Task t) {
    final c = t.subject.isEmpty ? kDim : colorForSubject(t.subject);
    final parts = <String>[];
    if (t.startDt != null) parts.add('开始 ${_fmt(t.startDt!)}');
    if (t.dueDt != null) {
      parts.add('${t.overdue ? "已逆期 " : "截止 "}${_fmt(t.dueDt!)}');
    }
    return ListTile(
      onTap: () => _edit(t),
      leading: Checkbox(
        value: t.done,
        activeColor: kAcc,
        onChanged: (_) => _toggle(t),
      ),
      title: Text(
        t.title,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          decoration: t.done ? TextDecoration.lineThrough : null,
          color: t.done ? kDim : null,
        ),
      ),
      subtitle: Row(
        children: [
          if (t.subject.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: c.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(t.subject, style: TextStyle(fontSize: 11, color: c)),
            ),
            const SizedBox(width: 8),
          ],
          if (parts.isNotEmpty)
            Expanded(
              child: Text(
                parts.join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: t.overdue ? const Color(0xFFFF5D6C) : kDim,
                ),
              ),
            ),
          if (t.priority == 2) ...[
            const SizedBox(width: 6),
            const Text('高',
                style: TextStyle(fontSize: 11, color: Color(0xFFFFB340))),
          ],
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: const TextStyle(fontSize: 14, color: kDim)),
      );
}
