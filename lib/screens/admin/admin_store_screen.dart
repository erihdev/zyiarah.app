import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:zyiarah/services/store_service.dart';

class AdminStoreScreen extends StatefulWidget {
  const AdminStoreScreen({super.key});

  @override
  State<AdminStoreScreen> createState() => _AdminStoreScreenState();
}

class _AdminStoreScreenState extends State<AdminStoreScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final ZyiarahStoreService _storeService = ZyiarahStoreService();
  bool _isSeeding = false;

  void _seedProducts() async {
    setState(() => _isSeeding = true);
    try {
      await _storeService.seedInitialProducts();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("تم استيراد منتجات سويفت كلين بنجاح!", style: GoogleFonts.tajawal()), backgroundColor: Colors.green),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("حدث خطأ أثناء الاستيراد.", style: GoogleFonts.tajawal()), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isSeeding = false);
    }
  }

  void _toggleProductVisibility(DocumentSnapshot doc) async {
    final isHidden = doc['is_hidden'] ?? false;
    await _db.collection('products').doc(doc.id).update({'is_hidden': !isHidden});
  }

  void _showEditPriceDialog(DocumentSnapshot doc) {
    final currentPrice = (doc['price'] ?? 0).toString();
    TextEditingController priceCtrl = TextEditingController(text: currentPrice);

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text("تعديل السعر", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: priceCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: "السعر الجديد (ر.س)",
            labelStyle: GoogleFonts.tajawal(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("إلغاء", style: GoogleFonts.tajawal()),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF5D1B5E), foregroundColor: Colors.white),
            onPressed: () async {
              try {
                await _db.collection('products').doc(doc.id).update({
                  'price': double.tryParse(priceCtrl.text) ?? double.parse(currentPrice),
                });
                if (dialogCtx.mounted) Navigator.pop(dialogCtx);
              } catch (e) {
                debugPrint('Error updating price: $e');
              }
            },
            child: Text("حفظ", style: GoogleFonts.tajawal()),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text("إدارة المتجر", style: GoogleFonts.tajawal(color: Colors.white, fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFF5D1B5E),
          actions: [
            IconButton(
              icon: _isSeeding ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.cloud_download, color: Colors.white),
              onPressed: _isSeeding ? null : () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text("استيراد منتجات سويفت كلين", style: GoogleFonts.tajawal()),
                    content: Text("هل تريد تحميل قائمة المنتجات والأسعار الافتراضية إلى قاعدة البيانات؟", style: GoogleFonts.tajawal()),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context), child: Text("إلغاء", style: GoogleFonts.tajawal())),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _seedProducts();
                        },
                        child: Text("بدء الاستيراد", style: GoogleFonts.tajawal()),
                      ),
                    ],
                  ),
                );
              },
              tooltip: "استيراد منتجات سويفت كلين",
            )
          ],
        ),
        body: StreamBuilder<QuerySnapshot>(
          stream: _db.collection('products').orderBy('created_at', descending: true).snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final docs = snapshot.data?.docs ?? [];
            if (docs.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.store_mall_directory, size: 80, color: Colors.grey[300]),
                    const SizedBox(height: 20),
                    Text("لا توجد أي منتجات في المتجر", style: GoogleFonts.tajawal(fontSize: 18, color: Colors.grey)),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: _isSeeding ? null : _seedProducts,
                      icon: const Icon(Icons.download),
                      label: Text("استيراد منتجات سويفت كلين", style: GoogleFonts.tajawal()),
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF5D1B5E), foregroundColor: Colors.white),
                    )
                  ],
                ),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: docs.length,
              itemBuilder: (context, index) {
                final doc = docs[index];
                final data = doc.data() as Map<String, dynamic>;
                final isHidden = data['is_hidden'] ?? false;
                
                return Card(
                  elevation: 2,
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        data['image_url'] ?? '',
                        width: 50,
                        height: 50,
                        fit: BoxFit.cover,
                        errorBuilder: (c, e, s) => Container(width: 50, height: 50, color: Colors.grey[200], child: const Icon(Icons.image)),
                      ),
                    ),
                    title: Text(data['name'] ?? 'بدون اسم', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text("${data['price']} ر.س", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 13)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.blueGrey, size: 20),
                          onPressed: () => _showEditPriceDialog(doc),
                        ),
                        Switch(
                          value: !isHidden,
                          onChanged: (val) => _toggleProductVisibility(doc),
                          activeThumbColor: Colors.green,
                          inactiveThumbColor: Colors.red,
                        ),
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
