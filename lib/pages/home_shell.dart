import 'package:flutter/material.dart';

import '../responsive.dart';
import '../theme.dart';
import 'calendar_page.dart';
import 'review_page.dart';
import 'settings_page.dart';
import 'tasks_page.dart';
import 'today_page.dart';
import 'timetable_page.dart';

class HomeShell extends StatefulWidget {
  HomeShell({super.key});

  /// 悬浮窗点了「新建」要把 tab 切过来，这里留一个全局入口
  static void goto(int i) => _HomeShellState._inst?._goto(i);

  @override
  State<HomeShell> createState() => _HomeShellState();
}
class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  /// 悬浮窗点了「新建」需要把 tab 切过来，这里留一个全局入口
  static _HomeShellState? _inst;

  @override
  void initState() {
    super.initState();
    _inst = this;
  }

  @override
  void dispose() {
    if (_inst == this) _inst = null;
    super.dispose();
  }

  void _goto(int i) {
    if (i < 0 || i >= _dests.length) return;
    setState(() => _index = i);
  }


  // 图标选择原则：一个东西只能有一种形象，别让「课表」和「日历」都长成日历。
  // 课表 = 表格（grid_on），日历 = 月历（calendar_month），计划 = 清单（checklist）。
  static List<_Dest> _dests = [
    _Dest('今日', Icons.wb_sunny_outlined, Icons.wb_sunny),
    _Dest('打卡', Icons.local_fire_department_outlined,
        Icons.local_fire_department),
    _Dest('课表', Icons.grid_on_outlined, Icons.grid_on),
    _Dest('日历', Icons.calendar_month_outlined, Icons.calendar_month),
    _Dest('计划', Icons.checklist_outlined, Icons.checklist),
    _Dest('我的', Icons.person_outline, Icons.person),
  ];

  Widget _page(int i) => switch (i) {
        0 => TodayPage(key: PageStorageKey('today')),
        1 => ReviewPage(key: PageStorageKey('review')),
        2 => TimetablePage(key: PageStorageKey('timetable')),
        3 => CalendarPage(key: PageStorageKey('calendar')),
        4 => TasksPage(key: PageStorageKey('tasks')),
        _ => SettingsPage(key: PageStorageKey('settings')),
      };

  @override
  Widget build(BuildContext context) {
    final wide = isWideScreen(context);
    final body = SafeArea(bottom: !wide, child: _page(_index));

    if (wide) {
      // 平板 / 横屏：左侧竖排导航。自己画而不是用 NavigationRail，
      // 因为 5 个 Tab 时 M3 的默认 rail 会把标签压得很紧，还没法加顶部徽标。
      return Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              Container(
                width: 96,
                decoration: BoxDecoration(
                  color: kCard,
                  border: Border(right: BorderSide(color: kLine)),
                ),
                child: Column(
                  children: [
                    SizedBox(height: 14),
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: kAcc.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.check_box_outlined,
                          color: kAcc, size: 22),
                    ),
                    SizedBox(height: 7),
                    Text('计划盒',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: kFg)),
                    SizedBox(height: 12),
                    Divider(height: 1, color: kLine),
                    Expanded(
                      child: ListView(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        children: [
                          for (var i = 0; i < _dests.length; i++) _railItem(i),
                        ],
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.only(bottom: 14, top: 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.cloud_off, size: 11, color: kFaint),
                          SizedBox(width: 4),
                          Text('离线',
                              style:
                                  TextStyle(fontSize: 10, color: kFaint)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(child: body),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        height: 58,
        // 六个 Tab 在手机上每个只有 60dp 宽，中文两字 + 图标并排必挤。
        // 只让选中项显示文字，图标恒居中，宽度够了也不会左右乱跳。
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
        backgroundColor: kCard,
        indicatorColor: kAcc.withValues(alpha: 0.18),
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (final d in _dests)
            NavigationDestination(
              icon: Icon(d.icon, size: 22),
              selectedIcon: Icon(d.active, size: 22),
              label: d.label,
            ),
        ],
      ),
    );
  }

  Widget _railItem(int i) {
    final d = _dests[i];
    final sel = i == _index;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Material(
        color: sel ? kAcc.withValues(alpha: 0.16) : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(() => _index = i),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 9),
            child: Column(
              children: [
                Icon(sel ? d.active : d.icon,
                    size: 22, color: sel ? kAcc : kDim),
                SizedBox(height: 4),
                Text(
                  d.label,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.1,
                    fontWeight: sel ? FontWeight.w700 : FontWeight.w400,
                    color: sel ? kAcc : kDim,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Dest {
  final String label;
  final IconData icon;
  final IconData active;
  _Dest(this.label, this.icon, this.active);
}