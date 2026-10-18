import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/db.dart';
import '../models.dart';
import '../palette.dart';
import '../responsive.dart';
import '../services/backup.dart';
import '../services/notify.dart';
import '../theme.dart';
import 'agreement.dart';

class SettingsPage extends StatefulWidget {
  SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  DateTime? _start;
  int _total = 20;
  int _current = 1;
  List<PeriodTime> _pt = kDefaultPeriodTimes;

  /// 「每节课的时间」默认收起：一天最多改一次，没必要一直占屏幕
  bool _ptOpen = false;

  // 通知
  bool _nEnabled = false;
  int _nLead = 10;
  bool _nSound = true;
  bool _nVibrate = true;

  // 备份
  List<File> _backups = const [];
  bool _busy = false;

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
    await Notify.i.load();
    final backups = await Backup.listLocal();
    if (!mounted) return;
    setState(() {
      _start = s;
      _total = t;
      _current = c;
      _pt = pt;
      _nEnabled = Notify.i.enabled;
      _nLead = Notify.i.lead;
      _nSound = Notify.i.sound;
      _nVibrate = Notify.i.vibrate;
      _backups = backups;
    });
  }

  void _toast(String msg) {
    if (!mounted) return;
    final m = ScaffoldMessenger.maybeOf(context);
    m?.clearSnackBars();
    m?.showSnackBar(SnackBar(content: Text(msg)));
  }

  /// 复制到剪贴板并给个回执，方便别人加群 / 加好友
  Future<void> _copy(String label, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    _toast('已复制$label：$value');
  }

  String _d(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return ContentWidth(
      child: ListView(
      padding: EdgeInsets.fromLTRB(20, 10, 20, 28),
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text('我的',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
        ),

        // ── 配色 ─────────────────────────────
        _H('配色'),
        Card(
          child: Padding(
            padding: EdgeInsets.fromLTRB(14, 14, 14, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('外观',
                    style: TextStyle(
                        fontSize: 12.5,
                        color: kDim,
                        fontWeight: FontWeight.w600)),
                SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<bool>(
                    segments: [
                      ButtonSegment(
                          value: true,
                          label: Text('深色'),
                          icon: Icon(Icons.dark_mode_outlined, size: 16)),
                      ButtonSegment(
                          value: false,
                          label: Text('浅色'),
                          icon: Icon(Icons.light_mode_outlined, size: 16)),
                    ],
                    selected: {Pal.dark},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) async {
                      await Pal.setDark(s.first);
                      if (mounted) setState(() {});
                    },
                  ),
                ),
                SizedBox(height: 20),
                Text('主题色',
                    style: TextStyle(
                        fontSize: 12.5,
                        color: kDim,
                        fontWeight: FontWeight.w600)),
                SizedBox(height: 10),
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
                SizedBox(height: 20),
                Text('科目配色',
                    style: TextStyle(
                        fontSize: 12.5,
                        color: kDim,
                        fontWeight: FontWeight.w600)),
                SizedBox(height: 10),
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
                SizedBox(height: 14),
                // 当前色板预览
                Row(
                  children: [
                    for (final c in Pal.subjects) ...[
                      Expanded(
                        child: Container(
                          height: 8,
                          margin: EdgeInsets.only(right: 3),
                          decoration: BoxDecoration(
                            color: c,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                SizedBox(height: 10),
                Text('切换科目配色会自动重算已有课程的颜色',
                    style: TextStyle(fontSize: 11, color: kFaint)),
              ],
            ),
          ),
        ),

        // ── 学期 ─────────────────────────────
        _H('学期'),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: Icon(Icons.school_outlined),
                title: Text('开学日期'),
                subtitle: Text(_start == null
                    ? '未设置 · 周次需手动指定'
                    : '${_d(_start!)}（第 1 周周一）'),
                trailing: Icon(Icons.chevron_right, size: 18, color: kDim),
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
              Divider(height: 1),
              ListTile(
                leading: Icon(Icons.calendar_month_outlined),
                title: Text('总周数'),
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
                      icon: Icon(Icons.remove_circle_outline),
                    ),
                    IconButton(
                      onPressed: () async {
                        if (_total >= 30) return;
                        await DB.i.setTotalWeeks(_total + 1);
                        await _load();
                      },
                      icon: Icon(Icons.add_circle_outline),
                    ),
                  ],
                ),
              ),
              Divider(height: 1),
              ListTile(
                leading: Icon(Icons.today_outlined),
                title: Text('当前周次'),
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
                            icon: Icon(Icons.remove_circle_outline),
                          ),
                          IconButton(
                            onPressed: () async {
                              if (_current >= _total) return;
                              await DB.i.setWeekNo(_current + 1);
                              await _load();
                            },
                            icon: Icon(Icons.add_circle_outline),
                          ),
                        ],
                      )
                    : null,
              ),
            ],
          ),
        ),

        // ── 节次时间（默认折叠） ──────────────
        _H('课表时间管理'),
        Card(
          child: Column(
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => setState(() => _ptOpen = !_ptOpen),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, 14, 12, 14),
                  child: Row(
                    children: [
                      Icon(Icons.schedule, size: 20, color: kAcc),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('每节课的时间',
                                style: TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w600)),
                            SizedBox(height: 2),
                            Text(
                              _ptOpen
                                  ? '点任意一节可修改起止时间'
                                  : '共 ${_pt.length} 节 · 第 1 节 ${_pt.first.s} 开始',
                              style:
                                  TextStyle(fontSize: 11.5, color: kDim),
                            ),
                          ],
                        ),
                      ),
                      AnimatedRotation(
                        turns: _ptOpen ? 0.5 : 0,
                        duration: Duration(milliseconds: 180),
                        child: Icon(Icons.expand_more,
                            size: 20, color: kDim),
                      ),
                    ],
                  ),
                ),
              ),
              AnimatedCrossFade(
                firstChild: SizedBox(width: double.infinity, height: 0),
                secondChild: Column(
                  children: [
                    Divider(height: 1),
                    for (var i = 0; i < _pt.length; i++) ...[
                      ListTile(
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        leading: CircleAvatar(
                          radius: 11,
                          backgroundColor: kCard2,
                          child: Text('${i + 1}',
                              style:
                                  TextStyle(fontSize: 10, color: kDim)),
                        ),
                        title: Text('第 ${i + 1} 节',
                            style: TextStyle(fontSize: 13.5)),
                        trailing: Text('${_pt[i].s} - ${_pt[i].e}',
                            style:
                                TextStyle(fontSize: 12.5, color: kAcc)),
                        onTap: () => _editPeriod(i),
                      ),
                      if (i != _pt.length - 1) Divider(height: 1),
                    ],
                  ],
                ),
                crossFadeState: _ptOpen
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                duration: Duration(milliseconds: 200),
              ),
            ],
          ),
        ),

        // ── 提醒 ─────────────────────────────
        _H('提醒'),
        Card(
          child: Column(
            children: [
              SwitchListTile(
                secondary: Icon(Icons.notifications_active_outlined),
                title: Text('计划提醒'),
                subtitle: Text(_nEnabled
                    ? '到点会推送通知（记得允许通知权限）'
                    : '已关闭，计划不会提醒你'),
                value: _nEnabled,
                onChanged: (v) async {
                  if (v) {
                    final ok = await Notify.i.requestPermission();
                    if (!ok && mounted) {
                      _toast('没有通知权限，请到系统设置里允许「计划盒」发通知');
                    }
                  }
                  await Notify.i.saveConfig(enabled: v);
                  await Notify.i.resyncAll();
                  await _load();
                },
              ),
              Divider(height: 1),
              Padding(
                padding: EdgeInsets.fromLTRB(16, 10, 16, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.alarm, size: 20,
                            color: _nEnabled ? kAcc : kDim),
                        SizedBox(width: 12),
                        Text('提前多久提醒',
                            style: TextStyle(
                                fontSize: 14.5,
                                color: _nEnabled ? kFg : kDim)),
                        Spacer(),
                        Text(_nLead == 0 ? '准点' : '$_nLead 分钟前',
                            style: TextStyle(
                                fontSize: 12.5,
                                color: _nEnabled ? kAcc : kDim,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                    SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final m in [0, 5, 10, 15, 30])
                          ChoiceChip(
                            label: Text(m == 0 ? '准点' : '$m 分'),
                            selected: _nLead == m,
                            onSelected: _nEnabled
                                ? (_) async {
                                    await Notify.i.saveConfig(lead: m);
                                    await Notify.i.resyncAll();
                                    await _load();
                                  }
                                : null,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Divider(height: 1),
              SwitchListTile(
                secondary: Icon(Icons.volume_up_outlined),
                title: Text('声音'),
                subtitle: Text('提醒时播放提示音'),
                value: _nSound,
                onChanged: _nEnabled
                    ? (v) async {
                        await Notify.i.saveConfig(sound: v);
                        await _load();
                      }
                    : null,
              ),
              Divider(height: 1),
              SwitchListTile(
                secondary: Icon(Icons.vibration),
                title: Text('震动'),
                subtitle: Text('提醒时让手机震一下'),
                value: _nVibrate,
                onChanged: _nEnabled
                    ? (v) async {
                        await Notify.i.saveConfig(vibrate: v);
                        await _load();
                      }
                    : null,
              ),
              Divider(height: 1),
              ListTile(
                leading: Icon(Icons.send_outlined),
                title: Text('发一条试试'),
                subtitle: Text('验证通知、声音、震动是否都正常'),
                trailing: Icon(Icons.chevron_right, size: 18, color: kDim),
                enabled: _nEnabled,
                onTap: _nEnabled
                    ? () async {
                        await Notify.i.showTest();
                        _toast('已发送，请下拉通知栏看看');
                      }
                    : null,
              ),
            ],
          ),
        ),

        // ── 数据 ─────────────────────────────
        _H('数据'),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: Icon(Icons.storage_outlined),
                title: Text('存储方式'),
                subtitle: Text('本地 SQLite，不上传、不联网'),
              ),
              Divider(height: 1),
              ListTile(
                leading: Icon(Icons.ios_share),
                title: Text('导出备份'),
                subtitle: Text('生成 JSON 并分享到网盘 / 微信 / 邮箱'),
                enabled: !_busy,
                onTap: _exportBackup,
              ),
              Divider(height: 1),
              ListTile(
                leading: Icon(Icons.file_open_outlined),
                title: Text('从文件导入'),
                subtitle: Text('选一个 .json 备份恢复，会覆盖现有数据'),
                enabled: !_busy,
                onTap: _importBackup,
              ),
              Divider(height: 1),
              ListTile(
                leading: Icon(Icons.save_outlined),
                title: Text('在本机留一份'),
                subtitle: Text('存到应用目录，重装前可以用文件管理器拷走'),
                enabled: !_busy,
                onTap: _saveLocalBackup,
              ),
              if (_backups.isNotEmpty) ...[
                Divider(height: 1),
                Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Row(
                    children: [
                      Text('本机备份 ${_backups.length} 份',
                          style: TextStyle(
                              fontSize: 12,
                              color: kDim,
                              fontWeight: FontWeight.w600)),
                      Spacer(),
                      Text('点一下恢复',
                          style: TextStyle(fontSize: 11, color: kFaint)),
                    ],
                  ),
                ),
                for (final f in _backups.take(8))
                  ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    leading: Icon(Icons.description_outlined,
                        size: 18, color: kDim),
                    title: Text(_backupLabel(f),
                        style: TextStyle(fontSize: 13)),
                    trailing: Text('${_kb(f)} KB',
                        style: TextStyle(fontSize: 11, color: kFaint)),
                    onTap: () => _restoreFromLocal(f),
                  ),
                SizedBox(height: 6),
              ],
              Divider(height: 1),
              ListTile(
                leading: Icon(Icons.delete_forever, color: kDanger),
                title: Text('清空所有数据',
                    style: TextStyle(color: kDanger)),
                subtitle: Text('课程、计划、设置全部删除，不可恢复'),
                onTap: _wipe,
              ),
            ],
          ),
        ),

        SizedBox(height: 20),
        // ── 关于 ─────────────────────────────
        _H('关于'),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: Icon(Icons.person_outline),
                title: Text('作者'),
                subtitle: Text('${About.author}　开源 GPL-3.0'),
              ),
              Divider(height: 1),
              ListTile(
                leading: Icon(Icons.chat_bubble_outline),
                title: Text('QQ'),
                subtitle: Text(About.qq),
                trailing: Icon(Icons.copy, size: 16, color: kFaint),
                onTap: () => _copy('QQ 号', About.qq),
              ),
              Divider(height: 1),
              ListTile(
                leading: Icon(Icons.auto_awesome_outlined),
                title: Text('小红书'),
                subtitle: Text(About.xhs),
                trailing: Icon(Icons.copy, size: 16, color: kFaint),
                onTap: () => _copy('小红书名', About.xhs),
              ),
              Divider(height: 1),
              ListTile(
                leading: Icon(Icons.groups_outlined),
                title: Text('官方 QQ 群'),
                subtitle: Text(About.qqGroup),
                trailing: Icon(Icons.copy, size: 16, color: kFaint),
                onTap: () => _copy('QQ 群号', About.qqGroup),
              ),
              Divider(height: 1),
              ListTile(
                leading: Icon(Icons.gavel_outlined),
                title: Text('使用协议与隐私说明'),
                subtitle: Text('数据只在本机、提醒不保证绝对准时、免责声明'),
                onTap: () => showAgreementDialog(context, mustAgree: false),
              ),
              Divider(height: 1),
              ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('版本'),
                subtitle: Text('v${About.version} · 构建号见安装包'),
              ),
            ],
          ),
        ),
        SizedBox(height: 16),
        Center(
          child: Text('PlanBox v${About.version} · 开源 GPL-3.0',
              style: TextStyle(fontSize: 11, color: kFaint)),
        ),
        SizedBox(height: 6),
        Center(
          child: Text('© 2026 ${About.author} · 数据全在本机 · 不联网 · 不收集任何信息',
              style: TextStyle(fontSize: 11, color: kFaint)),
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
        title: Text('确定清空？'),
        content: Text('课表、临时调课、计划、学期设置都会被删除，且无法恢复。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: kDanger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('清空'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await DB.i.wipe();
    await Notify.i.cancelAll();
    // 设置被清空，配色也回到默认
    Pal.accIdx = 0;
    Pal.subIdx = 0;
    Pal.rev.value++;
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('已清空')));
  }

  // ── 备份 ──────────────────────────────────────────
  String _backupLabel(File f) {
    final name = f.path.split('/').last;
    // planbox-backup-20261017-233012.json → 2026-10-17 23:30
    final m = RegExp(r'(\d{4})(\d{2})(\d{2})-(\d{2})(\d{2})').firstMatch(name);
    if (m == null) return name;
    return '${m.group(1)}-${m.group(2)}-${m.group(3)} '
        '${m.group(4)}:${m.group(5)}';
  }

  int _kb(File f) {
    try {
      return (f.lengthSync() / 1024).ceil();
    } catch (_) {
      return 0;
    }
  }

  Future<void> _exportBackup() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await Backup.exportAndShare();
      await _load();
      _toast('备份已生成，选个地方存下来就行');
    } catch (e) {
      _toast('导出失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveLocalBackup() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final f = await Backup.writeLocal();
      await _load();
      _toast('已保存到 ${f.path}');
    } catch (e) {
      _toast('保存失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importBackup() async {
    if (_busy) return;
    Map<String, dynamic>? data;
    try {
      data = await Backup.pickAndRead();
    } catch (e) {
      _toast('读不了这个文件：$e');
      return;
    }
    if (data == null) return; // 用户取消
    await _doRestore(
      () => Backup.restore(data!),
      what: '所选文件',
    );
  }

  Future<void> _restoreFromLocal(File f) async {
    await _doRestore(
      () => Backup.restoreFromFile(f),
      what: _backupLabel(f),
    );
  }

  /// 恢复前的二次确认：这是破坏性操作，必须说清楚会覆盖什么
  Future<void> _doRestore(Future<int> Function() run,
      {required String what}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('用「$what」覆盖现有数据？'),
        content: Text('当前的课表、计划、设置都会被替换成备份里的内容，'
            '这一步不能撤销。\n\n建议先「导出备份」留一份现在数据的副本。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kDanger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('覆盖恢复'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      final n = await run();
      // 备份里带着配色设置，重读一次让它生效（load 内部会 rev++）
      await Pal.load();
      await _load();
      _toast('恢复完成，共 $n 条计划');
    } catch (e) {
      _toast('恢复失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _H extends StatelessWidget {
  final String text;
  _H(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(left: 4, bottom: 8, top: 6),
        child: Text(text,
            style: TextStyle(
                fontSize: 13, color: kDim, fontWeight: FontWeight.w600)),
      );
}

/// 主题色圆点
class _AccentDot extends StatelessWidget {
  final AccentPreset preset;
  final bool selected;
  final VoidCallback onTap;
  _AccentDot({
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
            duration: Duration(milliseconds: 140),
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
                ? Icon(Icons.check, size: 18, color: Colors.white)
                : null,
          ),
          SizedBox(height: 4),
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
  _SubPaletteChip({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Duration(milliseconds: 140),
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                    margin: EdgeInsets.only(right: 2),
                    decoration:
                        BoxDecoration(color: c, shape: BoxShape.circle),
                  ),
              ],
            ),
            SizedBox(height: 5),
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
                  SizedBox(width: 4),
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