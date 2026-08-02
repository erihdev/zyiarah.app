import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' as intl;
import 'package:zyiarah/utils/time_format.dart';

/// محرّر جدول فتح المنطقة — يُدمج في حوار «إضافة/تعديل منطقة».
///
/// يبني `schedule` الذي يخزَّن على مستند المنطقة ويحسبه الخادم (getHourlyAvailability)
/// مرجعيّاً. الشكل:
///   { enabled, weekly:{"0":{open,start,end}..}, blackouts:[...], windows:[{from,to,start,end}] }
///
/// **الساعات تُعرَض 12 ساعة وتُخزَّن 24** — نفس قاعدة time_format: التخزين 24 لأن
/// الخادم يحلّله رقميّاً.
class ZoneScheduleEditor extends StatefulWidget {
  final Map<String, dynamic>? initial;
  final ValueChanged<Map<String, dynamic>> onChanged;

  const ZoneScheduleEditor({super.key, required this.onChanged, this.initial});

  @override
  State<ZoneScheduleEditor> createState() => _ZoneScheduleEditorState();
}

class _ZoneScheduleEditorState extends State<ZoneScheduleEditor> {
  static const Color _brand = Color(0xFF660033);
  static const _dayNames = ['الأحد', 'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت'];

  bool _enabled = false;
  // weekday(0-6) -> {open, start, end}
  final Map<int, _DayHours> _weekly = {};
  final List<String> _blackouts = [];
  final List<_Window> _windows = [];

  @override
  void initState() {
    super.initState();
    final s = widget.initial;
    _enabled = s?['enabled'] == true;
    final weekly = (s?['weekly'] as Map?) ?? {};
    for (int d = 0; d < 7; d++) {
      final w = weekly['$d'] as Map?;
      _weekly[d] = _DayHours(
        open: w?['open'] == true,
        start: (w?['start'] as num?)?.toInt() ?? 8,
        end: (w?['end'] as num?)?.toInt() ?? 22,
        // (تحكم المالك ساعة-بساعة) ساعات مقفلة داخل النطاق.
        closed: ((w?['closed'] as List?) ?? [])
            .map((h) => (h as num).toInt())
            .toSet(),
      );
    }
    for (final b in (s?['blackouts'] as List?) ?? []) {
      _blackouts.add(b.toString());
    }
    for (final w in (s?['windows'] as List?) ?? []) {
      if (w is Map) {
        _windows.add(_Window(
          from: w['from']?.toString() ?? '',
          to: w['to']?.toString() ?? '',
          start: (w['start'] as num?)?.toInt() ?? 9,
          end: (w['end'] as num?)?.toInt() ?? 13,
        ));
      }
    }
  }

