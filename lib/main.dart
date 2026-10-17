import 'package:flutter/material.dart';

// ── 设计 token（见 docs/DESIGN.md §5.2）──
const Color kBg = Color(0xFF0F1115);
const Color kCard = Color(0xFF181B22);
const Color kCard2 = Color(0xFF20242D);
const Color kLine = Color(0xFF2A2F3A);
const Color kAcc = Color(0xFF5B9CFF);
const Color kDim = Color(0xFF8B93A5);

/// 科目色板（8 色循环）
const List<Color> kSubjectColors = [
  Color(0xFF5B9CFF),
  Color(0xFFFF8A65),
  Color(0xFF4DD0E1),
  Color(0xFFBA68C8),
  Color(0xFF81C784),
  Color(0xFFFFD54F),
  Color(0xFFF06292),
  Color(0xFF9575CD),
];

void main() => runApp(const PlanBoxApp());

class PlanBoxApp extends StatelessWidget {
  const PlanBoxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PlanBox',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: kAcc,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: kBg,
        cardColor: kCard,
        dividerColor: kLine,
        appBarTheme: const AppBarTheme(
          backgroundColor: kBg,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          titleTextStyle: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
      home: const TimetablePage(),
    );
  }
}

/// 一节课：科目 + 教室
class Lesson {
  String subject;
  String room;
  Lesson(this.subject, [this.room = '']);

  Color get color {
    var h = 0;
    for (final c in subject.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return kSubjectColors[h % kSubjectColors.length];
  }
}

class TimetablePage extends StatefulWidget {
  const TimetablePage({super.key});

  @override
  State<TimetablePage> createState() => _TimetablePageState();
}

class _TimetablePageState extends State<TimetablePage> {
  static const List<String> kDays = ['周一', '周二', '周三', '周四', '周五'];
  static const int kPeriods = 8;

  /// key = "周一-3"
  final Map<String, Lesson> _cells = {};

  @override
  void initState() {
    super.initState();
    _seedDemo();
  }

  void _seedDemo() {
    final demo = <String, Lesson>{
      '周一-1': Lesson('语文'),
      '周一-2': Lesson('数学'),
      '周一-3': Lesson('英语'),
      '周一-4': Lesson('物理'),
      '周二-1': Lesson('数学'),
      '周二-2': Lesson('语文'),
      '周二-3': Lesson('体育', '操场'),
      '周二-4': Lesson('英语'),
      '周三-1': Lesson('化学', '实验楼'),
      '周三-2': Lesson('数学'),
      '周三-3': Lesson('语文'),
      '周四-1': Lesson('英语'),
      '周四-2': Lesson('物理'),
      '周四-3': Lesson('生物'),
      '周五-1': Lesson('语文'),
      '周五-2': Lesson('数学'),
      '周五-3': Lesson('历史'),
      '周五-4': Lesson('地理'),
    };
    _cells.addAll(demo);
  }

  int get _todayIndex {
    final w = DateTime.now().weekday;
    return (w >= 1 && w <= 5) ? w - 1 : -1;
  }

  Future<void> _edit(String day, int period) async {
    final key = '$day-$period';
    final ctrl = TextEditingController(text: _cells[key]?.subject ?? '');
    final roomCtrl = TextEditingController(text: _cells[key]?.room ?? '');
    const subjects = ['语文', '数学', '英语', '物理', '化学', '生物', '历史', '地理', '体育', '自习'];

    final ok = await showDialog<Object>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text('第 $period 节 · $day'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: '科目',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: roomCtrl,
                  decoration: const InputDecoration(
                    labelText: '教室（可选）',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in subjects)
                      ActionChip(
                        label: Text(s),
                        onPressed: () => setDlg(() => ctrl.text = s),
                      ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'clear'),
              child: const Text('清空'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );

    if (ok == 'clear') {
      setState(() => _cells.remove(key));
    } else if (ok == true) {
      final s = ctrl.text.trim();
      if (s.isEmpty) {
        setState(() => _cells.remove(key));
      } else {
        setState(() => _cells[key] = Lesson(s, roomCtrl.text.trim()));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Text('计划盒'),
            SizedBox(width: 10),
            Text('PlanBox',
                style: TextStyle(
                    fontSize: 13, color: kDim, fontWeight: FontWeight.w400)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '清空课表',
            onPressed: () => setState(_cells.clear),
            icon: const Icon(Icons.delete_outline, color: kDim),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                children: [
                  _buildHeader(),
                  const SizedBox(height: 10),
                  _buildDayRow(),
                  const SizedBox(height: 6),
                  Expanded(child: _buildGrid()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final now = DateTime.now();
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    return Row(
      children: [
        Text(
          '${now.month} 月 ${now.day} 日',
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
        ),
        const SizedBox(width: 12),
        Text(
          '星期${weekdays[now.weekday - 1]}',
          style: const TextStyle(fontSize: 14, color: kDim),
        ),
        const Spacer(),
        if (_cells.isNotEmpty)
          Text('共 ${_cells.length} 节课',
              style: const TextStyle(fontSize: 13, color: kDim)),
      ],
    );
  }

  Widget _buildDayRow() {
    return Row(
      children: [
        const SizedBox(width: 52),
        for (var i = 0; i < kDays.length; i++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: i == _todayIndex
                      ? kAcc.withValues(alpha: 0.15)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  i == _todayIndex ? '${kDays[i]} · 今天' : kDays[i],
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: i == _todayIndex
                        ? FontWeight.w700
                        : FontWeight.w500,
                    color: i == _todayIndex ? kAcc : kDim,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildGrid() {
    return Column(
      children: [
        for (var p = 1; p <= kPeriods; p++)
          Expanded(
            child: Row(
              children: [
                SizedBox(
                  width: 52,
                  child: Center(
                    child: Text(
                      '第$p节',
                      style: const TextStyle(fontSize: 11, color: kDim),
                    ),
                  ),
                ),
                for (final d in kDays)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: _cell(d, p),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _cell(String day, int period) {
    final lesson = _cells['$day-$period'];
    final highlight = kDays.indexOf(day) == _todayIndex;
    return Material(
      color: lesson == null
          ? (highlight ? kCard2.withValues(alpha: 0.55) : kCard)
          : lesson.color.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _edit(day, period),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color:
                  lesson == null ? kLine : lesson.color.withValues(alpha: 0.5),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          alignment: Alignment.center,
          child: lesson == null
              ? const SizedBox.shrink()
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      lesson.subject,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: lesson.color,
                      ),
                    ),
                    if (lesson.room.isNotEmpty)
                      Text(
                        lesson.room,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10, color: kDim),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}
