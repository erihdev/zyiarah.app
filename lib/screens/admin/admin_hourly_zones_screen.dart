import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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

  Future<void> _initializeDefaultZones() async {
    setState(() => _isLoading = true);
    
    final defaults = [
      {
        'name': 'داخل الداير - العيدابي',
        'subAreas': [],
        'prices': {'4': 200, '5': 240, '6': 260, '8': 280},
        'rank': 1,
      },
      {
        'name': 'فيفا - جبال فيفا والعارضة',
        'subAreas': ["فيفا", "جبل خاشر", "جبال الحشر", "عثوان", "المشاف"],
        'prices': {'4': 300, '5': 355, '6': 410, '8': 465},
        'rank': 2,
      },
      {
        'name': 'مناطق أخرى (الجوه، عيبان، الخ)',
        'subAreas': ["ريع", "الجوه", "عيبان", "العشبة", "القاع", "المشوف", "الطلعه", "اسكان حرس الحدود", "صدر جورا", "حي الاسكان"],
        'prices': {'4': 260, '5': 305, '6': 350, '8': 460},
        'rank': 3,
      }
    ];

    for (var z in defaults) {
      await _db.collection('hourly_zones').add(z);
    }

    _fetchZones();
  }

  void _showZoneDialog({DocumentSnapshot? doc}) {
    final Map<String, dynamic>? data = doc?.data() as Map<String, dynamic>?;

    final nameCtrl = TextEditingController(text: data?['name'] ?? '');
    final subAreasCtrl = TextEditingController(text: (data?['subAreas'] as List<dynamic>?)?.join('، ') ?? '');
    
    final p4Ctrl = TextEditingController(text: data?['prices']?['4']?.toString() ?? '');
    final p5Ctrl = TextEditingController(text: data?['prices']?['5']?.toString() ?? '');
    final p6Ctrl = TextEditingController(text: data?['prices']?['6']?.toString() ?? '');
    final p8Ctrl = TextEditingController(text: data?['prices']?['8']?.toString() ?? '');

    int rank = data?['rank'] ?? (_zones.length + 1);

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                title: Text(doc == null ? 'إضافة منطقة جديدة' : 'تعديل المنطقة', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'اسم المنطقة الرئيسي (مثل: داخل الداير)')),
                      const SizedBox(height: 10),
                      TextField(
                        controller: subAreasCtrl, 
                        maxLines: 2, 
                        decoration: const InputDecoration(labelText: 'الأحياء التابعة (افصل بينها بفاصلة ،)', hintText: 'حي 1، حي 2، حي 3'),
                      ),
                      const SizedBox(height: 15),
                      const Text('أسعار الساعات الأساسية:', style: TextStyle(fontWeight: FontWeight.bold)),
                      Row(
                        children: [
                          Expanded(child: TextField(controller: p4Ctrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '4 ساعات'))),
                          const SizedBox(width: 10),
                          Expanded(child: TextField(controller: p5Ctrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '5 ساعات'))),
                        ],
                      ),
                      Row(
                        children: [
                          Expanded(child: TextField(controller: p6Ctrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '6 ساعات'))),
                          const SizedBox(width: 10),
                          Expanded(child: TextField(controller: p8Ctrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '8 ساعات'))),
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
                    onPressed: () async {
                      if (nameCtrl.text.isEmpty) return;
                      
                      final newData = {
                        'name': nameCtrl.text.trim(),
                        'subAreas': subAreasCtrl.text.split('،').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
                        'prices': {
                          '4': double.tryParse(p4Ctrl.text) ?? 0,
                          '5': double.tryParse(p5Ctrl.text) ?? 0,
                          '6': double.tryParse(p6Ctrl.text) ?? 0,
                          '8': double.tryParse(p8Ctrl.text) ?? 0,
                        },
                        'rank': rank,
                      };

                      if (doc == null) {
                        await _db.collection('hourly_zones').add(newData);
                      } else {
                        await _db.collection('hourly_zones').doc(doc.id).update(newData);
                      }

                      if (context.mounted) {
                        Navigator.pop(ctx);
                        _fetchZones();
                      }
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                    child: Text('حفظ', style: GoogleFonts.tajawal(color: Colors.white)),
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
      await _db.collection('hourly_zones').doc(id).delete();
      _fetchZones();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text('إدارة مناطق التنظيف (بالساعة)', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
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
                    Text('لا توجد مناطق متاحة حالياً', style: GoogleFonts.tajawal(fontSize: 18, color: Colors.grey[600])),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: _initializeDefaultZones,
                      icon: const Icon(Icons.download),
                      label: Text('تحميل المناطق الافتراضية', style: GoogleFonts.tajawal()),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white),
                    )
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
                          if ((data['subAreas'] as List?)?.isNotEmpty ?? false)
                            Text(
                              (data['subAreas'] as List).join('، '), 
                              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                            ),
                          const Divider(height: 30),
                          Wrap(
                            spacing: 15,
                            runSpacing: 10,
                            children: [
                              _priceBadge('4 ساعات', prices['4']?.toString() ?? '0'),
                              _priceBadge('5 ساعات', prices['5']?.toString() ?? '0'),
                              _priceBadge('6 ساعات', prices['6']?.toString() ?? '0'),
                              _priceBadge('8 ساعات', prices['8']?.toString() ?? '0'),
                            ],
                          ),
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

  Widget _priceBadge(String label, String price) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.blueGrey, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text('$price ر.س', style: const TextStyle(fontSize: 15, color: Colors.blue, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}
