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

  Future<void> _edit([Task? t]) async {
    final title = TextEditingController(text: t?.title ?? '');
    String subject = t?.subject ?? '';
    int priority = t?.priority ?? 1;
    DateTime? due = t?.dueAt == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(t!.dueAt!);

    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text(t == null ? '新建任务' : '编辑任务'),
          content: SizedBox(
            width: 430,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: title,
                    autofocus: t == null,
                    decoration: const InputDecoration(
                        labelText: '任务名称', hintText: '数学作业 P32-35'),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final s in kSubjects)
                        ChoiceChip(
                          label: Text(s, style: const TextStyle(fontSize: 12)),
                          selected: subject == s,
                          visualDensity: VisualDensity.compact,
                          onSelected: (v) =>
                              setDlg(() => subject = v ? s : ''),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const Icon(Icons.schedule, size: 18, color: kDim),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          due == null
                              ? '未设置截止时间'
                              : '截止：${due!.month}/${due!.day} '
                                  '${due!.hour.toString().padLeft(2, "0")}:'
                                  '${due!.minute.toString().padLeft(2, "0")}',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          final d = await showDatePicker(
                            context: ctx,
                            initialDate: due ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                          );
                          if (d == null) return;
                          final tm = await showTimePicker(
                            context: ctx,
                            initialTime: TimeOfDay(
                                hour: due?.hour ?? 22, minute: due?.minute ?? 0),
                          );
                          setDlg(() => due = DateTime(d.year, d.month, d.day,
                              tm?.hour ?? 22, tm?.minute ?? 0));
                        },
                        child: const Text('选择'),
                      ),
                      if (due != null)
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          onPressed: () => setDlg(() => due = null),
                          icon: const Icon(Icons.close, size: 16),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 0, label: Text('低')),
                      ButtonSegment(value: 1, label: Text('中')),
                      ButtonSegment(value: 2, label: Text('高')),
                    ],
                    selected: {priority},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) =>
                        setDlg(() => priority = s.first),
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
    } else if (res == 'save') {
      final name = title.text.trim();
      if (name.isEmpty) return;
      final target = t ??
          Task(
            title: name,
            subject: subject,
            dueAt: due?.millisecondsSinceEpoch,
            priority: priority,
          );
      target
        ..title = name
        ..subject = subject
        ..priority = priority
        ..dueAt = due?.millisecondsSinceEpoch;
      await DB.i.saveTask(target);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final todo = _tasks.where((t) => !t.done).toList();
    final done = _tasks.where((t) => t.done).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        backgroundColor: kAcc,
        foregroundColor: const Color(0xFF08111F),
        icon: const Icon(Icons.add),
        label: const Text('新建任务',
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 96),
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
                      child: Text('${todo.length} 项未完成',
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
                            const Text('还没有任务',
                                style:
                                    TextStyle(fontSize: 15, color: kDim)),
                            const SizedBox(height: 6),
                            Text('点右下角「新建任务」开始',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: kDim.withValues(alpha: 0.7))),
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
                  if (done.isNotEmpty) ...[
                    const _SectionTitle('已完成'),
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
              child: Text(t.subject,
                  style: TextStyle(fontSize: 11, color: c)),
            ),
            const SizedBox(width: 8),
          ],
          if (t.dueAt != null)
            Text(
              _due(t),
              style: TextStyle(
                fontSize: 11,
                color: t.overdue ? const Color(0xFFFF5D6C) : kDim,
              ),
            ),
          if (t.priority == 2) ...[
            const SizedBox(width: 8),
            const Text('高优先',
                style: TextStyle(fontSize: 11, color: Color(0xFFFFB340))),
          ],
        ],
      ),
    );
  }

  String _due(Task t) {
    final d = DateTime.fromMillisecondsSinceEpoch(t.dueAt!);
    return '${d.month}/${d.day} '
        '${d.hour.toString().padLeft(2, "0")}:${d.minute.toString().padLeft(2, "0")}'
        '${t.overdue ? " · 已逾期" : ""}';
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: const TextStyle(fontSize: 14, color: kDim)),
      );
}
