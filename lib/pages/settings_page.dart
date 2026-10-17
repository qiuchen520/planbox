import 'package:flutter/material.dart';

import '../data/db.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int _week = 1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final w = await DB.i.weekNo();
    if (mounted) setState(() => _week = w);
  }

  Future<void> _setWeek(int v) async {
    if (v < 1) v = 1;
    await DB.i.setWeekNo(v);
    setState(() => _week = v);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text('我的',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.event_repeat),
            title: const Text('当前周次'),
            subtitle: Text('第 $_week 周 · ${_week.isOdd ? "单周" : "双周"}'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: () => _setWeek(_week - 1),
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                IconButton(
                  onPressed: () => _setWeek(_week + 1),
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.storage_outlined),
                title: const Text('数据存储'),
                subtitle: const Text('本地 SQLite，不上传、不联网'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('关于 PlanBox'),
                subtitle: const Text('v0.2.0 · 开源 · GPL-3.0'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Card(
          child: ListTile(
            leading: const Icon(Icons.delete_forever, color: Color(0xFFFF5D6C)),
            title: const Text('清空所有数据',
                style: TextStyle(color: Color(0xFFFF5D6C))),
            subtitle: const Text('删除全部课程与任务，不可恢复'),
            onTap: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('确定清空？'),
                  content: const Text('课程、任务、周次设置都会被删除，且无法恢复。'),
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
              if (ok == true) {
                await DB.i.wipe();
                await _load();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已清空')),
                  );
                }
              }
            },
          ),
        ),
        const SizedBox(height: 24),
        const Center(
          child: Text('数据全在本机 · 不联网 · 不收集任何信息',
              style: TextStyle(fontSize: 12, color: Color(0xFF5C6474))),
        ),
      ],
    );
  }
}
