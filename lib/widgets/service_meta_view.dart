import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// يعرض تفصيل الخدمة المخزَّن في `service_meta` على الطلب.
///
/// **سبب وجوده:** الطلب كان يصل الإدارة والسائق بمبلغٍ مجرّد — «تنظيف الكنب: 230 ر.س».
/// كم قطعة؟ ما مقاسها؟ كم مكيفاً ومن أي نوع؟ لا أحد يعرف: السائق يذهب بلا معرفة ما
/// يحمل من عُدّة، والإدارة لا تملك ما تدقّق به المبلغ إن اعترضت العميلة.
///
/// وكتابة `service_meta` بلا قارئ = بيانات ميتة، وهو المرض نفسه الذي أنتج حقول تسعير
/// تكتبها الإدارة ولا يقرؤها أحد. لذلك يُعرض هنا للطرفين من مصدر واحد.
///
/// سطر مختصر للتفصيل — لبطاقات القوائم حيث لا مساحة لجدول كامل.
///
/// «صيانة شباك ×1 • غسيل سبليت ×2» للمكيفات، و«كنب ×2 (4.50 م²) • سجاد ×1 (6.00 م²)»
/// للكنب والسجاد. كانت قوائم الإدارة تعرض اسم الخدمة والمبلغ فقط، فلا يُعرف نوع
/// المكيف ولا عدد الوحدات إلا بفتح تفاصيل كل طلب (ملاحظة المالك).
///
/// يُرجع null إن غاب الحقل (طلبات قديمة) أو تلف — فلا يُرسم السطر أصلاً.
String? zyiarahServiceMetaSummary(dynamic meta) {
  if (meta is! Map) return null;
  final parts = <String>[];
  switch (meta['kind']) {
    // السيارات والمكيفات بنية بنود واحدة (label/count) — نفس الملخّص.
    case 'car_interior':
    case 'ac_service':
      final lines = meta['lines'];
      if (lines is! List) return null;
      for (final l in lines.whereType<Map>()) {
        final c = ZyiarahServiceMetaView._num(l['count']).toInt();
        if (c > 0) parts.add('${l['label'] ?? '-'} ×$c');
      }
    case 'sofa_rug_sqm':
      final pieces = meta['pieces'];
      if (pieces is! List) return null;
      // تجميع القطع حسب النوع: العدد والمقدار المسعَّر (م² للسجاد، م.ط للكنب).
      final count = <String, int>{};
      final measure = <String, double>{};
      final unit = <String, String>{};
      for (final p in pieces.whereType<Map>()) {
        final label = '${p['label'] ?? '-'}'.split(' ').first; // «كنب 1» → «كنب»
        count[label] = (count[label] ?? 0) + 1;
        // الطلبات القديمة (بلا billed_measure/uses_area) كانت كلها بالمساحة.
        final m = ZyiarahServiceMetaView._num(
            p['billed_measure'] ?? p['area_sqm']);
        measure[label] = (measure[label] ?? 0) + m;
        unit[label] = p['uses_area'] == false ? 'م.ط' : 'م²';
      }
      for (final label in count.keys) {
        parts.add(
            '$label ×${count[label]} (${measure[label]!.toStringAsFixed(2)} ${unit[label]})');
      }
    case 'store_products':
      final items = meta['items'];
      if (items is! List) return null;
      for (final it in items.whereType<Map>()) {
        final q = ZyiarahServiceMetaView._num(it['quantity']).toInt();
        if (q > 0) parts.add('${it['name'] ?? '-'} ×$q');
      }
    default:
      return null;
  }
  return parts.isEmpty ? null : parts.join(' • ');
}

/// الجدول الكامل للتفصيل — لشاشتي تفاصيل الطلب (إدارة وسائق).
///
/// يتجاهل نفسه بصمت إن كان الحقل غائباً (الطلبات القديمة) أو تالفاً — لا يُسقط الشاشة.
class ZyiarahServiceMetaView extends StatelessWidget {
  final dynamic meta;
  const ZyiarahServiceMetaView({super.key, required this.meta});

  static const Color _brand = Color(0xFF5D1B5E);