  void _emit() {
    widget.onChanged({
      'enabled': _enabled,
      'weekly': {
        for (final e in _weekly.entries)
          '${e.key}': {
            'open': e.value.open,
            'start': e.value.start,
            'end': e.value.end,
            // تُحفظ فقط الساعات الواقعة داخل النطاق الحالي — تغيير النطاق
            // لا يُبقي أشباح ساعات مقفلة خارج حدوده.
            'closed': (e.value.closed
                    .where((h) => h >= e.value.start && h < e.value.end)
                    .toList()
                  ..sort()),
          },
      },
      'blackouts': List<String>.from(_blackouts),
      'windows': _windows
          .where((w) => w.from.isNotEmpty && w.to.isNotEmpty)
          .map((w) => {'from': w.from, 'to': w.to, 'start': w.start, 'end': w.end})
          .toList(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 30),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _enabled,
          activeThumbColor: _brand,
          title: Text('جدول فتح مخصّص لهذه المنطقة',
              style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 13)),
          subtitle: Text(
              _enabled
                  ? 'العميلة لا تحجز إلا في الأيام والساعات المحددة أدناه.'
                  : 'مغلق = المنطقة مفتوحة كل يوم من 8ص إلى 10م (الافتراضي).',
              style: GoogleFonts.tajawal(fontSize: 11, color: Colors.grey)),
          onChanged: (v) => setState(() {
            _enabled = v;
            _emit();
          }),
        ),
        if (_enabled) ...[
          _sectionLabel('أيام العمل الأسبوعية'),
          Text('اضغط على أي ساعة أسفل اليوم لقفلها (تحمرّ) أو فتحها — المقفلة لا تُحجز.',
              style: GoogleFonts.tajawal(fontSize: 10, color: Colors.grey)),
          const SizedBox(height: 4),
          ...List.generate(7, _weeklyRow),
          const SizedBox(height: 12),
          _sectionLabel('فتح استثنائي بتواريخ محددة (يتجاوز الأسبوعي)'),
          Text('مثال: فتح المنطقة يومي 20 و21 فقط بساعات خاصة.',
              style: GoogleFonts.tajawal(fontSize: 10, color: Colors.grey)),
          const SizedBox(height: 6),
          ..._windows.asMap().entries.map((e) => _windowRow(e.key, e.value)),
          _addButton('إضافة فترة فتح', () {
            setState(() {
              _windows.add(_Window(from: '', to: '', start: 9, end: 13));
              _emit();
            });
          }),
          const SizedBox(height: 12),
          _sectionLabel('أيام إغلاق استثنائية (إجازات)'),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ..._blackouts.map((d) => Chip(
                    label: Text(d, style: GoogleFonts.tajawal(fontSize: 11)),
                    onDeleted: () => setState(() {
                      _blackouts.remove(d);
                      _emit();
                    }),
                    backgroundColor: const Color(0xFFFEF2F2),
                  )),
              ActionChip(
                avatar: const Icon(Icons.add, size: 16, color: _brand),
                label: Text('إضافة يوم إغلاق', style: GoogleFonts.tajawal(fontSize: 11)),
                onPressed: _addBlackout,
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _sectionLabel(String t) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 6),
        child: Text(t,
            style: GoogleFonts.tajawal(
                fontWeight: FontWeight.bold, fontSize: 12, color: _brand)),
      );

  Widget _weeklyRow(int day) {
    final d = _weekly[day]!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 74,
                child:
                    Text(_dayNames[day], style: GoogleFonts.tajawal(fontSize: 12)),
              ),
              Switch(
                value: d.open,
                activeThumbColor: const Color(0xFF059669),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: (v) => setState(() {
                  d.open = v;
                  _emit();
                }),
              ),
              if (d.open) ...[
                Expanded(child: _hourDropdown(d.start, (v) => setState(() {
                      d.start = v;
                      if (d.end <= v) d.end = (v + 1).clamp(1, 23);
                      _emit();
                    }))),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Text('→', style: TextStyle(color: Color(0xFF94A3B8))),
                ),
                Expanded(child: _hourDropdown(d.end, (v) => setState(() {
                      d.end = v;
                      if (d.start >= v) d.start = (v - 1).clamp(0, 22);
                      _emit();
                    }))),
              ] else
                Expanded(
                  child: Text('مغلق',
                      style: GoogleFonts.tajawal(fontSize: 11, color: Colors.grey)),
                ),
            ],
          ),
          // (طلب المالك) تحكم ساعة-بساعة داخل النطاق: نقرة تقفل الساعة (تحمرّ)
          // ونقرة تفتحها — المقفلة تُعامل كممتلئة فلا يحجزها أحد.
          if (d.open)
            Padding(
              padding: const EdgeInsets.only(right: 74, bottom: 6),
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (int h = d.start; h < d.end; h++)
                    GestureDetector(
                      onTap: () => setState(() {
                        if (!d.closed.remove(h)) d.closed.add(h);
                        _emit();
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: d.closed.contains(h)
                              ? const Color(0xFFFEE2E2)
                              : const Color(0xFFF0FDF4),
                          borderRadius: BorderRadius.circular(7),
                          border: Border.all(
                              color: d.closed.contains(h)
                                  ? const Color(0xFFFCA5A5)
                                  : const Color(0xFFBBF7D0)),
                        ),
                        child: Text(
                          formatHour12(h),
                          style: GoogleFonts.tajawal(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: d.closed.contains(h)
                                ? const Color(0xFFDC2626)
                                : const Color(0xFF15803D),
                            decoration: d.closed.contains(h)
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _windowRow(int index, _Window w) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _dateField('من', w.from, (v) => setState(() {
                    w.from = v;
                    _emit();
                  }))),
              const SizedBox(width: 6),
              Expanded(child: _dateField('إلى', w.to, (v) => setState(() {
                    w.to = v;
                    _emit();
                  }))),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFDC2626)),
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() {
                  _windows.removeAt(index);
                  _emit();
                }),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(child: _hourDropdown(w.start, (v) => setState(() {
                    w.start = v;
                    if (w.end <= v) w.end = (v + 1).clamp(1, 23);
                    _emit();
                  }))),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Text('→', style: TextStyle(color: Color(0xFF94A3B8))),
              ),
              Expanded(child: _hourDropdown(w.end, (v) => setState(() {
                    w.end = v;
                    if (w.start >= v) w.start = (v - 1).clamp(0, 22);
                    _emit();
                  }))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _hourDropdown(int value, ValueChanged<int> onChanged) {
    return DropdownButtonFormField<int>(
      initialValue: value,
      isDense: true,
      isExpanded: true,
      decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
      items: List.generate(24, (h) => h)
          .map((h) => DropdownMenuItem(
                value: h,
                child: Text(formatHour12(h),
                    style: GoogleFonts.tajawal(fontSize: 12)),
              ))
          .toList(),
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }

  Widget _dateField(String label, String value, ValueChanged<String> onChanged) {
    return InkWell(
      onTap: () async {
        final now = DateTime.now();
        final init = value.isNotEmpty
            ? (DateTime.tryParse(value) ?? now.add(const Duration(days: 1)))
            : now.add(const Duration(days: 1));
        final picked = await showDatePicker(
          context: context,
          initialDate: init,
          firstDate: now,
          lastDate: now.add(const Duration(days: 365)),
        );
        if (picked != null) onChanged(intl.DateFormat('yyyy-MM-dd').format(picked));
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.tajawal(fontSize: 11),
          border: const OutlineInputBorder(),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        ),
        child: Text(value.isEmpty ? '—' : value,
            style: GoogleFonts.tajawal(fontSize: 12)),
      ),
    );
  }

  Future<void> _addBlackout() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) {
      final ds = intl.DateFormat('yyyy-MM-dd').format(picked);
      if (!_blackouts.contains(ds)) {
        setState(() {
          _blackouts.add(ds);
          _blackouts.sort();
          _emit();
        });
      }
    }
  }

  Widget _addButton(String label, VoidCallback onTap) => Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          onPressed: onTap,
          icon: const Icon(Icons.add, size: 16),
          label: Text(label, style: GoogleFonts.tajawal(fontSize: 12)),
          style: TextButton.styleFrom(foregroundColor: _brand),
        ),
      );
}

class _DayHours {
  bool open;
  int start;
  int end;

  /// ساعات أقفلها المالك داخل النطاق — تُعامل كساعات ممتلئة فلا تُحجز.
  Set<int> closed;
  _DayHours(
      {required this.open,
      required this.start,
      required this.end,
      Set<int>? closed})
      : closed = closed ?? {};
}

class _Window {
  String from;
  String to;
  int start;
  int end;
  _Window({required this.from, required this.to, required this.start, required this.end});
}
