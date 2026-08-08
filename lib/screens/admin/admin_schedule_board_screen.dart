import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' as intl;
import 'package:zyiarah/screens/admin/admin_order_details_screen.dart';

/// المدى الزمني المعروض. «ماذا أمامنا» — كلها تبدأ من **اليوم** لا من الماضي.
enum BoardRange { day, week, month }

extension _BoardRangeX on BoardRange {
  String get label => switch (this) {
        BoardRange.day => 'اليوم',
        BoardRange.week => 'الأسبوع',
        BoardRange.month => 'الشهر',
      };

  /// عدد الأيام المعروضة ابتداءً من اليوم — الأسبوع 7 والشهر 30 يوماً متدحرجة
  /// (لا «الشهر الميلادي») كي يبقى الأفق ثابتاً مهما كان تاريخ اليوم.
  int get days => switch (this) {
        BoardRange.day => 1,
        BoardRange.week => 7,
        BoardRange.month => 30,
      };
}

/// جدول متابعة العمليات — **استشرافي** لا تقرير ماضٍ: يعرض الاشتراكات والخدمات
/// والطلبات القادمة مجمَّعةً يومياً، مع إبراز ما يحتاج تدخّل الإدارة (بلا سائق).
/// لوحة الإحصائيات تجيب «كم ربحنا»؛ هذه تجيب «ماذا أمامنا وماذا ينقصه».
class AdminScheduleBoardScreen extends StatefulWidget {
  const AdminScheduleBoardScreen({super.key});

  @override
  State<AdminScheduleBoardScreen> createState() =>
      _AdminScheduleBoardScreenState();
}

class _AdminScheduleBoardScreenState extends State<AdminScheduleBoardScreen> {
  static const Color _brand = Color(0xFF660033);

  /// حدّ الجلب — حارس ضد استعلام غير محدود يستهلك القراءات ويُبطئ الشاشة.
  /// أكبر بكثير من حمل شهرٍ واقعي، ونُنبّه صراحةً إن بلغناه بدل الصمت.
  static const int _fetchLimit = 800;

  BoardRange _range = BoardRange.week;

  /// الحالات المنتهية لا تُعدّ ضمن «ما أمامنا».
  static const _deadStatuses = {'cancelled', 'rejected', 'completed'};

