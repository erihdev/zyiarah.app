import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AdminSubscriptionsScreen extends StatefulWidget {
  const AdminSubscriptionsScreen({super.key});

  @override
  State<AdminSubscriptionsScreen> createState() => _AdminSubscriptionsScreenState();
}

class _AdminSubscriptionsScreenState extends State<AdminSubscriptionsScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  bool _isLoading = true;
  List<QueryDocumentSnapshot> _packages = [];

  @override
  void initState() {
    super.initState();
    _fetchPackages();
  }

  Future<void> _fetchPackages() async {
    try {
      final snapshot = await _db.collection('subscription_packages').orderBy('rank').get();
      if (mounted) {
        setState(() {
          _packages = snapshot.docs;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _initializeDefaultPackages() async {
    setState(() => _isLoading = true);
    
    final defaults = [
      {
        'title': 'الباقة اليومية',
        'subtitle': 'زيارة واحدة في اليوم المختار',
        'price': '99',
        'features': ['تنظيف شامل لمدة 4 ساعات', 'تشمل جميع الأدوات', 'مقدمة خدمة واحدة'],
        'isPremium': false,
        'rank': 1,
      },
      {
        'title': 'الباقة الأسبوعية',
        'subtitle': 'زيارة واحدة اسبوعياً (4 زيارات)',
        'price': '349',
        'features': ['توفير 15%', 'تحديد موعد ثابت أسبوعياً', 'خصومات على الخدمات الإضافية'],
        'isPremium': false,
        'rank': 2,
      },
      {
        'title': 'الباقة الشهرية (جولد)',
        'subtitle': 'زيارتين اسبوعياً (8 زيارات)',
        'price': '649',
        'features': ['توفير 25%', 'مقدمة خدمة ثابتة ومفضلة', 'أولوية في الحجز', 'عقد إلكتروني موثق'],
        'isPremium': true,
        'rank': 3,
      }
    ];

    try {
      for (var pkg in defaults) {
        await _db.collection('subscription_packages').add(pkg);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تحميل الباقات الافتراضية بنجاح')));
      }
      _fetchPackages();
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading defaults: $e')));
      }
    } finally {
       // _fetchPackages will set it to false, but if it wasn't called:
       // setState(() => _isLoading = false);
    }
  }

  void _showPackageDialog({DocumentSnapshot? package}) {
    final titleCtrl = TextEditingController(text: package?['title'] ?? '');
    final subtitleCtrl = TextEditingController(text: package?['subtitle'] ?? '');
    final priceCtrl = TextEditingController(text: package?['price'] ?? '');
    final featuresCtrl = TextEditingController(text: (package?['features'] as List<dynamic>?)?.join('\n') ?? '');
    bool isPremium = package?['isPremium'] ?? false;
    int rank = package?['rank'] ?? (_packages.length + 1);
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                title: Text(package == null ? 'إضافة باقة جديدة' : 'تعديل الباقة', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isSaving)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 20),
                          child: LinearProgressIndicator(color: Color(0xFF1E293B)),
                        ),
                      TextField(controller: titleCtrl, enabled: !isSaving, decoration: const InputDecoration(labelText: 'اسم الباقة', border: OutlineInputBorder())),
                      const SizedBox(height: 15),
                      TextField(controller: subtitleCtrl, enabled: !isSaving, decoration: const InputDecoration(labelText: 'العنوان الفرعي/الوصف', border: OutlineInputBorder())),
                      const SizedBox(height: 15),
                      TextField(controller: priceCtrl, enabled: !isSaving, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'السعر (ر.س)', border: OutlineInputBorder())),
                      const SizedBox(height: 15),
                      TextField(
                        controller: featuresCtrl, 
                        enabled: !isSaving,
                        maxLines: 4, 
                        decoration: const InputDecoration(labelText: 'الميزات (ميزة في كل سطر)', hintText: 'مثال:\nتنظيف شامل\nتوفير 15%', border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Checkbox(
                            value: isPremium,
                            onChanged: isSaving ? null : (val) => setDialogState(() => isPremium = val ?? false),
                          ),
                          const Text('باقة مميزة (ذهبية)؟'),
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
                      if (titleCtrl.text.isEmpty || priceCtrl.text.isEmpty) {
                         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("يرجى إدخال مسمى الباقة وسعرها")));
                         return;
                      }
                      
                      setDialogState(() => isSaving = true);
                      try {
                        final data = {
                          'title': titleCtrl.text.trim(),
                          'subtitle': subtitleCtrl.text.trim(),
                          'price': priceCtrl.text.trim(),
                          'features': featuresCtrl.text.trim().split('\n').where((s) => s.isNotEmpty).toList(),
                          'isPremium': isPremium,
                          'rank': rank,
                          'updated_at': FieldValue.serverTimestamp(),
                        };

                        if (package == null) {
                          await _db.collection('subscription_packages').add(data);
                        } else {
                          await _db.collection('subscription_packages').doc(package.id).update(data);
                        }

                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("تم حفظ الباقة بنجاح ✅")));
                          _fetchPackages();
                        }
                      } catch (e) {
                         setDialogState(() => isSaving = false);
                         if (ctx.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("خطأ في الحفظ: $e")));
                      }
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E293B)),
                    child: Text(isSaving ? "جاري الحفظ..." : "حفظ الباقة", style: GoogleFonts.tajawal(color: Colors.white)),
                  ),
                ],
              ),
            );
          }
        );
      },
    );
  }

  Future<void> _deletePackage(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تأكيد الحذف'),
          content: const Text('هل أنت متأكد من حذف هذه الباقة؟'),
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
        await _db.collection('subscription_packages').doc(id).delete();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("تم حذف الباقة بنجاح")));
        _fetchPackages();
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
        title: Text('إدارة باقات الاشتراك', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF5D1B5E),
        foregroundColor: Colors.white,
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _packages.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.inventory_2_outlined, size: 80, color: Colors.grey),
                    const SizedBox(height: 20),
                    Text('لا توجد باقات حالياً', style: GoogleFonts.tajawal(fontSize: 18, color: Colors.grey[600])),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: _initializeDefaultPackages,
                      icon: const Icon(Icons.download),
                      label: Text('تحميل الباقات الافتراضية', style: GoogleFonts.tajawal()),
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF5D1B5E), foregroundColor: Colors.white),
                    )
                  ],
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(20),
                itemCount: _packages.length,
                itemBuilder: (context, index) {
                  final pkg = _packages[index];
                  final data = pkg.data() as Map<String, dynamic>;
                  final features = (data['features'] as List<dynamic>?) ?? [];
                  
                  return Card(
                    margin: const EdgeInsets.only(bottom: 20),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(color: data['isPremium'] == true ? Colors.amber : Colors.transparent, width: 2),
                    ),
                    elevation: 5,
                    shadowColor: Colors.black.withValues(alpha: 0.1),
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
                                  data['title'] ?? '', 
                                  style: GoogleFonts.tajawal(fontSize: 20, fontWeight: FontWeight.bold, color: const Color(0xFF5D1B5E)),
                                ),
                              ),
                              Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit, color: Colors.blue),
                                    onPressed: () => _showPackageDialog(package: pkg),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.red),
                                    onPressed: () => _deletePackage(pkg.id),
                                  ),
                                ],
                              )
                            ],
                          ),
                          Text(data['subtitle'] ?? '', style: GoogleFonts.tajawal(fontSize: 14, color: Colors.grey[600])),
                          const SizedBox(height: 10),
                          Text('${data['price']} ر.س', style: GoogleFonts.tajawal(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black)),
                          const Divider(height: 30),
                          ...features.map((f) => Padding(
                            padding: const EdgeInsets.only(bottom: 5),
                            child: Row(
                              children: [
                                Icon(Icons.check_circle, size: 16, color: data['isPremium'] == true ? Colors.amber : const Color(0xFF5D1B5E)),
                                const SizedBox(width: 8),
                                Expanded(child: Text(f.toString(), style: GoogleFonts.tajawal(fontSize: 13))),
                              ],
                            ),
                          )),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showPackageDialog(),
        backgroundColor: const Color(0xFF5D1B5E),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}
