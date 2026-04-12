import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:zyiarah/screens/location_picker_screen.dart';

class AdminHourlyZonesScreen extends StatefulWidget {
  const AdminHourlyZonesScreen({super.key});

  @override
  State<AdminHourlyZonesScreen> createState() => _AdminHourlyZonesScreenState();
}

class _AdminHourlyZonesScreenState extends State<AdminHourlyZonesScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  bool _isLoading = true;
  List<QueryDocumentSnapshot> _zones = [];

  @override
  void initState() {
    super.initState();
    _fetchZones();
  }

  Future<void> _fetchZones() async {
    try {
      final snapshot = await _db.collection('hourly_zones').orderBy('rank').get();
      if (mounted) {
        setState(() {
          _zones = snapshot.docs;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showZoneDialog({DocumentSnapshot? doc}) {
    final Map<String, dynamic>? data = doc?.data() as Map<String, dynamic>?;

    final nameCtrl = TextEditingController(text: data?['name'] ?? '');
    final radiusCtrl = TextEditingController(text: data?['radiusKm']?.toString() ?? '15');
    
    // Hourly Prices
    final p1Ctrl = TextEditingController(text: data?['prices']?['1']?.toString() ?? '');
    final p4Ctrl = TextEditingController(text: data?['prices']?['4']?.toString() ?? '');
    final p5Ctrl = TextEditingController(text: data?['prices']?['5']?.toString() ?? '');
    final p6Ctrl = TextEditingController(text: data?['prices']?['6']?.toString() ?? '');
    final p8Ctrl = TextEditingController(text: data?['prices']?['8']?.toString() ?? '');

    // Sofa & Rug Prices for this zone
    final pSofaCtrl = TextEditingController(text: data?['sofaPrice']?.toString() ?? '35');
    final pRugCtrl = TextEditingController(text: data?['rugPrice']?.toString() ?? '15');

    int rank = data?['rank'] ?? (_zones.length + 1);
    GeoPoint? selectedGeo = data?['centerLoc'] as GeoPoint?;
    bool isSaving = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                title: Text(doc == null ? 'إضافة منطقة جديدة للمنصة' : 'تعديل المنطقة', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (isSaving)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 20),
                          child: LinearProgressIndicator(color: Color(0xFF1E293B)),
                        ),
                      TextField(controller: nameCtrl, enabled: !isSaving, decoration: const InputDecoration(labelText: 'اسم المنطقة الرئيسي (مثل: داخل الداير)', border: OutlineInputBorder())),
                      const SizedBox(height: 15),
                      
                      // Map Center Selection
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.location_on, color: Colors.blue),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    selectedGeo == null 
                                      ? "يجب تحديد موقع نقطة مركز المنطقة من الخريطة" 
                                      : "تم التحديد: (${selectedGeo!.latitude.toStringAsFixed(4)}, ${selectedGeo!.longitude.toStringAsFixed(4)})",
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: selectedGeo == null ? Colors.red : Colors.green),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            ElevatedButton.icon(
                              onPressed: isSaving ? null : () async {
                                final geo = await Navigator.push(
                                  context, 
                                  MaterialPageRoute(builder: (_) => const LocationPickerScreen(serviceName: "تحديد مركز المنطقة"))
                                );
                                if (geo != null && geo is GeoPoint) {
                                  setDialogState(() {
                                    selectedGeo = geo;
                                  });
                                }
                              },
                              icon: const Icon(Icons.map),
                              label: const Text("التقاط من الخريطة"),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 15),
                      TextField(
                        controller: radiusCtrl, 
                        enabled: !isSaving,
                        keyboardType: TextInputType.number, 
                        decoration: const InputDecoration(labelText: 'نصف القطر المدعوم (كم)', helperText: 'المسافة التي يغطيها المركز (مثال: 15)', border: OutlineInputBorder()),
                      ),
                      
                      const Divider(height: 30),
                      Text('أسعار باقات التنظيف بالساعة (ر.س):', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(child: TextField(controller: p1Ctrl, enabled: !isSaving, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '1 ساعة', border: OutlineInputBorder()))),
                          const SizedBox(width: 10),
                          Expanded(child: TextField(controller: p4Ctrl, enabled: !isSaving, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '4 ساعات', border: OutlineInputBorder()))),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(child: TextField(controller: p5Ctrl, enabled: !isSaving, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '5 ساعات', border: OutlineInputBorder()))),
                          const SizedBox(width: 10),
                          Expanded(child: TextField(controller: p6Ctrl, enabled: !isSaving, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '6 ساعات', border: OutlineInputBorder()))),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextField(controller: p8Ctrl, enabled: !isSaving, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '8 ساعات', border: OutlineInputBorder())),
                      
                      const Divider(height: 30),
                      Text('أسعار خدمة التنظيف العميق (ر.س):', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(child: TextField(controller: pSofaCtrl, enabled: !isSaving, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'متر الكنب', border: OutlineInputBorder()))),
                          const SizedBox(width: 10),
                          Expanded(child: TextField(controller: pRugCtrl, enabled: !isSaving, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'متر الزل', border: OutlineInputBorder()))),
                        ],
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text('إلغاء', style: GoogleFonts.tajawal(color: Colors.grey)),
                  ),
                  ElevatedButton(
                    onPressed: isSaving ? null : () async {
                      if (nameCtrl.text.isEmpty || selectedGeo == null) {
                         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('الرجاء كتابة الاسم وتحديد نقطة المركز')));
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
                          'sofaPrice': double.tryParse(pSofaCtrl.text) ?? 35,
                          'rugPrice': double.tryParse(pRugCtrl.text) ?? 15,
                          'rank': rank,
                          'updated_at': FieldValue.serverTimestamp(),
                        };

                        if (doc == null) {
                          await _db.collection('hourly_zones').add(newData);
                        } else {
                          await _db.collection('hourly_zones').doc(doc.id).update(newData);
                        }

                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("تم حفظ المنطقة والأسعار بنجاح ✅")));
                          _fetchZones();
                        }
                      } catch (e) {
                         setDialogState(() => isSaving = false);
                         if (ctx.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("خطأ في الحفظ: $e")));
                      }
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E293B)),
                    child: Text(isSaving ? "جاري الحفظ..." : "حفظ المنطقة", style: GoogleFonts.tajawal(color: Colors.white)),
                  ),
                ],
              ),
            );
          }
        );
      },
    );
  }

  Future<void> _deleteZone(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('حذف المنطقة'),
          content: const Text('هل أنت متأكد من حذف هذه المنطقة نهائياً؟'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true), 
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('حذف', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );

    if (confirm == true) {
      try {
        await _db.collection('hourly_zones').doc(id).delete();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("تم حذف المنطقة بنجاح")));
        _fetchZones();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("فشل الحذف الجذري: $e")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text('إدارة وخرائط المناطق (النطاقات الجغرافية)', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _zones.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.map_outlined, size: 80, color: Colors.grey),
                    const SizedBox(height: 20),
                    Text('الرجاء إضافة مناطق التغطية من الخريطة الان', style: GoogleFonts.tajawal(fontSize: 18, color: Colors.grey[600])),
                  ],
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(20),
                itemCount: _zones.length,
                itemBuilder: (context, index) {
                  final doc = _zones[index];
                  final data = doc.data() as Map<String, dynamic>;
                  final prices = data['prices'] as Map<String, dynamic>? ?? {};

                  return Card(
                    margin: const EdgeInsets.only(bottom: 20),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    elevation: 3,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  data['name'] ?? '', 
                                  style: GoogleFonts.tajawal(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue[900]),
                                ),
                              ),
                              Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit, color: Colors.blue),
                                    onPressed: () => _showZoneDialog(doc: doc),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.red),
                                    onPressed: () => _deleteZone(doc.id),
                                  ),
                                ],
                              )
                            ],
                          ),
                          Text('نصف القطر المغطى للمركز: ${data['radiusKm'] ?? 15} كم', style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
                          const Divider(height: 30),
                          Wrap(
                            spacing: 15,
                            runSpacing: 10,
                            children: [
                              _priceBadge('1 ساعة', prices['1']?.toString() ?? '0', Colors.blue),
                              _priceBadge('4 ساعات', prices['4']?.toString() ?? '0', Colors.blue),
                              _priceBadge('5 ساعات', prices['5']?.toString() ?? '0', Colors.blue),
                              _priceBadge('6 ساعات', prices['6']?.toString() ?? '0', Colors.blue),
                              _priceBadge('8 ساعات', prices['8']?.toString() ?? '0', Colors.blue),
                            ],
                          ),
                          const SizedBox(height: 15),
                          Wrap(
                            spacing: 15,
                            runSpacing: 10,
                            children: [
                              _priceBadge('متر الكنب', data['sofaPrice']?.toString() ?? '0', Colors.purple),
                              _priceBadge('متر الزل', data['rugPrice']?.toString() ?? '0', Colors.purple),
                            ],
                          )
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showZoneDialog(),
        backgroundColor: Colors.blueAccent,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _priceBadge(String label, String price, Color color) {
    if (price == '0' || price == '0.0') return const SizedBox.shrink(); // hide 0
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade800, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text('$price ر.س', style: TextStyle(fontSize: 15, color: color, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}