  @override
  Widget build(BuildContext context) {
    final m = meta;
    if (m is! Map) return const SizedBox.shrink();

    final rows = switch (m['kind']) {
      'sofa_rug_sqm' => _sofaRugRows(m),
      'ac_service' => _acRows(m),
      'car_interior' => _acRows(m), // بنود label/count/unit_price نفسها
      'store_products' => _storeRows(m),

      _ => const <_MetaRow>[],
    };
    if (rows.isEmpty) return const SizedBox.shrink();

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.receipt_long_rounded, size: 18, color: _brand),
                const SizedBox(width: 8),
                Text('تفصيل الخدمة',
                    style: GoogleFonts.tajawal(
                        fontWeight: FontWeight.bold, color: _brand)),
                const Spacer(),
                Text(_headline(m),
                    style: GoogleFonts.tajawal(
                        fontSize: 12, color: const Color(0xFF64748B))),
              ],
            ),
            const Divider(height: 18),
            ...rows.map((r) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(r.label,
                            style: GoogleFonts.tajawal(
                                fontSize: 13, color: const Color(0xFF1E293B))),
                      ),
                      Text(r.detail,
                          style: GoogleFonts.tajawal(
                              fontSize: 12, color: const Color(0xFF64748B))),
                      const SizedBox(width: 10),
                      Text(r.total,
                          style: GoogleFonts.tajawal(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: _brand)),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }

  String _headline(Map m) {
    if (m['kind'] == 'sofa_rug_sqm') {
      final pieces = m['pieces'];
      final n = pieces is List ? pieces.length : 0;
      return '$n قطعة';
    }
    if (m['kind'] == 'ac_service') {
      return '${_num(m['total_units']).toInt()} مكيف';
    }
    if (m['kind'] == 'car_interior') {
      return '${_num(m['total_cars']).toInt()} سيارة';
    }
    if (m['kind'] == 'store_products') {
      return '${_num(m['total_qty']).toInt()} منتج';
    }
    return '';
  }

  List<_MetaRow> _sofaRugRows(Map m) {
    final pieces = m['pieces'];
    if (pieces is! List) return const [];
    return pieces.whereType<Map>().map((p) {
      final l = _num(p['length_m']);
      final w = _num(p['width_m']);
      final a = _num(p['area_sqm']);
      final rate = _num(p['price_per_unit'] ?? p['price_per_sqm']);
      // الطلبات القديمة (بلا uses_area) كانت كلها بالمساحة؛ الجديدة توسم الكنب طولياً.
      final usesArea = p['uses_area'] != false && w > 0;
      return _MetaRow(
        label: '${p['label'] ?? '-'}',
        detail: usesArea
            ? '${_t(l)}م × ${_t(w)}م = ${a.toStringAsFixed(2)} م² × ${_t(rate)}'
            : '${_t(l)} م.ط × ${_t(rate)}',
        total: '${_num(p['line_total']).toStringAsFixed(2)} ر.س',
      );
    }).toList();
  }

  List<_MetaRow> _acRows(Map m) {
    final lines = m['lines'];
    if (lines is! List) return const [];
    return lines.whereType<Map>().map((l) {
      final count = _num(l['count']).toInt();
      final unit = _num(l['unit_price']);
      return _MetaRow(
        label: '${l['label'] ?? '-'}',
        detail: '$count × ${_t(unit)} ر.س',
        total: '${_num(l['line_total']).toStringAsFixed(2)} ر.س',
      );
    }).toList();
  }

  /// أصناف طلب المتجر: [{name, quantity, unit_price, line_total}].
  List<_MetaRow> _storeRows(Map m) {
    final items = m['items'];
    if (items is! List) return const [];
    return items.whereType<Map>().map((it) {
      final qty = _num(it['quantity']).toInt();
      final unit = _num(it['unit_price']);
      return _MetaRow(
        label: '${it['name'] ?? '-'}',
        detail: '$qty × ${_t(unit)} ر.س',
        total: '${_num(it['line_total']).toStringAsFixed(2)} ر.س',
      );
    }).toList();
  }

  /// حقول Firestore قد تصل نصّاً — التحويل المباشر كان يُسقط شاشات في هذا المشروع.
  static double _num(dynamic v) => v is num
      ? v.toDouble()
      : (v == null ? 0.0 : double.tryParse(v.toString()) ?? 0.0);

  static String _t(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
}

class _MetaRow {
  final String label;
  final String detail;
  final String total;
  const _MetaRow({required this.label, required this.detail, required this.total});
}
