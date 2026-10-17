import 'package:flutter/material.dart';

import '../responsive.dart';
import '../theme.dart';
import 'settings_page.dart';
import 'tasks_page.dart';
import 'today_page.dart';
import 'timetable_page.dart';

class HomeShell extends StatefulWidget {
  HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static List<_Dest> _dests = [
    _Dest('今日', Icons.wb_sunny_outlined, Icons.wb_sunny),
    _Dest('课表', Icons.calendar_month_outlined, Icons.calendar_month),
    _Dest('计划', Icons.checklist_outlined, Icons.checklist),
    _Dest('我的', Icons.person_outline, Icons.person),
  ];

  Widget _page(int i) => switch (i) {
        0 => TodayPage(key: PageStorageKey('today')),
        1 => TimetablePage(key: PageStorageKey('timetable')),
        2 => TasksPage(key: PageStorageKey('tasks')),
        _ => SettingsPage(key: PageStorageKey('settings')),
      };

  @override
  Widget build(BuildContext context) {
    final wide = isWideScreen(context);
    final body = SafeArea(bottom: !wide, child: _page(_index));

    if (wide) {
      // 平板 / 横屏：左侧竖排导航，右侧留满内容区
      return Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              NavigationRail(
                selectedIndex: _index,
                onDestinationSelected: (i) => setState(() => _index = i),
                labelType: NavigationRailLabelType.all,
                backgroundColor: kCard,
                indicatorColor: kAcc.withValues(alpha: 0.20),
                selectedIconTheme: IconThemeData(color: kAcc, size: 24),
                unselectedIconTheme: IconThemeData(color: kDim, size: 22),
                selectedLabelTextStyle: TextStyle(
                    color: kAcc, fontSize: 12, fontWeight: FontWeight.w600),
                unselectedLabelTextStyle:
                    TextStyle(color: kDim, fontSize: 12),
                leading: Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Icon(Icons.check_box_outlined,
                      color: kAcc, size: 26),
                ),
                destinations: [
                  for (final d in _dests)
                    NavigationRailDestination(
                      icon: Icon(d.icon),
                      selectedIcon: Icon(d.active),
                      label: Text(d.label),
                    ),
                ],
              ),
              VerticalDivider(width: 1, thickness: 1, color: kLine),
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
        height: 62,
        backgroundColor: kCard,
        indicatorColor: kAcc.withValues(alpha: 0.18),
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (final d in _dests)
            NavigationDestination(
              icon: Icon(d.icon),
              selectedIcon: Icon(d.active),
              label: d.label,
            ),
        ],
      ),
    );
  }
}

class _Dest {
  final String label;
  final IconData icon;
  final IconData active;
  const _Dest(this.label, this.icon, this.active);
}
