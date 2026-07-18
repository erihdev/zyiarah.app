import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:zyiarah/services/audit_service.dart';
import 'package:zyiarah/screens/location_picker_screen.dart';
import 'package:zyiarah/utils/service_pricing_defaults.dart';
import 'package:zyiarah/utils/firestore_maps.dart';
import 'package:zyiarah/screens/admin/admin_zone_schedule_editor.dart';

class AdminHourlyZonesScreen extends StatefulWidget {
  const AdminHourlyZonesScreen({super.key});

  @override
  State<AdminHourlyZonesScreen> createState() => _AdminHourlyZonesScreenState();
}

class _AdminHourlyZonesScreenState extends State<AdminHourlyZonesScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> _toggleZoneEnabled(String id, bool currentValue) async {
    try {
      await _db.collection('service_zones').doc(id).update({'enabled': !currentValue});
      ZyiarahAuditService().logAction(
        action: currentValue ? 'DISABLE_ZONE' : 'ENABLE_ZONE',
        details: {'zone_id': id},
        targetId: id,
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("خطأ: $e")));
    }
  }

  Future<void> _deleteZone(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text("تأكيد الحذف", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
          content: const Text("هل أنت متأكد من حذف هذه المنطقة نهائياً؟ سيؤثر هذا على توفر الخدمة في هذا النطاق."),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("إلغاء")),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text("حذف الآن", style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );

    if (confirm == true) {
      try {
        await _db.collection('service_zones').doc(id).delete();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("تم حذف المنطقة بنجاح")));
        
        ZyiarahAuditService().logAction(
          action: 'DELETE_ZONE',
          details: {'zone_id': id},
          targetId: id,
        );
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("خطأ أثناء الحذف: $e")));
      }
    }
  }

  /// يطبّق أسعار الحوار الحالي على **المناطق المختارة** — الأسعار فقط.
  ///
  /// طلب المالك (بعد تجربة نسخة «الكل»): قائمة بكل المدن يختار منها ما يُطبَّق
  /// عليه، بدل الكل-أو-لا-شيء. الحقول المكتوبة محصورة عمداً في الأسعار — لا اسم
  /// ولا إحداثيات ولا نصف قطر ولا تفعيل ولا جدول: نسخ الأسعار يجب ألا يمسّ
  /// هويّة المنطقة ولا جدولها.
  Future<int> _applyPricesToZones(
      Iterable<String> zoneIds, Map<String, dynamic> priceFields) async {
    final batch = _db.batch();
    for (final id in zoneIds) {
      batch.update(_db.collection('service_zones').doc(id), {
        ...priceFields,
        'updated_at': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    await ZyiarahAuditService().logAction(
      action: 'APPLY_PRICES_TO_ZONES',
      details: {'zones': zoneIds.toList(), ...priceFields},
      targetId: 'service_zones',
    );
    return zoneIds.length;
  }

  /// منتقي المناطق: كل المدن كمربعات اختيار + «تحديد الكل». يُرجع المعرّفات
  /// المختارة أو null عند الإلغاء. الاختيار الصريح هو التأكيد — لا حوار ثانٍ.
  Future<Set<String>?> _pickTargetZones(BuildContext ctx) async {
    final snap = await _db.collection('service_zones').get();
    if (!ctx.mounted) return null;
    final zones = snap.docs;
    final selected = <String>{};
    return showDialog<Set<String>>(
      context: ctx,
      builder: (c2) => StatefulBuilder(
        builder: (c2, setPickState) {
          final allChecked = selected.length == zones.length && zones.isNotEmpty;
          return Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Text('اختر المناطق لتطبيق الأسعار',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              content: SizedBox(
                width: 340,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CheckboxListTile(
                      value: allChecked,
                      onChanged: (v) => setPickState(() {
                        selected.clear();
                        if (v == true) selected.addAll(zones.map((d) => d.id));
                      }),
                      title: const Text('تحديد الكل',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                    ),
                    const Divider(height: 8),
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            for (final d in zones)
                              CheckboxListTile(
                                value: selected.contains(d.id),
                                onChanged: (v) => setPickState(() {
                                  if (v == true) {
                                    selected.add(d.id);
                                  } else {
                                    selected.remove(d.id);
                                  }
                                }),
                                title: Text((d.data()['name'] ?? d.id).toString()),
                                controlAffinity: ListTileControlAffinity.leading,
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'تُنسخ الأسعار فقط — الأسماء والمواقع والجداول لا تتأثر.',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(c2),
                    child: const Text('إلغاء')),
                ElevatedButton(
                  onPressed: selected.isEmpty
                      ? null
                      : () => Navigator.pop(c2, Set<String>.of(selected)),
                  child: Text(
                      selected.isEmpty ? 'حفظ' : 'حفظ (${selected.length})'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// يحوّل اسم المنطقة المكتوب إلى إحداثيات — «اكتب صبيا فتقفز الخريطة إلى صبيا».
  ///
  /// نفس محرّك بحث منتقي الموقع (Mapbox forward geocoding): مقيّد بالسعودية،
  /// ومنحاز لمنطقة جازان (proximity) كي تتقدّم «صبيا جازان» على أي تشابه أبعد.
  /// بمهلة، والفشل يُسجَّل ولا يُزعج — هذه مساعدة، والنقر على الخريطة يبقى سيّداً.
  Future<GeoPoint?> _geocodeZoneName(String query) async {
    final token = dotenv.env['MAPBOX_TOKEN'] ?? '';
    if (token.isEmpty || query.trim().length < 2) return null;
    try {
      final url = Uri.parse(
          'https://api.mapbox.com/search/geocode/v6/forward'
          '?q=${Uri.encodeComponent(query.trim())}'
          '&access_token=$token&language=ar&country=sa'
          '&proximity=43.0505,17.3023&limit=1');
      final res = await http.get(url).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final features = (json.decode(res.body)['features'] as List?) ?? [];
      if (features.isEmpty) return null;
      final coords = features.first['geometry']?['coordinates'];
      if (coords is! List || coords.length < 2) return null;
      return GeoPoint((coords[1] as num).toDouble(), (coords[0] as num).toDouble());
    } catch (e) {
      debugPrint('[ZoneGeocode] failed for "$query": $e');
      return null;
    }
  }

  void _showZoneDialog({DocumentSnapshot? doc}) {
    final Map<String, dynamic>? data = doc?.data() as Map<String, dynamic>?;
    final nameCtrl = TextEditingController(text: data?['name'] ?? '');
    final radiusCtrl = TextEditingController(text: data?['radiusKm']?.toString() ?? '15');
    
    final p1Ctrl = TextEditingController(text: data?['prices']?['1']?.toString() ?? '');
    final p4Ctrl = TextEditingController(text: data?['prices']?['4']?.toString() ?? '');
    final p5Ctrl = TextEditingController(text: data?['prices']?['5']?.toString() ?? '');
    final p6Ctrl = TextEditingController(text: data?['prices']?['6']?.toString() ?? '');
    final p8Ctrl = TextEditingController(text: data?['prices']?['8']?.toString() ?? '');

    // sofaPrice/rugPrice (المتر الطولي) أُزيلا بقرار المالك: «المتر الطولي يختفي».
    // لم يعد لهما حقلٌ هنا ولا قارئ في التطبيق — نظام تسعير واحد فقط، بالمتر المربع.
    // (كان وجودهما مع حقول م² هو سبب المشكلة: الحيّان موسومان «قديمة» والميتة معروضة
    // كأنها العاملة، فمن يسعّر الجديدة لا يغيّر شيئاً وهو مقتنع أنه سعّر.)
    final pSofaSqmCtrl = TextEditingController(text: (data?['sofaSqmPrice'] ?? kDefaultSofaSqmPrice).toString());
    final pRugSqmCtrl = TextEditingController(text: (data?['rugSqmPrice'] ?? kDefaultRugSqmPrice).toString());
    final pAcMaintWinCtrl = TextEditingController(text: (data?['acMaintWindowPrice'] ?? kDefaultAcMaintWindowPrice).toString());
    final pAcMaintSplitCtrl = TextEditingController(text: (data?['acMaintSplitPrice'] ?? kDefaultAcMaintSplitPrice).toString());
    final pAcWashWinCtrl = TextEditingController(text: (data?['acWashWindowPrice'] ?? kDefaultAcWashWindowPrice).toString());
    final pAcWashSplitCtrl = TextEditingController(text: (data?['acWashSplitPrice'] ?? kDefaultAcWashSplitPrice).toString());

    // rank عبر num: لو خُزّن double يوماً (لوحة الويب) لا ينفجر الحوار.
    // مصدر القائمة المنسدلة «نسخ الأسعار من»: يُجلب مرة عند فتح الحوار.
    final Future<QuerySnapshot<Map<String, dynamic>>> zonesFuture =
        _db.collection('service_zones').get();
    String? copiedFromId;
    // ترميز الاسم المكتوب إلى موقع — مؤجَّل كي لا نستعلم عند كل حرف.
    Timer? nameDebounce;

    int rank = (data?['rank'] as num?)?.toInt() ?? 0;
    GeoPoint? selectedGeo = data?['centerLoc'] as GeoPoint?;
    bool isSaving = false;

    // جدول فتح المنطقة — يبنيه المحرّر ويُكتب على المستند. null قبل أي تعديل =
    // نُبقي القيمة الحالية كما هي (لا نكتب schedule إن لم يُلمَس).
    // stringKeyedMap لا `as`: الخرائط المتداخلة تصل Map<Object?,Object?> والتحويل
    // الصلب كان يرمي **قبل** showDialog — فيموت زرّ التعديل بصمت لأي منطقة لها جدول.
    Map<String, dynamic>? scheduleData = stringKeyedMap(data?['schedule']);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Text(doc == null ? "إضافة منطقة تغطية" : "تعديل المنطقة", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
              // عرض مضبوط (لا SingleChildScrollView عارية): AlertDialog يقيس محتواه
              // بـ IntrinsicWidth، وخريطة المعاينة بداخله (FlutterMap = LayoutBuilder)
              // «لا تدعم الأبعاد الذاتية» فترمي أثناء التخطيط — حوارٌ بلا مقاس، غير
              // مرئي، يبتلع النقرات فيبدو زرّ التعديل ميتاً. العرض الصريح يُنهي
              // القياس الذاتي عند هذا الحدّ فلا يصل الخريطة إطلاقاً.
              content: SizedBox(
                width: 380,
                child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isSaving) const Padding(padding: EdgeInsets.only(bottom: 15), child: LinearProgressIndicator(color: Color(0xFF1E293B))),

                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                          labelText: 'اسم المنطقة (مثلاً: صبيا)',
                          border: OutlineInputBorder()),
                      // كتابة الاسم تنقل الخريطة إليه تلقائياً (طلب المالك):
                      // «كتبت صبيا — المفترض ينقلني مباشرة إلى صبيا».
                      onChanged: (q) {
                        nameDebounce?.cancel();
                        nameDebounce = Timer(const Duration(milliseconds: 700), () async {
                          final g = await _geocodeZoneName(q);
                          if (g == null) return;
                          if (!ctx.mounted) return;
                          setDialogState(() => selectedGeo = g);
                        });
                      },
                    ),
                    const SizedBox(height: 15),
                    
                    // الخريطة الحيّة — ظاهرة دائماً تحت الاسم مباشرة (طلب المالك):
                    // قبل التحديد تفتح على منطقة جازان، والنقر عليها يضع المركز،
                    // وتغيير نصف القطر يُكبّر/يُصغّر الدائرة حيّاً.
                    _ZoneCoveragePreview(
                      center: selectedGeo,
                      radiusKm: double.tryParse(radiusCtrl.text) ?? 15.0,
                      onPick: (g) => setDialogState(() => selectedGeo = g),
                    ),
                    const SizedBox(height: 12),

                    TextField(
                      controller: radiusCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'نصف القطر للتغطية (كم)', border: OutlineInputBorder()),
                      // إعادة الرسم عند كل تغيير كي تتحدث دائرة التغطية حيّاً.
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 10),

                    // خريطة كاملة للتحديد الأدق (بحث بالاسم + سحب) — مكمّلة للنقر السريع.
                    InkWell(
                      onTap: () async {
                        final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => LocationPickerScreen(
                          serviceName: 'تحديد موقع المنطقة',
                          radius: double.tryParse(radiusCtrl.text) ?? 15.0,
                        )));
                        if (result != null && result is GeoPoint) {
                          setDialogState(() => selectedGeo = result);
                        }
                      },
                      child: Row(
                        children: [
                          Icon(Icons.open_in_full_rounded, size: 15, color: Colors.blue.shade700),
                          const SizedBox(width: 6),
                          Text('فتح خريطة كاملة لتحديدٍ أدق',
                              style: TextStyle(fontSize: 12, color: Colors.blue.shade700)),
                        ],
                      ),
                    ),

                    const Divider(height: 30),
                    // «نسخ الأسعار من منطقة سابقة» (طلب المالك): عند إضافة مدينة
                    // جديدة يختار مدينة قائمة فتُنسخ أسعارها **إلى الحقول فوراً**
                    // (الساعات + م² + المكيفات) ثم يعدّل ما شاء ويحفظ عادي.
                    // لا كتابة على أي منطقة أخرى — تعبئة نموذج فحسب.
                    FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      future: zonesFuture,
                      builder: (context, snap) {
                        final docs = (snap.data?.docs ?? [])
                            .where((d) => d.id != doc?.id)
                            .toList();
                        if (docs.isEmpty) return const SizedBox.shrink();
                        return DropdownButtonFormField<String>(
                          initialValue: copiedFromId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'نسخ الأسعار من منطقة سابقة',
                            prefixIcon: Icon(Icons.content_copy_rounded, size: 18),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: [
                            for (final d in docs)
                              DropdownMenuItem(
                                value: d.id,
                                child: Text((d.data()['name'] ?? d.id).toString()),
                              ),
                          ],
                          onChanged: isSaving
                              ? null
                              : (id) {
                                  if (id == null) return;
                                  final src = docs
                                      .firstWhere((d) => d.id == id)
                                      .data();
                                  final prices =
                                      stringKeyedMap(src['prices']) ?? {};
                                  String n(dynamic v) => v == null
                                      ? ''
                                      : (v is num
                                          ? (v == v.roundToDouble()
                                              ? v.toInt().toString()
                                              : v.toString())
                                          : v.toString());
                                  setDialogState(() {
                                    copiedFromId = id;
                                    p1Ctrl.text = n(prices['1']);
                                    p4Ctrl.text = n(prices['4']);
                                    p5Ctrl.text = n(prices['5']);
                                    p6Ctrl.text = n(prices['6']);
                                    p8Ctrl.text = n(prices['8']);
                                    pSofaSqmCtrl.text = n(src['sofaSqmPrice']);
                                    pRugSqmCtrl.text = n(src['rugSqmPrice']);
                                    pAcMaintWinCtrl.text =
                                        n(src['acMaintWindowPrice']);
                                    pAcMaintSplitCtrl.text =
                                        n(src['acMaintSplitPrice']);
                                    pAcWashWinCtrl.text =
                                        n(src['acWashWindowPrice']);
                                    pAcWashSplitCtrl.text =
                                        n(src['acWashSplitPrice']);
                                  });
                                },
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    const Text("أسعار النظافة بالساعة (ر.س):", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: TextField(controller: p1Ctrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'ساعة', border: OutlineInputBorder()))),
                        const SizedBox(width: 8),
                        Expanded(child: TextField(controller: p4Ctrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '4 ساعات', border: OutlineInputBorder()))),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: TextField(controller: p5Ctrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '5 ساعات', border: OutlineInputBorder()))),
                        const SizedBox(width: 8),
                        Expanded(child: TextField(controller: p6Ctrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '6 ساعات', border: OutlineInputBorder()))),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Spacer(),
                        Expanded(child: TextField(controller: p8Ctrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '8 ساعات', border: OutlineInputBorder()))),
                        const Spacer(),
                      ],
                    ),
                    
                    const Divider(height: 30),
                    const Text("أسعار الكنب والسجاد — بالمتر المربع (ر.س/م²):", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const Text("العميلة تُدخل طول وعرض كل قطعة ويُحسب السعر آلياً. صفر = تعطيل الخدمة في هذه المنطقة.",
                        style: TextStyle(fontSize: 11, color: Colors.grey)),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: TextField(controller: pSofaSqmCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'الكنب (ر.س/م²)', border: OutlineInputBorder()))),
                        const SizedBox(width: 8),
                        Expanded(child: TextField(controller: pRugSqmCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'السجاد (ر.س/م²)', border: OutlineInputBorder()))),
                      ],
                    ),

                    const Divider(height: 30),
                    const Text("أسعار المكيفات — لكل مكيف (ر.س):", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const Text("اتركه فارغاً لتعطيل النوع في هذه المنطقة.",
                        style: TextStyle(fontSize: 11, color: Colors.grey)),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: TextField(controller: pAcMaintWinCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'صيانة — شباك', border: OutlineInputBorder()))),
                        const SizedBox(width: 8),
                        Expanded(child: TextField(controller: pAcMaintSplitCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'صيانة — سبليت', border: OutlineInputBorder()))),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: TextField(controller: pAcWashWinCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'غسيل — شباك', border: OutlineInputBorder()))),
                        const SizedBox(width: 8),
                        Expanded(child: TextField(controller: pAcWashSplitCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'غسيل — سبليت', border: OutlineInputBorder()))),
                      ],
                    ),

                    // جدول فتح المنطقة: أيام وساعات العمل + فتح/إغلاق تواريخ استثنائية.
                    ZoneScheduleEditor(
                      initial: scheduleData,
                      onChanged: (s) => scheduleData = s,
                    ),
                  ],
                ),
              ),
              ),
              actions: [
                // نسخ الأسعار لمناطق يختارها الأدمن من قائمة (طلب المالك) —
                // الاختيار الصريح + زرّ الحفظ هما التأكيد.
                TextButton.icon(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final targets = await _pickTargetZones(ctx);
                          if (targets == null || targets.isEmpty) return;
                          setDialogState(() => isSaving = true);
                          try {
                            final n = await _applyPricesToZones(targets, {
                              'prices': {
                                '1': double.tryParse(p1Ctrl.text) ?? 0,
                                '4': double.tryParse(p4Ctrl.text) ?? 0,
                                '5': double.tryParse(p5Ctrl.text) ?? 0,
                                '6': double.tryParse(p6Ctrl.text) ?? 0,
                                '8': double.tryParse(p8Ctrl.text) ?? 0,
                              },
                              'sofaSqmPrice': double.tryParse(pSofaSqmCtrl.text) ?? 0,
                              'rugSqmPrice': double.tryParse(pRugSqmCtrl.text) ?? 0,
                              'acMaintWindowPrice': double.tryParse(pAcMaintWinCtrl.text) ?? 0,
                              'acMaintSplitPrice': double.tryParse(pAcMaintSplitCtrl.text) ?? 0,
                              'acWashWindowPrice': double.tryParse(pAcWashWinCtrl.text) ?? 0,
                              'acWashSplitPrice': double.tryParse(pAcWashSplitCtrl.text) ?? 0,
                            });
                            if (ctx.mounted) {
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                  content: Text('حُفظت الأسعار في $n منطقة ✅'),
                                  backgroundColor: Colors.green));
                            }
                          } catch (e) {
                            setDialogState(() => isSaving = false);
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                  content: Text('تعذّر النسخ: $e'),
                                  backgroundColor: Colors.red));
                            }
                          }
                        },
                  icon: const Icon(Icons.copy_all_rounded, size: 18),
                  label: const Text('تطبيق على مناطق…'),
                ),
                TextButton(onPressed: isSaving ? null : () => Navigator.pop(ctx), child: const Text("إلغاء")),
                ElevatedButton(
                  onPressed: isSaving ? null : () async {
                    if (nameCtrl.text.isEmpty || selectedGeo == null) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("يرجى إكمال البيانات وتحديد الموقع")));
                      return;
                    }
                    setDialogState(() => isSaving = true);
                    try {
                      final newData = {
                        'name': nameCtrl.text.trim(),
                        'centerLoc': selectedGeo,
                        'radiusKm': double.tryParse(radiusCtrl.text) ?? 15.0,
                        'prices': {
                          '1': double.tryParse(p1Ctrl.text) ?? 0,
                          '4': double.tryParse(p4Ctrl.text) ?? 0,
                          '5': double.tryParse(p5Ctrl.text) ?? 0,
                          '6': double.tryParse(p6Ctrl.text) ?? 0,
                          '8': double.tryParse(p8Ctrl.text) ?? 0,
                        },
                        // صفر = «غير مسعّرة» فتُعطَّل الخدمة بدل بيعها بسعر افتراضي.
                        // (sofaPrice/rugPrice الطوليان لم يعودا يُكتبان — النظام أُلغي.
                        //  نتركهما في المستندات القائمة بلا مساس: لا قارئ لهما، وحذفهما
                        //  يكسر أي نسخة قديمة ما زالت مثبَّتة قبل التحديث الإجباري.)
                        'sofaSqmPrice': double.tryParse(pSofaSqmCtrl.text) ?? 0,
                        'rugSqmPrice': double.tryParse(pRugSqmCtrl.text) ?? 0,
                        'acMaintWindowPrice': double.tryParse(pAcMaintWinCtrl.text) ?? 0,
                        'acMaintSplitPrice': double.tryParse(pAcMaintSplitCtrl.text) ?? 0,
                        'acWashWindowPrice': double.tryParse(pAcWashWinCtrl.text) ?? 0,
                        'acWashSplitPrice': double.tryParse(pAcWashSplitCtrl.text) ?? 0,
                        'rank': rank,
                        'enabled': data?['enabled'] ?? true,
                        // جدول الفتح — يُكتب متى لمس الأدمن المحرّر (scheduleData != null).
                        // نُبقيه إن لم يُلمَس كي لا نمسح جدولاً قائماً بحفظٍ عابر.
                        if (scheduleData != null) 'schedule': scheduleData,
                        'updated_at': FieldValue.serverTimestamp(),
                      };

                      if (doc == null) {
                        await _db.collection('service_zones').add(newData);
                      } else {
                        await _db.collection('service_zones').doc(doc.id).update(newData);
                      }
                      
                      ZyiarahAuditService().logAction(
                        action: doc == null ? 'CREATE_ZONE' : 'UPDATE_ZONE',
                        details: {
                          'name': newData['name'],
                          'zone_id': doc?.id ?? 'NEW',
                        },
                        targetId: doc?.id,
                      );

                      if (ctx.mounted) Navigator.pop(ctx);
                    } catch (e) {
                      setDialogState(() => isSaving = false);
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF5D1B5E), foregroundColor: Colors.white),
                  child: Text(isSaving ? "جاري الحفظ..." : "حفظ المنطقة"),
                ),
              ],
            ),
          );
        },
      ),
    ).whenComplete(() {
      nameDebounce?.cancel();
      nameCtrl.dispose();
      radiusCtrl.dispose();
      p1Ctrl.dispose();
      p4Ctrl.dispose();
      p5Ctrl.dispose();
      p6Ctrl.dispose();
      p8Ctrl.dispose();
      // الستة الجديدة كانت تُسرَّب في كل فتح/إغلاق للحوار — أُضيفت الحقول ونُسي التخلّص.
      pSofaSqmCtrl.dispose();
      pRugSqmCtrl.dispose();
      pAcMaintWinCtrl.dispose();
      pAcMaintSplitCtrl.dispose();
      pAcWashWinCtrl.dispose();
      pAcWashSplitCtrl.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          title: Text('إدارة ونطاقات الخدمة', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFF5D1B5E),
          foregroundColor: Colors.white,
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => _showZoneDialog(),
          backgroundColor: const Color(0xFF5D1B5E),
          child: const Icon(Icons.add_location_alt_rounded, color: Colors.white),
        ),
        body: StreamBuilder<QuerySnapshot>(
          stream: _db.collection('service_zones').orderBy('rank').snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
            if (snapshot.hasError) return const Center(child: Text("تعذّر تحميل المناطق", style: TextStyle(color: Colors.grey)));
            final docs = snapshot.data?.docs ?? [];
            if (docs.isEmpty) return const Center(child: Text("لا توجد مناطق تغطية حالياً"));

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: docs.length,
              itemBuilder: (context, index) {
                final doc = docs[index];
                final data = doc.data() as Map<String, dynamic>;

                final isEnabled = data['enabled'] as bool? ?? true;
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    leading: CircleAvatar(
                      backgroundColor: isEnabled ? Colors.green.shade50 : Colors.grey.shade100,
                      child: Icon(Icons.location_on, color: isEnabled ? Colors.green : Colors.grey),
                    ),
                    title: Text(data['name'] ?? '', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("نطاق التغطية: ${data['radiusKm']} كم", style: const TextStyle(fontSize: 12)),
                        const SizedBox(height: 2),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: isEnabled ? Colors.green.shade50 : Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            isEnabled ? "مفعّلة" : "معطّلة",
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isEnabled ? Colors.green.shade700 : Colors.grey.shade600),
                          ),
                        ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch(
                          value: isEnabled,
                          onChanged: (_) => _toggleZoneEnabled(doc.id, isEnabled),
                          activeThumbColor: Colors.green,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        IconButton(icon: const Icon(Icons.edit_outlined, color: Colors.blue, size: 20), onPressed: () => _showZoneDialog(doc: doc)),
                        IconButton(icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 20), onPressed: () => _deleteZone(doc.id)),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// معاينة حيّة لنطاق تغطية المنطقة داخل نافذة الإضافة/التعديل.
///
/// تُظهر للإدارة **ما الذي يغطيه نصف القطر فعلاً على الأرض** قبل الحفظ: دائرة حول المركز
/// المختار تتحدث فور تغيير الرقم. بدونها كان على الأدمن فتح الخريطة والرجوع لكل تجربة،
/// ولا يرى أثر تغيير نصف القطر إطلاقاً بعد اختيار المركز.
class _ZoneCoveragePreview extends StatelessWidget {
  /// null قبل التحديد — تُعرض الخريطة على مركز جازان الافتراضي بانتظار نقرة.
  final GeoPoint? center;
  final double radiusKm;
  final ValueChanged<GeoPoint> onPick;

  const _ZoneCoveragePreview({
    required this.center,
    required this.radiusKm,
    required this.onPick,
  });

  /// مركز منطقة جازان — نقطة بداية معقولة لنشاطٍ كل مناطقه هناك.
  static const LatLng _fallbackCenter = LatLng(17.3023, 43.0505);

  @override
  Widget build(BuildContext context) {
    final token = dotenv.env['MAPBOX_TOKEN'] ?? '';
    final picked = center != null;
    final latLng = picked
        ? LatLng(center!.latitude, center!.longitude)
        : _fallbackCenter;
    // قبل التحديد: زوم واسع يُظهر المنطقة كلها؛ بعده: زوم يناسب نصف القطر.
    final zoom = picked ? _zoomForRadius(radiusKm) : 9.3;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(picked ? Icons.travel_explore_rounded : Icons.touch_app_rounded,
                size: 16, color: Colors.blue),
            const SizedBox(width: 6),
            Text(
              picked
                  ? 'نطاق التغطية — ${radiusKm.toStringAsFixed(radiusKm % 1 == 0 ? 0 : 1)} كم'
                  : 'اضغط على الخريطة لتحديد مركز المنطقة',
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: 190,
            child: Stack(
              children: [
                FlutterMap(
                  key: ValueKey(picked
                      ? 'zp_${center!.latitude.toStringAsFixed(5)}_${center!.longitude.toStringAsFixed(5)}_$radiusKm'
                      : 'zp_unpicked'),
                  options: MapOptions(
                    initialCenter: latLng,
                    initialZoom: zoom,
                    // النقر يحدّد المركز؛ بقية الإيماءات معطّلة كي لا تبتلع
                    // الخريطةُ تمريرَ الحوار.
                    interactionOptions:
                        const InteractionOptions(flags: InteractiveFlag.none),
                    onTap: (tapPos, ll) =>
                        onPick(GeoPoint(ll.latitude, ll.longitude)),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/{z}/{x}/{y}?access_token=$token',
                      additionalOptions: {'accessToken': token},
                      userAgentPackageName: 'com.zyiarah.zyiarah',
                    ),
                    if (picked)
                      CircleLayer(
                        circles: [
                          CircleMarker(
                            point: latLng,
                            radius: radiusKm * 1000,
                            useRadiusInMeter: true,
                            color: Colors.blue.withValues(alpha: 0.22),
                            borderColor: Colors.blue,
                            borderStrokeWidth: 2,
                          ),
                        ],
                      ),
                    if (picked)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: latLng,
                            width: 34,
                            height: 34,
                            child: const Icon(Icons.location_on,
                                color: Color(0xFF5D1B5E), size: 34),
                          ),
                        ],
                      ),
                  ],
                ),
                if (!picked)
                  IgnorePointer(
                    child: Container(
                      alignment: Alignment.bottomCenter,
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text('اضغط لوضع المركز هنا',
                            style:
                                TextStyle(color: Colors.white, fontSize: 11)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// زوم يجعل دائرة نصف القطر مرئية كاملة في معاينة 190px.
double _zoomForRadius(double km) {
  if (km <= 2) return 12.5;
  if (km <= 5) return 11.3;
  if (km <= 10) return 10.3;
  if (km <= 20) return 9.3;
  if (km <= 40) return 8.3;
  return 7.3;
}
