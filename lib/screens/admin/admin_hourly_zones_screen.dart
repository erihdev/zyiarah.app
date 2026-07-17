import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:zyiarah/services/audit_service.dart';
import 'package:zyiarah/screens/location_picker_screen.dart';
import 'package:zyiarah/utils/service_pricing_defaults.dart';
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

  /// يطبّق أسعار الحوار الحالي على **كل** المناطق — الأسعار فقط.
  ///
  /// طلب المالك: تعديل واحد يعمّ الجميع بدل تكرار الإدخال منطقةً منطقة (ومع التوسّع
  /// يصير التكرار نسياناً: منطقة تبقى بسعر قديم). الحقول المكتوبة محصورة عمداً في
  /// الأسعار — لا اسم ولا إحداثيات ولا نصف قطر ولا تفعيل ولا جدول: تعميم الأسعار
  /// يجب ألا يمسّ هويّة المنطقة ولا جدولها.
  Future<int> _applyPricesToAllZones(Map<String, dynamic> priceFields) async {
    final snap = await _db.collection('service_zones').get();
    final batch = _db.batch();
    for (final d in snap.docs) {
      batch.update(d.reference, {
        ...priceFields,
        'updated_at': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    await ZyiarahAuditService().logAction(
      action: 'APPLY_PRICES_ALL_ZONES',
      details: {'zones': snap.size, ...priceFields},
      targetId: 'service_zones',
    );
    return snap.size;
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

    int rank = data?['rank'] ?? 0;
    GeoPoint? selectedGeo = data?['centerLoc'] as GeoPoint?;
    bool isSaving = false;

    // جدول فتح المنطقة — يبنيه المحرّر ويُكتب على المستند. null قبل أي تعديل =
    // نُبقي القيمة الحالية كما هي (لا نكتب schedule إن لم يُلمَس).
    Map<String, dynamic>? scheduleData = data?['schedule'] as Map<String, dynamic>?;

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
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isSaving) const Padding(padding: EdgeInsets.only(bottom: 15), child: LinearProgressIndicator(color: Color(0xFF1E293B))),

                    TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'اسم المنطقة (مثلاً: شمال الرياض)', border: OutlineInputBorder())),
                    const SizedBox(height: 15),
                    
                    // Map Selection
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
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.blue.shade200)),
                        child: Row(
                          children: [
                            const Icon(Icons.map_outlined, color: Colors.blue),
                            const SizedBox(width: 8),
                            Expanded(child: Text(selectedGeo == null ? "اضغط لتحديد مركز المنطقة من الخريطة" : "تم تحديد الإحداثيات بنجاح ✅", style: TextStyle(fontSize: 12, color: Colors.blue.shade900))),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 15),

                    TextField(
                      controller: radiusCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'نصف القطر للتغطية (كم)', border: OutlineInputBorder()),
                      // إعادة الرسم عند كل تغيير كي تتحدث دائرة التغطية في المعاينة حيّاً.
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 12),

                    // معاينة حيّة لنطاق التغطية: تُظهر للإدارة ما الذي يغطيه نصف القطر فعلاً
                    // على الخريطة قبل الحفظ — وتتحدث فور تغيير الرقم أو المركز.
                    if (selectedGeo != null)
                      _ZoneCoveragePreview(
                        center: selectedGeo!,
                        radiusKm: double.tryParse(radiusCtrl.text) ?? 15.0,
                      ),
                    if (selectedGeo != null) const SizedBox(height: 15),

                    const Divider(height: 30),
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
              actions: [
                // تعميم الأسعار: يقرأ حقول الأسعار المُدخلة الآن ويكتبها لكل المناطق —
                // بتأكيد صريح، لأنه استبدال جماعي لا رجعة فيه بضغطة.
                TextButton.icon(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final confirmed = await showDialog<bool>(
                            context: ctx,
                            builder: (c2) => Directionality(
                              textDirection: TextDirection.rtl,
                              child: AlertDialog(
                                title: const Text('تطبيق على كل المناطق؟'),
                                content: const Text(
                                    'ستُستبدل أسعار الساعات والكنب والسجاد والمكيفات في كل المناطق '
                                    'بالأسعار المُدخلة هنا.\n(الأسماء والمواقع والجداول لا تتأثر.)'),
                                actions: [
                                  TextButton(
                                      onPressed: () => Navigator.pop(c2, false),
                                      child: const Text('إلغاء')),
                                  ElevatedButton(
                                      onPressed: () => Navigator.pop(c2, true),
                                      child: const Text('نعم، طبّق')),
                                ],
                              ),
                            ),
                          );
                          if (confirmed != true) return;
                          setDialogState(() => isSaving = true);
                          try {
                            final n = await _applyPricesToAllZones({
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
                                  content: Text('طُبّقت الأسعار على $n منطقة ✅'),
                                  backgroundColor: Colors.green));
                            }
                          } catch (e) {
                            setDialogState(() => isSaving = false);
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                  content: Text('تعذّر التعميم: $e'),
                                  backgroundColor: Colors.red));
                            }
                          }
                        },
                  icon: const Icon(Icons.copy_all_rounded, size: 18),
                  label: const Text('تطبيق على كل المناطق'),
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
  final GeoPoint center;
  final double radiusKm;

  const _ZoneCoveragePreview({required this.center, required this.radiusKm});

  @override
  Widget build(BuildContext context) {
    final token = dotenv.env['MAPBOX_TOKEN'] ?? '';
    final latLng = LatLng(center.latitude, center.longitude);
    // كل تغيير في نصف القطر يعيد بناء الخريطة بمفتاح جديد فتُعاد المركزة بالزوم المناسب.
    final zoom = _zoomForRadius(radiusKm);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.travel_explore_rounded, size: 16, color: Colors.blue),
            const SizedBox(width: 6),
            Text(
              'نطاق التغطية — ${radiusKm.toStringAsFixed(radiusKm % 1 == 0 ? 0 : 1)} كم',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue),
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
                  key: ValueKey('zone_preview_${center.latitude}_${center.longitude}_$radiusKm'),
                  options: MapOptions(
                    initialCenter: latLng,
                    initialZoom: zoom,
                    // معاينة فقط — لا تفاعل كي لا تبتلع تمرير النافذة.
                    interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/{z}/{x}/{y}?access_token=$token',
                      additionalOptions: {'accessToken': token},
                      userAgentPackageName: 'com.zyiarah.zyiarah',
                    ),
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
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: latLng,
                          child: const Icon(Icons.location_on, color: Color(0xFF50B498), size: 34),
                        ),
                      ],
                    ),
                  ],
                ),
                // تعذّر تحميل الخريطة (توكن مفقود مثلاً) لا يترك مربعاً أسود غامضاً.
                if (token.isEmpty)
                  Container(
                    color: Colors.grey.shade200,
                    alignment: Alignment.center,
                    child: const Text('تعذّر عرض الخريطة (رمز Mapbox غير مضبوط)',
                        style: TextStyle(fontSize: 11, color: Colors.grey)),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// زوم يجعل الدائرة كاملةً ظاهرة في المعاينة مهما كان نصف القطر.
  static double _zoomForRadius(double km) {
    if (km <= 2) return 12.5;
    if (km <= 5) return 11.3;
    if (km <= 10) return 10.3;
    if (km <= 20) return 9.3;
    if (km <= 40) return 8.3;
    return 7.3;
  }
}
