import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AdminSettingsScreen extends StatefulWidget {
  const AdminSettingsScreen({super.key});

  @override
  State<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends State<AdminSettingsScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  
  bool _isLoading = true;
  bool _isSaving = false;

  final TextEditingController _sofaInsideCtrl = TextEditingController();
  final TextEditingController _sofaOutsideCtrl = TextEditingController();
  final TextEditingController _rugInsideCtrl = TextEditingController();
  final TextEditingController _rugOutsideCtrl = TextEditingController();
  final TextEditingController _depositCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchPricing();
  }

  Future<void> _fetchPricing() async {
    try {
      final doc = await _db.collection('system_configs').doc('main_settings').get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        setState(() {
          _sofaInsideCtrl.text = (data['sofa_price_inside'] ?? 35).toString();
          _sofaOutsideCtrl.text = (data['sofa_price_outside'] ?? 39).toString();
          _rugInsideCtrl.text = (data['rug_price_inside'] ?? 15).toString();
          _rugOutsideCtrl.text = (data['rug_price_outside'] ?? 17).toString();
          _depositCtrl.text = (data['outside_deposit'] ?? 50).toString();
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _savePricing() async {
    setState(() => _isSaving = true);
    try {
      await _db.collection('system_configs').doc('main_settings').set({
        'sofa_price_inside': double.tryParse(_sofaInsideCtrl.text) ?? 35,
        'sofa_price_outside': double.tryParse(_sofaOutsideCtrl.text) ?? 39,
        'rug_price_inside': double.tryParse(_rugInsideCtrl.text) ?? 15,
        'rug_price_outside': double.tryParse(_rugOutsideCtrl.text) ?? 17,
        'outside_deposit': double.tryParse(_depositCtrl.text) ?? 50,
      }, SetOptions(merge: true));
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("تم حفظ تسعيرة الكنب والزل بنجاح!", style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("حدث خطأ أثناء الحفظ")));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  void dispose() {
    _sofaInsideCtrl.dispose();
    _sofaOutsideCtrl.dispose();
    _rugInsideCtrl.dispose();
    _rugOutsideCtrl.dispose();
    _depositCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text("إعدادات التسعير المرنة", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
              const SizedBox(height: 5),
              const Text("تحكم مباشر بأسعار الكنب والزل بالمتر وعربون المناطق الخارجية.", style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 24),
              
              Card(
                elevation: 3,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("أسعار الكنب", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF5D1B5E))),
                      const Divider(),
                      _buildNumField("للمتر داخل الداير (ر.س)", _sofaInsideCtrl),
                      const SizedBox(height: 12),
                      _buildNumField("للمتر خارج الداير (ر.س)", _sofaOutsideCtrl),
                      
                      const SizedBox(height: 24),
                      const Text("أسعار الزل (السجاد)", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF5D1B5E))),
                      const Divider(),
                      _buildNumField("للمتر داخل الداير (ر.س)", _rugInsideCtrl),
                      const SizedBox(height: 12),
                      _buildNumField("للمتر خارج الداير (ر.س)", _rugOutsideCtrl),

                      const SizedBox(height: 24),
                      const Text("شروط الحجز", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF5D1B5E))),
                      const Divider(),
                      _buildNumField("التأمين / العربون لخارج الداير (ر.س)", _depositCtrl),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 30),
              SizedBox(
                height: 55,
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _savePricing,
                  icon: _isSaving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.save),
                  label: const Text("حفظ التسعيرة الحالية", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
    );
  }

  Widget _buildNumField(String label, TextEditingController controller) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
        filled: true,
        fillColor: Colors.grey[50],
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.grey)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.3))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF2563EB), width: 2)),
      ),
    );
  }
}
