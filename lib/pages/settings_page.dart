import 'package:flutter/material.dart';

import '../data/db.dart';
import '../models.dart';
import '../palette.dart';
import '../responsive.dart';
import '../theme.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  DateTime? _start;
  int _total = 20;
  int _current = 1;
  List<PeriodTime> _pt = kDefaultPeriodTimes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await DB.i.semesterStart();
    final t = await DB.i.totalWeeks();
    final c = await DB.i.currentWeek();
    final pt = await DB.i.periodTimes();
    if (!mounted) return;
    setState(() {
      _start = s;
      _total = t;
      _current = c;
      _pt = pt;
    });
  }

  String _d(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return ContentWidth(
      child: ListView(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text('我的',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
        ),

        // ── 配色 ─────────────────────────────
        const _H('配色'),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('主题色',
                    style: TextStyle(
                        fontSize: 12.5,
                        color: kDim,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (var i = 0; i < kAccentPresets.length; i++)
                      _AccentDot(
                        preset: kAccentPresets[i],
                        selected: Pal.accIdx == i,
                        onTap: () async {
                          await Pal.setAccent(i);
                          if (mounted) setState(() {});
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                const Text('科目配色',
                    style: TextStyle(
                        fontSize: 12.5,
                        color: kDim,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < kSubjectPresets.length; i++)
                      _SubPaletteChip(
                        preset: kSubjectPresets[i],
                        selected: Pal.subIdx == i,
                        onTap: () async {
                          await Pal.setSubjectPreset(i);
                          if (mounted) setState(() {});
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                // 当前色板预览
                Row(
                  children: [
                    for (final c in Pal.subjects) ...[
                      Expanded(
                        child: Container(
                          height: 8,
                          margin: const EdgeInsets.only(right: 3),
                          decoration: BoxDecoration(
                            color: c,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                const Text('切换科目配色会自动重算已有课程的颜色',
                    style: TextStyle(fontSize: 11, color: kFaint)),
              ],
            ),
          ),
        ),

        // ── 学期 ─────────────────────────────
        const _H('学期'),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.school_outlined),
                title: const Text('开学日期'),
                subtitle: Text(_start == null
                    ? '未设置 · 周次需手动指定'
                    : '${_d(_start!)}（第 1 周周一）'),
                trailing: const Icon(Icons.chevron_right, size: 18, color: kDim),
                onTap: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _start ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (d == null) return;
                  await DB.i.setSemesterStart(d);
                  await _load();
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.calendar_month_outlined),
                title: const Text('总周数'),
                subtitle: Text('$_total 周'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: () async {
                        if (_total <= 1) return;
                        await DB.i.setTotalWeeks(_total - 1);
                        await _load();
                      },
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    IconButton(
                      onPressed: () async {
                        if (_total >= 30) return;
                        await DB.i.setTotalWeeks(_total + 1);
                        await _load();
                      },
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.today_outlined),
                title: const Text('当前周次'),
                subtitle: Text(
                    '第 $_current 周 · ${_current.isOdd ? "单周" : "双周"}'
                    '${_start == null ? "（手动）" : "（自动计算）"}'),
                trailing: _start == null
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            onPressed: () async {
                              if (_current <= 1) return;
                              await DB.i.setWeekNo(_current - 1);
                              await _load();
                            },
                            icon: const Icon(Icons.remove_circle_outline),
                          ),
                          IconButton(
                            onPressed: () async {
                              if (_current >= _total) return;
                              await DB.i.setWeekNo(_current + 1);
                              await _load();
                            },
                            icon: const Icon(Icons.add_circle_outline),
                          ),
                        ],
                      )
                    : null,
              ),
            ],
          ),
        ),

        // ── 节次时间 ─────────────────────────
        const _H('每节课的时间'),
        Card(
          child: Column(
            children: [
              for (var i = 0; i < _pt.length; i++) ...[
                ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 12,
                    backgroundColor: kCard2,
                    child: Text('${i + 1}',
                        style: const TextStyle(fontSize: 11, color: kDim)),
                  ),
                  title: Text('第 ${i + 1} 节',
                      style: const TextStyle(fontSize: 14)),
                  trailing: Text('${_pt[i].s} - ${_pt[i].e}',
                      style: TextStyle(fontSize: 13, color: kAcc)),
                  onTap: () => _editPeriod(i),
                ),
                if (i != _pt.length - 1) const Divider(height: 1),
              ],
            ],
          ),
        ),

        // ── 数据 ─────────────────────────────
        const _H('数据'),
        Card(
          child: Column(
            children: [
              const ListTile(
                leading: Icon(Icons.storage_outlined),
                title: Text('存储方式'),
                subtitle: Text('本地 SQLite，不上传、不联网'),
              ),
              const Divider(height: 1),
              ListTile(
                leading:
                    const Icon(Icons.delete_forever, color: Color(0xFFFF5D6C)),
                title: const Text('清空所有数据',
                    style: TextStyle(color: Color(0xFFFF5D6C))),
                subtitle: const Text('课程、计划、设置全部删除，不可恢复'),
                onTap: _wipe,
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),
        const Center(
          child: Text('PlanBox v0.4.0 · 开源 GPL-3.0',
              style: TextStyle(fontSize: 11, color: Color(0xFF5C6474))),
        ),
        const SizedBox(height: 6),
        const Center(
          child: Text('数据全在本机 · 不联网 · 不收集任何信息',
              style: TextStyle(fontSize: 11, color: Color(0xFF5C6474))),
        ),
      ],
      ),
    );
  }

  Future<void> _editPeriod(int i) async {
    final cur = _pt[i];
    final start = await _pickTime(cur.s);
    if (!mounted || start == null) return;
    final end = await _pickTime(cur.e);
    if (!mounted || end == null) return;
    final list = List<PeriodTime>.from(_pt);
    list[i] = PeriodTime(start, end);
    await DB.i.setPeriodTimes(list);
    await _load();
    // 顺带把后面没改的节次整体平移？不做，保持可预期
  }

  Future<String?> _pickTime(String init) async {
    final p = init.split(':');
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.tryParse(p.isNotEmpty ? p[0] : '8') ?? 8,
        minute: int.tryParse(p.length > 1 ? p[1] : '0') ?? 0,
      ),
    );
    if (t == null) return null;
    return '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _wipe() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确定清空？'),
        content: const Text('课表、临时调课、计划、学期设置都会被删除，且无法恢复。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFF5D6C)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await DB.i.wipe();
    // 设置被清空，配色也回到默认
    Pal.accIdx = 0;
    Pal.subIdx = 0;
    Pal.rev.value++;
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已清空')));
  }
}