  DateTime get _start {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  DateTime get _end => _start.add(Duration(days: _range.days));

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          title: Text('جدول المتابعة',
              style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
          backgroundColor: _brand,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: Column(
          children: [
            _rangeSelector(),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _rangeSelector() => Container(
        color: _brand,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        child: Row(
          children: [
            for (final r in BoardRange.values)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: GestureDetector(
                    onTap: () => setState(() => _range = r),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _range == r
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(r.label,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.tajawal(
                              fontWeight: FontWeight.bold,
                              color: _range == r ? _brand : Colors.white)),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );

  Widget _body() {
    // نطاق على حقل واحد + ترتيب على الحقل نفسه ⇒ لا يحتاج فهرساً مركّباً.
    // التصفية بالحالة محلية عمداً: whereNotIn معه ترتيب يفرض فهرساً إضافياً.
    final q = FirebaseFirestore.instance
        .collection('orders')
        .where('service_date',
            isGreaterThanOrEqualTo: Timestamp.fromDate(_start))
        .where('service_date', isLessThan: Timestamp.fromDate(_end))
        .orderBy('service_date')
        .limit(_fetchLimit);

    return StreamBuilder<QuerySnapshot>(
      stream: q.snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          // لا فشل صامت: بلا هذا تظهر الشاشة فارغة فيُفهَم «لا مواعيد» خطأً.
          return _message(
              Icons.error_outline_rounded,
              'تعذّر تحميل الجدول',
              '${snap.error}',
              color: Colors.red);
        }
        if (!snap.hasData) {
          return const Center(
              child: CircularProgressIndicator(color: _brand));
        }

        final docs = snap.data!.docs.where((d) {
          final m = d.data() as Map<String, dynamic>;
          return !_deadStatuses.contains('${m['status'] ?? ''}');
        }).toList();

        if (docs.isEmpty) {
          return _message(Icons.event_available_rounded, 'لا مواعيد',
              'لا شيء مجدول خلال ${_range.label == 'اليوم' ? 'اليوم' : _range.label}.');
        }

        // تجميع حسب اليوم — LinkedHashMap يحفظ ترتيب الاستعلام (الأقدم أولاً).
        final byDay = <String, List<QueryDocumentSnapshot>>{};
        for (final d in docs) {
          final dt = ((d.data() as Map)['service_date'] as Timestamp?)?.toDate();
          if (dt == null) continue;
          byDay
              .putIfAbsent(intl.DateFormat('yyyy-MM-dd').format(dt), () => [])
              .add(d);
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _kpiStrip(docs),
            const SizedBox(height: 14),
            _mixStrip(docs),
            const SizedBox(height: 18),
            if (snap.data!.docs.length >= _fetchLimit)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _banner(
                    'عُرض أول $_fetchLimit موعد فقط — ضيّق المدى لرؤية البقية.',
                    const Color(0xFFFFFBEB),
                    const Color(0xFF92400E)),
              ),
            for (final entry in byDay.entries) _dayCard(entry.key, entry.value),
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }

  /// المؤشرات التي تُصرّف العمل: أهمّها **بلا سائق** — وحده القابل للتصرّف الآن.
  Widget _kpiStrip(List<QueryDocumentSnapshot> docs) {
    int unassigned = 0, unpaid = 0;
    double revenue = 0;
    for (final d in docs) {
      final m = d.data() as Map<String, dynamic>;
      if (_driverIdOf(m) == null) unassigned++;
      if (m['is_paid'] != true) unpaid++;
      revenue += (m['amount'] as num?)?.toDouble() ?? 0;
    }

    // الأرقام ملخّص فوق الطلبات لا بديل عنها (تصحيح المالك): ثلاثة مؤشرات
    // تشغيلية فقط، والإيراد سطر ثانوي أسفلها — الطلبات نفسها هي المحتوى.
    return Column(
      children: [
        Row(
          children: [
            Expanded(
                child: _kpi('الطلبات', '${docs.length}',
                    Icons.event_note_rounded, const Color(0xFF334155))),
            const SizedBox(width: 10),
            Expanded(
                child: _kpi(
                    'بلا سائق',
                    '$unassigned',
                    Icons.person_off_outlined,
                    unassigned > 0
                        ? const Color(0xFFDC2626)
                        : const Color(0xFF059669))),
            const SizedBox(width: 10),
            Expanded(
                child: _kpi(
                    'غير مدفوعة',
                    '$unpaid',
                    Icons.pending_actions_rounded,
                    unpaid > 0
                        ? const Color(0xFFD97706)
                        : const Color(0xFF059669))),
          ],
        ),
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Text(
              'الإيراد المتوقع: ${revenue.toStringAsFixed(2)} ر.س',
              style: GoogleFonts.tajawal(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF64748B))),
        ),
      ],
    );
  }

  /// تركيبة الحمل: اشتراكات مقابل طلبات مدفوعة — الاشتراك بلا إيراد جديد لكنه
  /// يستهلك سائقاً، فخلطهما في رقم واحد يخفي حقيقة الضغط التشغيلي.
  Widget _mixStrip(List<QueryDocumentSnapshot> docs) {
    int subs = 0, regular = 0;
    for (final d in docs) {
      final m = d.data() as Map<String, dynamic>;
      if (m['contract_id'] != null || m['payment_method'] == 'subscription') {
        subs++;
      } else {
        regular++;
      }
    }
    return Row(
      children: [
        Expanded(
            child: _pill('زيارات اشتراكات', '$subs', const Color(0xFF7C3AED))),
        const SizedBox(width: 10),
        Expanded(
            child: _pill('طلبات وخدمات', '$regular', const Color(0xFF0E7490))),
      ],
    );
  }

  Widget _dayCard(String dayKey, List<QueryDocumentSnapshot> items) {
    final day = DateTime.parse(dayKey);
    final isToday = _isSameDay(day, DateTime.now());
    final unassigned = items
        .where((d) => _driverIdOf(d.data() as Map<String, dynamic>) == null)
        .length;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: isToday ? _brand.withValues(alpha: 0.4) : const Color(0xFFE2E8F0)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          // مفتوحة دائماً: الغرض رؤية **الطلبات نفسها** لا عدّها. الطيّ الافتراضي
          // كان يُظهر رقماً فقط فيبدو الجدول إحصاءً آخر (تصحيح المالك).
          initiallyExpanded: true,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          title: Row(
            children: [
              Expanded(
                child: Text(
                    '${_weekdayAr(day)} ${intl.DateFormat('d MMMM', 'ar').format(day)}'
                    '${isToday ? ' • اليوم' : ''}',
                    style: GoogleFonts.tajawal(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: isToday ? _brand : const Color(0xFF1E293B))),
              ),
              if (unassigned > 0) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('$unassigned بلا سائق',
                      style: GoogleFonts.tajawal(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFFDC2626))),
                ),
                const SizedBox(width: 6),
              ],
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('${items.length}',
                    style: GoogleFonts.tajawal(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF334155))),
              ),
            ],
          ),
          children: [for (final d in items) _appointmentRow(d)],
        ),
      ),
    );
  }

  Widget _appointmentRow(QueryDocumentSnapshot doc) {
    final m = doc.data() as Map<String, dynamic>;
    final dt = (m['service_date'] as Timestamp?)?.toDate();
    final driverId = _driverIdOf(m);
    final isSub =
        m['contract_id'] != null || m['payment_method'] == 'subscription';

    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => AdminOrderDetailsScreen(orderId: doc.id)),
      ),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        child: Row(
          children: [
            SizedBox(
              width: 52,
              child: Text(dt == null ? '—' : intl.DateFormat('h:mm a').format(dt),
                  style: GoogleFonts.tajawal(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF475569))),
            ),
            Container(
              width: 4,
              height: 34,
              decoration: BoxDecoration(
                color: isSub ? const Color(0xFF7C3AED) : const Color(0xFF0E7490),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // رقم الطلب أولاً: هو ما تُعرَّف به الطلبات في كل الشاشات
                      // وفي الحديث بين الإدارة والسائق.
                      Text('#${m['code'] ?? doc.id.substring(0, 6)}',
                          style: GoogleFonts.tajawal(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFF94A3B8))),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                            '${m['service_name'] ?? m['service_type'] ?? 'خدمة'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.tajawal(
                                fontSize: 13, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                      '${m['client_name'] ?? '—'} • ${m['zone_name'] ?? '—'}'
                      '${m['client_phone'] != null && '${m['client_phone']}'.isNotEmpty ? ' • ${m['client_phone']}' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.tajawal(
                          fontSize: 11, color: const Color(0xFF64748B))),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      _tag(_statusAr('${m['status'] ?? ''}'),
                          const Color(0xFF334155)),
                      if (driverId == null)
                        _tag('بلا سائق', const Color(0xFFDC2626), strong: true)
                      else
                        _tag('${m['driver_name'] ?? 'مُسنَد'}',
                            const Color(0xFF059669)),
                      if (m['is_paid'] != true && !isSub)
                        _tag('غير مدفوع', const Color(0xFFD97706)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                    isSub
                        ? 'اشتراك'
                        : '${((m['amount'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)} ر.س',
                    style: GoogleFonts.tajawal(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: isSub ? const Color(0xFF7C3AED) : _brand)),
                const Icon(Icons.chevron_left_rounded,
                    size: 18, color: Color(0xFF94A3B8)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── مساعدات ──

  /// الطلبات القديمة تحمل driver_id والجديدة قد تحمل driverId — نقبل الاثنين،
  /// والسلسلة الفارغة تُعامَل «بلا سائق» (كانت تُحسب مُسنَدة فتختفي من التنبيه).
  static String? _driverIdOf(Map<String, dynamic> m) {
    final v = m['driver_id'] ?? m['driverId'];
    final s = v?.toString().trim();
    return (s == null || s.isEmpty) ? null : s;
  }

  /// الحالة تُخزَّن إنجليزية في المستند — تُعرض عربية كما في بقية شاشات الإدارة.
  static String _statusAr(String s) => switch (s) {
        'scheduled' => 'مجدول',
        'assigned' => 'مُسند',
        'accepted' => 'مقبول',
        'on_the_way' => 'في الطريق',
        'in_progress' => 'قيد التنفيذ',
        'pending' => 'قيد الانتظار',
        'under_review' => 'قيد المراجعة',
        'awaiting_payment' => 'بانتظار الدفع',
        '' => 'بلا حالة',
        _ => s,
      };

  Widget _tag(String text, Color color, {bool strong = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: strong ? 0.14 : 0.08),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(text,
            style: GoogleFonts.tajawal(
                fontSize: 10,
                fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
                color: color)),
      );

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _weekdayAr(DateTime d) => const [
        'الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس',
        'الجمعة', 'السبت', 'الأحد',
      ][d.weekday - 1];

  Widget _kpi(String label, String value, IconData icon, Color color) =>
      Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(height: 6),
            Text(value,
                style: GoogleFonts.tajawal(
                    fontSize: 18, fontWeight: FontWeight.w900, color: color)),
            const SizedBox(height: 2),
            Text(label,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: GoogleFonts.tajawal(
                    fontSize: 10, color: const Color(0xFF64748B))),
          ],
        ),
      );

  Widget _pill(String label, String value, Color color) => Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(label,
                  style: GoogleFonts.tajawal(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF334155))),
            ),
            Text(value,
                style: GoogleFonts.tajawal(
                    fontSize: 15, fontWeight: FontWeight.w900, color: color)),
          ],
        ),
      );

  Widget _banner(String text, Color bg, Color fg) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: bg, borderRadius: BorderRadius.circular(14)),
        child: Text(text,
            style: GoogleFonts.tajawal(
                fontSize: 12, color: fg, fontWeight: FontWeight.w600)),
      );

  Widget _message(IconData icon, String title, String detail,
          {Color color = const Color(0xFF94A3B8)}) =>
      Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 56, color: color),
              const SizedBox(height: 14),
              Text(title,
                  style: GoogleFonts.tajawal(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF334155))),
              const SizedBox(height: 6),
              Text(detail,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.tajawal(
                      fontSize: 12.5, color: const Color(0xFF64748B))),
            ],
          ),
        ),
      );
}
