import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:zyiarah/models/driver_schedule.dart';
import 'package:zyiarah/theme/app_theme.dart';

/// جدول المهام والمناوبات للسائق (تصميم Stitch `_39`، 2026-09-16).
///
/// كان تبويبين (النشطة/السجل) مرتّبين بوقت الإنشاء. الآن: جدول أسبوعي (سبت→جمعة)
/// وشهري بعدد مهام كل يوم، مؤشرات الفترة (مجدولة/منجزة/متبقية)، ومهام اليوم
/// المختار بوقتها — والسجل ثالثاً كما كان. الاستعلامان كما كانا (النشط بفلتر
/// الحالة على الخادم + أحدث 100 في السجل) فلا فهرس جديد؛ الدمج والتقويم محليان.
class DriverTasksScreen extends StatefulWidget {
  /// للاختبارات: بثّ جاهز بدل Firestore، وهويّة ووقت مفروضان.
  final Stream<List<DriverTask>>? items;
  final String? uid;
  final DateTime? now;

  const DriverTasksScreen({super.key, this.items, this.uid, this.now});

  @override
  State<DriverTasksScreen> createState() => _DriverTasksScreenState();
}

enum _View { week, month, history }

class _DriverTasksScreenState extends State<DriverTasksScreen> {
  late final String? _driverId;
  late final DateTime _now;
  late DateTime _selected;
  _View _view = _View.week;

