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
      final area = _num(m['total_area_sqm']);
      return '${area.toStringAsFixed(2)} م² إجمالاً';
    }
    if (m['kind'] == 'ac_service') {
      return '${_num(m['total_units']).toInt()} مكيف';
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
      final rate = _num(p['price_per_sqm']);
      return _MetaRow(
        label: '${p['label'] ?? '-'}',
        detail: '${_t(l)}م × ${_t(w)}م = ${a.toStringAsFixed(2)} م² × ${_t(rate)}',
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