class _H extends StatelessWidget {
  final String text;
  const _H(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8, top: 6),
        child: Text(text,
            style: const TextStyle(
                fontSize: 13, color: kDim, fontWeight: FontWeight.w600)),
      );
}

/// 主题色圆点
class _AccentDot extends StatelessWidget {
  final AccentPreset preset;
  final bool selected;
  final VoidCallback onTap;
  const _AccentDot({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [preset.glow, preset.color],
              ),
              border: Border.all(
                color: selected ? Colors.white : Colors.transparent,
                width: 2,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                          color: preset.color.withValues(alpha: 0.5),
                          blurRadius: 10)
                    ]
                  : null,
            ),
            child: selected
                ? const Icon(Icons.check, size: 18, color: Colors.white)
                : null,
          ),
          const SizedBox(height: 4),
          Text(preset.name,
              style: TextStyle(
                  fontSize: 10,
                  color: selected ? preset.color : kFaint)),
        ],
      ),
    );
  }
}

/// 科目色板选择卡
class _SubPaletteChip extends StatelessWidget {
  final SubjectPreset preset;
  final bool selected;
  final VoidCallback onTap;
  const _SubPaletteChip({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? kAcc.withValues(alpha: 0.12) : kCard2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? kAcc : kLine),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final c in preset.colors.take(8))
                  Container(
                    width: 9,
                    height: 9,
                    margin: const EdgeInsets.only(right: 2),
                    decoration:
                        BoxDecoration(color: c, shape: BoxShape.circle),
                  ),
              ],
            ),
            const SizedBox(height: 5),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(preset.name,
                    style: TextStyle(
                        fontSize: 11.5,
                        color: selected ? kAcc : kDim,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w400)),
                if (selected) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.check_circle, size: 12, color: kAcc),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
