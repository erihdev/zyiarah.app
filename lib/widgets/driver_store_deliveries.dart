import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:zyiarah/utils/home_packages.dart' show formatSarAny;
import 'package:zyiarah/utils/net_timeout.dart';
import 'package:zyiarah/utils/store_order_flow.dart';

/// توصيلاتُ المتجرِ المُسندةُ إلى السائق (قرار المالك 2026-10-24).
///
/// الإدارةُ تُجهِّزُ طلبَ المتجرِ ثمّ تختارُ السائق، فيَظهرُ هنا «مع السائق»
/// حتى يُسلِّمَه فيَخرجُ من اللوحة. طلباتُ المتجرِ في `store_orders` لا
/// `orders`، فلها بثُّها وبطاقتُها — لا تَدخلُ ترتيبَ مهامِّ الخدماتِ ولا
/// تتبّعَ الموقعِ الحيّ.
///
/// القواعدُ تَسمحُ للسائقِ بقراءةِ ما أُسنِدَ إليه، وبكتابةٍ واحدة:
/// `with_driver ⇒ delivered` مع `delivered_at`.
class DriverStoreDeliveries extends StatefulWidget {
  final String driverId;

  /// قابلٌ للحقنِ في الاختبار — بلا Firebase.
  final Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>>? items;

  const DriverStoreDeliveries({super.key, required this.driverId, this.items});

  @override
  State<DriverStoreDeliveries> createState() => _DriverStoreDeliveriesState();
}

class _DriverStoreDeliveriesState extends State<DriverStoreDeliveries> {
  static const _brand = Color(0xFF660033);

  /// البثُّ يُبنى مرّةً لا في كلِّ `build`.
  late final Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _stream =
      widget.items ??
          FirebaseFirestore.instance
              .collection('store_orders')
              .where('driver_id', isEqualTo: widget.driverId)
              .where('status', isEqualTo: kStoreWithDriver)
              .snapshots()
              // مهلةُ أوّلِ حدثٍ كبقيّةِ البثوث: ذاكرةٌ باردةٌ وخادمٌ بعيدٌ لا
              // يُعلِّقانِ اللوحة — والخطأُ يُخفي القسمَ لا مهامَّ الخدمات.
              .firstEventTimeout()
              .map((s) => s.docs);

  final Set<String> _busy = {};

  Future<void> _deliver(String id, Map<String, dynamic> order) async {
    final code = (order['code'] ?? id.substring(0, 6)).toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text('تأكيد التسليم', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
          content: Text('هل سلّمت طلب المتجر #$code للعميلة؟',
              style: GoogleFonts.tajawal()),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ليس بعد')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
              child: const Text('تم التسليم'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy.add(id));
    try {
      await FirebaseFirestore.instance.collection('store_orders').doc(id).update({
        'status': kStoreDelivered,
        'delivered_at': FieldValue.serverTimestamp(),
      }).timeout(kNetCallTimeout);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('تم تسليم الطلب #$code ✅', style: GoogleFonts.tajawal()),
        backgroundColor: Colors.green,
      ));
    } catch (e) {
      if (!mounted) return;
      final denied = e is FirebaseException && e.code == 'permission-denied';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            denied
                ? 'لا يمكن تسليم هذا الطلب — ربما أُعيد إسناده أو أُلغي'
                : 'تعذّر تسجيل التسليم — تحقّق من الاتصال وأعد المحاولة',
            style: GoogleFonts.tajawal()),
        backgroundColor: Colors.red,
      ));
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  Future<void> _open(Uri uri) async {
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تعذّر الفتح'), backgroundColor: Colors.red));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تعذّر الفتح'), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
      stream: _stream,
      builder: (context, snap) {
        // لا شيءَ مُسندٌ (أو تعذّرت القراءة): لا قسمَ — مهامُّ الخدماتِ أسفلَه
        // تَبقى كما هي، ولا لافتةَ خطأٍ فوقَ لوحةٍ تعمل.
        final docs = snap.data ?? const [];
        if (docs.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('توصيلات المتجر (${docs.length})',
                  style: GoogleFonts.tajawal(fontWeight: FontWeight.w900, fontSize: 17)),
              const SizedBox(height: 10),
              for (final d in docs) _card(d.id, d.data()),
            ],
          ),
        );
      },
    );
  }

  Widget _card(String id, Map<String, dynamic> o) {
    final code = (o['code'] ?? id.substring(0, 6)).toString();
    final items = (o['items'] is List) ? (o['items'] as List) : const [];
    final phone = (o['client_phone'] ?? '').toString();
    final loc = o['delivery_location'];
    final busy = _busy.contains(id);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.indigo.withValues(alpha: 0.3), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.shopping_bag_outlined, color: Colors.indigo),
              const SizedBox(width: 8),
              Expanded(
                child: Text('طلب متجر #$code',
                    style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 15)),
              ),
              Text('${formatSarAny(o['total_amount'])} ر.س',
                  style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, color: _brand)),
            ],
          ),
          const SizedBox(height: 6),
          Text('العميلة: ${o['client_name'] ?? '—'}', style: GoogleFonts.tajawal(fontSize: 13)),
          if (items.isNotEmpty) ...[
            const SizedBox(height: 6),
            for (final it in items.take(6))
              if (it is Map)
                Text('• ${it['name'] ?? 'منتج'} × ${it['quantity'] ?? 1}',
                    style: GoogleFonts.tajawal(fontSize: 12, color: const Color(0xFF475569))),
            if (items.length > 6)
              Text('… و${items.length - 6} أصناف أخرى',
                  style: GoogleFonts.tajawal(fontSize: 12, color: const Color(0xFF475569))),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              if (phone.isNotEmpty)
                TextButton.icon(
                  onPressed: () => _open(Uri.parse('tel:$phone')),
                  icon: const Icon(Icons.call_outlined, size: 18),
                  label: const Text('اتصال'),
                ),
              if (loc is GeoPoint)
                TextButton.icon(
                  onPressed: () => _open(Uri.parse(
                      'https://maps.google.com/?q=${loc.latitude},${loc.longitude}')),
                  icon: const Icon(Icons.map_outlined, size: 18),
                  label: const Text('الموقع'),
                ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: busy ? null : () => _deliver(id, o),
                icon: busy
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.check_circle_outline, size: 18),
                label: const Text('تم التسليم'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green, foregroundColor: Colors.white),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