  @override
  void initState() {
    super.initState();
    _driverId = widget.items != null
        ? widget.uid
        : FirebaseAuth.instance.currentUser?.uid;
    _now = widget.now ?? DateTime.now();
    _selected = DriverSchedule.dayKey(_now);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF1F5F9),
        appBar: AppBar(
          title: Text('جدول المهام والمناوبات',
              style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
          backgroundColor: ZyiarahTheme.brand,
          foregroundColor: Colors.white,
          elevation: 0,
          automaticallyImplyLeading: false,
        ),
        body: _driverId == null
            ? const Center(child: Text('يرجى تسجيل الدخول'))
            : (widget.items != null ? _injected() : _firestore(_driverId!)),
      ),
    );
  }

  Widget _injected() {
    return StreamBuilder<List<DriverTask>>(
      stream: widget.items,
      builder: (context, s) {
        if (s.connectionState == ConnectionState.waiting && !s.hasData) {
          return _loading();
        }
        if (s.hasError) return _error();
        return _content(s.data ?? const [], historyCapped: false);
      },
    );
  }

  Widget _firestore(String driverId) {
    // (تدقيق السائق) استعلامان محدودان بدل بثّ كل طلبات السائق مدى الحياة:
    // النشطة بفلتر حالات خادمي (يخدمه فهرس driver_id+status القائم)، والسجل
    // بأحدث 100 طلب (يخدمه فهرس driver_id+created_at القائم) ثم تصفية
    // حالات السجل محلياً — إضافة whereIn فوق orderBy كانت ستتطلب فهرساً جديداً.
    final active = FirebaseFirestore.instance
        .collection('orders')
        .where('driver_id', isEqualTo: driverId)
        .where('status', whereIn: DriverSchedule.activeStatuses)
        .snapshots();
    final history = FirebaseFirestore.instance
        .collection('orders')
        .where('driver_id', isEqualTo: driverId)
        .orderBy('created_at', descending: true)
        .limit(100)
        .snapshots();

    List<DriverTask> parse(QuerySnapshot<Map<String, dynamic>> q) => [
          for (final d in q.docs) DriverTask.fromMap(d.id, d.data(), fallback: _now),
        ];

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: active,
      builder: (context, a) {
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: history,
          builder: (context, h) {
            if ((a.connectionState == ConnectionState.waiting && !a.hasData) ||
                (h.connectionState == ConnectionState.waiting && !h.hasData)) {
              return _loading();
            }
            if (a.hasError || h.hasError) return _error();
            final activeTasks = a.hasData ? parse(a.data!) : const <DriverTask>[];
            final historyTasks = h.hasData
                ? parse(h.data!)
                    .where((t) => DriverSchedule.historyStatuses.contains(t.status))
                    .toList()
                : const <DriverTask>[];
            return _content(
              DriverSchedule.merge(activeTasks, historyTasks),
              historyCapped: (h.data?.docs.length ?? 0) >= 100,
            );
          },
        );
      },
    );
  }

  Widget _loading() =>
      const Center(child: CircularProgressIndicator(color: ZyiarahTheme.brand));

  Widget _error() {
    // لا «قائمة فارغة» كاذبة عند الفشل — لافتة خطأ + إعادة المحاولة
    // (setState يعيد بناء التيار فيُعاد الاشتراك).
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(children: [
                const Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('تعذّر تحميل المهام — تحقّق من اتصالك',
                      style: GoogleFonts.tajawal(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.red.shade800)),
                ),
              ]),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () => setState(() {}),
              icon: const Icon(Icons.refresh, size: 18),
              label: Text('إعادة المحاولة',
                  style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  // ───────────────────────── المحتوى ─────────────────────────

  Widget _content(List<DriverTask> all, {required bool historyCapped}) {
    final byDay = DriverSchedule.bucket(all);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: SegmentedButton<_View>(
          segments: const [
            ButtonSegment(
                value: _View.week,
                label: Text('الجدول الأسبوعي'),
                icon: Icon(Icons.calendar_view_week_rounded, size: 16)),
            ButtonSegment(
                value: _View.month,
                label: Text('الجدول الشهري'),
                icon: Icon(Icons.calendar_month_rounded, size: 16)),
            ButtonSegment(
                value: _View.history,
                label: Text('السجل'),
                icon: Icon(Icons.history_rounded, size: 16)),
          ],
          selected: {_view},
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(
            textStyle: GoogleFonts.tajawal(fontSize: 11.5, fontWeight: FontWeight.bold),
            selectedBackgroundColor: ZyiarahTheme.brand,
            selectedForegroundColor: Colors.white,
          ),
          onSelectionChanged: (s) => setState(() => _view = s.first),
        ),
      ),
      Expanded(
        child: switch (_view) {
          _View.week => _weekView(all, byDay),
          _View.month => _monthView(all, byDay),
          _View.history => _historyView(all, historyCapped),
        },
      ),
    ]);
  }

  Widget _weekView(List<DriverTask> all, Map<DateTime, List<DriverTask>> byDay) {
    final days = DriverSchedule.weekDays(_selected);
    final inWeek = DriverSchedule.inRange(all, days.first, days.last);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        _kpiRow(DriverSchedule.kpis(inWeek)),
        const SizedBox(height: 12),
        _navRow(
          label: DriverSchedule.weekLabel(_selected),
          onPrev: () => setState(() =>
              _selected = _selected.subtract(const Duration(days: 7))),
          onNext: () =>
              setState(() => _selected = _selected.add(const Duration(days: 7))),
        ),
        const SizedBox(height: 8),
        _weekStrip(days, byDay),
        const SizedBox(height: 16),
        ..._dayList(byDay),
      ],
    );
  }

  Widget _monthView(List<DriverTask> all, Map<DateTime, List<DriverTask>> byDay) {
    final start = DriverSchedule.monthStart(_selected);
    final end = DriverSchedule.monthEnd(_selected);
    final inMonth = DriverSchedule.inRange(all, start, end);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        _kpiRow(DriverSchedule.kpis(inMonth)),
        const SizedBox(height: 12),
        _navRow(
          label: '${DriverSchedule.monthName(_selected)} ${_selected.year}',
          onPrev: () => setState(() =>
              _selected = DateTime(_selected.year, _selected.month - 1, 1)),
          onNext: () => setState(() =>
              _selected = DateTime(_selected.year, _selected.month + 1, 1)),
        ),
        const SizedBox(height: 8),
        _monthGrid(byDay),
        const SizedBox(height: 16),
        ..._dayList(byDay),
      ],
    );
  }

  Widget _historyView(List<DriverTask> all, bool capped) {
    final history = all
        .where((t) => DriverSchedule.historyStatuses.contains(t.status))
        .toList()
      ..sort((a, b) => b.when.compareTo(a.when));
    if (history.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.history, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text('لا يوجد سجل مهام بعد',
              style: GoogleFonts.tajawal(color: Colors.grey, fontSize: 15)),
        ]),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ملاحظة الحدّ تظهر فقط عند بلوغ سقف الاستعلام (سجلّ أقدم مقصوص فعلاً).
        if (capped)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text('يعرض أحدث 100 طلب',
                textAlign: TextAlign.center,
                style: GoogleFonts.tajawal(fontSize: 11, color: Colors.grey)),
          ),
        for (final t in history) _taskCard(t, showDate: true),
      ],
    );
  }

  // ───────────────────────── العناصر ─────────────────────────

  Widget _kpiRow(({int scheduled, int done, int remaining}) k) {
    Widget tile(String label, int value, String sub, Color color) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(children: [
            Text(label,
                style: GoogleFonts.tajawal(
                    fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.white)),
            Text('$value',
                style: GoogleFonts.tajawal(
                    fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white)),
            Text(sub,
                style: GoogleFonts.tajawal(
                    fontSize: 10.5, color: Colors.white.withValues(alpha: 0.9))),
          ]),
        ),
      );
    }

    return Row(children: [
      tile('المجدولة', k.scheduled, 'زيارة', ZyiarahTheme.brand),
      const SizedBox(width: 8),
      tile('المنجزة', k.done, 'مكتملة ✓', const Color(0xFF0F766E)),
      const SizedBox(width: 8),
      tile('المتبقية', k.remaining, 'مهمة ⏳', const Color(0xFFB45309)),
    ]);
  }

  Widget _navRow(
      {required String label, required VoidCallback onPrev, required VoidCallback onNext}) {
    return Row(children: [
      IconButton(
          tooltip: 'السابق',
          onPressed: onPrev,
          icon: const Icon(Icons.chevron_right_rounded, color: ZyiarahTheme.brand)),
      Expanded(
        child: Text(label,
            textAlign: TextAlign.center,
            style: GoogleFonts.tajawal(fontSize: 14, fontWeight: FontWeight.bold)),
      ),
      IconButton(
          tooltip: 'التالي',
          onPressed: onNext,
          icon: const Icon(Icons.chevron_left_rounded, color: ZyiarahTheme.brand)),
    ]);
  }

  Widget _weekStrip(List<DateTime> days, Map<DateTime, List<DriverTask>> byDay) {
    return Row(children: [
      for (final d in days) ...[
        Expanded(child: _dayCell(d, byDay[d] ?? const [], compact: false)),
        if (d != days.last) const SizedBox(width: 4),
      ],
    ]);
  }

  Widget _dayCell(DateTime d, List<DriverTask> tasks, {required bool compact}) {
    final isToday = DriverSchedule.sameDay(d, _now);
    final isSelected = DriverSchedule.sameDay(d, _selected);
    final count = tasks.where((t) => !t.isCancelled).length;
    final allDone = count > 0 && tasks.every((t) => t.isCompleted || t.isCancelled);
    final inMonth = compact ? d.month == _selected.month : true;

    final Color bg = isSelected
        ? ZyiarahTheme.brand.withValues(alpha: 0.10)
        : (count == 0 ? const Color(0xFFF8FAFC) : Colors.white);
    final Color border = isSelected
        ? ZyiarahTheme.brand
        : (isToday ? const Color(0xFFB45309) : Colors.grey.shade200);

    return GestureDetector(
      onTap: () => setState(() => _selected = d),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: compact ? 6 : 8, horizontal: 2),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border, width: isSelected || isToday ? 1.5 : 1),
        ),
        child: Column(children: [
          if (!compact)
            Text(isToday ? 'اليوم' : DriverSchedule.dayName(d),
                style: GoogleFonts.tajawal(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: isToday ? const Color(0xFFB45309) : ZyiarahTheme.inkMuted)),
          Text('${d.day}',
              style: GoogleFonts.tajawal(
                  fontSize: compact ? 13 : 18,
                  fontWeight: FontWeight.w800,
                  color: inMonth ? ZyiarahTheme.ink : ZyiarahTheme.inkFaint)),
          if (count == 0)
            (compact
                ? const SizedBox(height: 14)
                : Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.bedtime_outlined, size: 11, color: Colors.grey),
                    const SizedBox(width: 2),
                    Text('راحة',
                        style: GoogleFonts.tajawal(fontSize: 9.5, color: Colors.grey)),
                  ]))
          else
            Container(
              margin: const EdgeInsets.only(top: 2),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: allDone
                    ? const Color(0xFF0F766E).withValues(alpha: 0.12)
                    : ZyiarahTheme.brand.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (allDone)
                  const Icon(Icons.done_all_rounded, size: 11, color: Color(0xFF0F766E)),
                if (allDone) const SizedBox(width: 2),
                Text(compact ? '$count' : '$count مهام',
                    style: GoogleFonts.tajawal(
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold,
                        color: allDone ? const Color(0xFF0F766E) : ZyiarahTheme.brand)),
              ]),
            ),
        ]),
      ),
    );
  }

  Widget _monthGrid(Map<DateTime, List<DriverTask>> byDay) {
    final grid = DriverSchedule.monthGrid(_selected);
    return Column(children: [
      Row(children: [
        for (final name in DriverSchedule.dayNames)
          Expanded(
            child: Text(name,
                textAlign: TextAlign.center,
                style: GoogleFonts.tajawal(
                    fontSize: 9.5,
                    fontWeight: FontWeight.bold,
                    color: ZyiarahTheme.inkMuted)),
          ),
      ]),
      const SizedBox(height: 4),
      for (var i = 0; i < grid.length; i += 7)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(children: [
            for (var j = i; j < i + 7; j++) ...[
              Expanded(
                  child: _dayCell(grid[j], byDay[grid[j]] ?? const [], compact: true)),
              if (j != i + 6) const SizedBox(width: 3),
            ],
          ]),
        ),
    ]);
  }

  List<Widget> _dayList(Map<DateTime, List<DriverTask>> byDay) {
    final tasks = byDay[_selected] ?? const <DriverTask>[];
    final active = tasks.where((t) => !t.isCancelled).length;
    final title = DriverSchedule.sameDay(_selected, _now)
        ? 'مهام اليوم (${DriverSchedule.dateLabel(_selected)})'
        : 'مهام ${DriverSchedule.dateLabel(_selected)}';
    return [
      Row(children: [
        Expanded(
          child: Text(title,
              style: GoogleFonts.tajawal(fontSize: 14, fontWeight: FontWeight.bold)),
        ),
        Text(active == 0 ? 'لا مهام' : '$active زيارات ميدانية مسندة',
            style: GoogleFonts.tajawal(fontSize: 11, color: ZyiarahTheme.inkMuted)),
      ]),
      const SizedBox(height: 10),
      if (tasks.isEmpty)
        Container(
          padding: const EdgeInsets.symmetric(vertical: 28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(children: [
            const Icon(Icons.bedtime_outlined, size: 36, color: Colors.grey),
            const SizedBox(height: 8),
            Text('لا مهام في هذا اليوم — راحة',
                style: GoogleFonts.tajawal(color: Colors.grey, fontSize: 14)),
          ]),
        )
      else
        for (final t in tasks) _taskCard(t, showDate: false),
    ];
  }

  Widget _taskCard(DriverTask t, {required bool showDate}) {
    Color statusColor;
    String statusLabel;
    IconData statusIcon;

    switch (t.status) {
      case 'completed':
        statusColor = Colors.green;
        statusLabel = 'مكتملة بنجاح ✓';
        statusIcon = Icons.check_circle_outline;
        break;
      case 'cancelled':
        statusColor = Colors.red;
        statusLabel = 'ملغاة';
        statusIcon = Icons.cancel_outlined;
        break;
      case 'in_progress':
        statusColor = Colors.blue;
        statusLabel = 'جارية الآن ⚡';
        statusIcon = Icons.timer_outlined;
        break;
      case 'scheduled':
        statusColor = ZyiarahTheme.brand;
        statusLabel = 'قادمة ⏳';
        statusIcon = Icons.event_available_outlined;
        break;
      case 'assigned':
        // إسناد يدوي من الأدمن — بانتظار الجدولة (لا يستطيع السائق تقديمها بنفسه)
        statusColor = Colors.orange;
        statusLabel = 'مُسنَدة — بانتظار الجدولة';
        statusIcon = Icons.assignment_ind_outlined;
        break;
      case 'on_the_way':
      case 'accepted':
        statusColor = Colors.orange;
        statusLabel = t.status == 'on_the_way' ? 'في الطريق' : 'مقبولة';
        statusIcon = Icons.directions_car_outlined;
        break;
      default:
        statusColor = ZyiarahTheme.brand;
        statusLabel = 'معلقة';
        statusIcon = Icons.hourglass_empty;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: statusColor.withValues(alpha: 0.15)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: ZyiarahTheme.brand.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                showDate
                    ? '${t.when.year}/${t.when.month.toString().padLeft(2, '0')}/${t.when.day.toString().padLeft(2, '0')} · ${t.timeLabel}'
                    : t.timeLabel,
                style: GoogleFonts.tajawal(
                    fontSize: 11, fontWeight: FontWeight.bold, color: ZyiarahTheme.brand),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(statusIcon, size: 12, color: statusColor),
                const SizedBox(width: 4),
                Text(statusLabel,
                    style: GoogleFonts.tajawal(
                        color: statusColor, fontWeight: FontWeight.bold, fontSize: 10.5)),
              ]),
            ),
            const Spacer(),
            Text('#${t.code}',
                textDirection: TextDirection.ltr,
                style: GoogleFonts.tajawal(color: Colors.grey[400], fontSize: 11)),
          ]),
          const SizedBox(height: 8),
          Text(t.serviceName,
              style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 4),
          Row(children: [
            Icon(Icons.person_outline, size: 13, color: Colors.grey[500]),
            const SizedBox(width: 4),
            Text('العميل: ${t.clientName}',
                style: GoogleFonts.tajawal(color: Colors.grey[600], fontSize: 12)),
          ]),
          if (t.zoneName.isNotEmpty)
            Row(children: [
              Icon(Icons.location_on_outlined, size: 13, color: Colors.grey[500]),
              const SizedBox(width: 4),
              Text(t.zoneName,
                  style: GoogleFonts.tajawal(color: Colors.grey[600], fontSize: 12)),
            ]),
        ],
      ),
    );
  }
}
