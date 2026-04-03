import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'dart:ui';

class AdminSettingsScreen extends StatefulWidget {
  const AdminSettingsScreen({super.key});

  @override
  State<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends State<AdminSettingsScreen> with SingleTickerProviderStateMixin {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  
  bool _isLoading = true;
  bool _isSaving = false;
  late AnimationController _fadeController;

  final TextEditingController _sofaInsideCtrl = TextEditingController();
  final TextEditingController _sofaOutsideCtrl = TextEditingController();
  final TextEditingController _rugInsideCtrl = TextEditingController();
  final TextEditingController _rugOutsideCtrl = TextEditingController();
  final TextEditingController _depositCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _fetchPricing();
  }

  Future<void> _fetchPricing() async {
    try {
      final doc = await _db.collection('system_configs').doc('main_settings').get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        if (mounted) {
          setState(() {
            _sofaInsideCtrl.text = (data['sofa_price_inside'] ?? 35).toString();
            _sofaOutsideCtrl.text = (data['sofa_price_outside'] ?? 39).toString();
            _rugInsideCtrl.text = (data['rug_price_inside'] ?? 15).toString();
            _rugOutsideCtrl.text = (data['rug_price_outside'] ?? 17).toString();
            _depositCtrl.text = (data['outside_deposit'] ?? 50).toString();
            _isLoading = false;
          });
          _fadeController.forward();
        }
      } else {
        if (mounted) {
          setState(() => _isLoading = false);
          _fadeController.forward();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _fadeController.forward();
      }
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
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 10),
              Text("تم حفظ التسعيرة بنجاح!", style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          backgroundColor: Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text("حدث خطأ أثناء الحفظ"),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
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
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: _isLoading 
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF6366F1)))
          : Stack(
              children: [
                // Top decorative background
                Positioned(
                  top: -100,
                  right: -50,
                  child: Container(
                    width: 300,
                    height: 300,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF6366F1).withValues(alpha: 0.15),
                          const Color(0xFF8B5CF6).withValues(alpha: 0.0),
                        ],
                        begin: Alignment.topRight,
                        end: Alignment.bottomLeft,
                      ),
                    ),
                  ),
                ),
                
                FadeTransition(
                  opacity: _fadeController,
                  child: ListView(
                    padding: const EdgeInsets.only(top: 40, left: 24, right: 24, bottom: 40),
                    children: [
                      // Header
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                                  blurRadius: 20,
                                  offset: const Offset(0, 10),
                                )
                              ],
                            ),
                            child: const Icon(Icons.settings_suggest_rounded, color: Color(0xFF6366F1), size: 32),
                          ),
                          const SizedBox(width: 16),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "إعدادات التسعير المرنة",
                                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF1E293B), letterSpacing: -0.5),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  "تحكم بأسعار التنظيف وعربون الحجز الداخلي والخارجي.",
                                  style: TextStyle(fontSize: 13, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 32),
                      
                      // Sofa Pricing Card
                      _buildSectionCard(
                        title: "أسعار غسيل الكنب (بالمتر)",
                        icon: Icons.chair_rounded,
                        color: const Color(0xFF3B82F6),
                        children: [
                          _buildPremiumField("داخل الداير (منطقة الرياض التلقائية)", "ر.س", _sofaInsideCtrl, Icons.location_inner_rounded),
                          const SizedBox(height: 16),
                          _buildPremiumField("خارج الداير (المناطق البعيدة)", "ر.س", _sofaOutsideCtrl, Icons.location_off_rounded),
                        ],
                      ),
                      
                      const SizedBox(height: 24),
                      
                      // Rug Pricing Card
                      _buildSectionCard(
                        title: "أسعار غسيل الزل والسجاد (بالمتر)",
                        icon: Icons.grid_view_rounded,
                        color: const Color(0xFFF59E0B),
                        children: [
                          _buildPremiumField("داخل الداير (منطقة الرياض التلقائية)", "ر.س", _rugInsideCtrl, Icons.location_inner_rounded),
                          const SizedBox(height: 16),
                          _buildPremiumField("خارج الداير (المناطق البعيدة)", "ر.س", _rugOutsideCtrl, Icons.location_off_rounded),
                        ],
                      ),
                      
                      const SizedBox(height: 24),
                      
                      // Deposit Settings Card
                      _buildSectionCard(
                        title: "شروط وسياسات الحجز (العربون)",
                        icon: Icons.security_rounded,
                        color: const Color(0xFF10B981),
                        children: [
                          _buildPremiumField("العربون الافتراضي لخارج الداير", "ر.س", _depositCtrl, Icons.payments_rounded),
                        ],
                      ),

                      const SizedBox(height: 36),
                      
                      // Save Button
                      Container(
                        height: 60,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF6366F1).withValues(alpha: 0.3),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            )
                          ],
                        ),
                        child: ElevatedButton(
                          onPressed: _isSaving ? null : _savePricing,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6366F1),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          ),
                          child: _isSaving
                              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                              : const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.save_rounded, size: 24),
                                    SizedBox(width: 8),
                                    Text("حفظ التحديثات", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                        ),
                      ),
                      
                      const SizedBox(height: 48),
                      
                      // System Testing Danger Zone
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: Colors.red.shade100, width: 2),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 20, left: 20, right: 20, bottom: 12),
                              child: Row(
                                children: [
                                  Icon(Icons.warning_amber_rounded, color: Colors.red.shade400, size: 24),
                                  const SizedBox(width: 10),
                                  const Text("أدوات اختبار النظام (نطاق خطر)", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF1E293B))),
                                ],
                              ),
                            ),
                            const Divider(height: 1),
                            Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                children: [
                                  const Text(
                                    "قم باختبار جودة نظام مراقبة وتتبع الأعطال (Crashlytics). النقر هنا سيتعمد إغلاق التطبيق فجأة وإرسال تقرير عطل مباشر.",
                                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B), height: 1.5),
                                  ),
                                  const SizedBox(height: 16),
                                  SizedBox(
                                    width: double.infinity,
                                    height: 50,
                                    child: OutlinedButton.icon(
                                      onPressed: () {
                                        FirebaseCrashlytics.instance.crash();
                                      },
                                      icon: const Icon(Icons.bug_report_rounded),
                                      label: const Text("محاكاة انهيار للتطبيق", style: TextStyle(fontWeight: FontWeight.bold)),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.red.shade600,
                                        side: BorderSide(color: Colors.red.shade200, width: 1.5),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                        backgroundColor: Colors.red.shade50.withValues(alpha: 0.5),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ],
            ),
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required Color color,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF94A3B8).withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.04),
                  border: Border(bottom: BorderSide(color: color.withValues(alpha: 0.1))),
                ),
                child: Row(
                  children: [
                    Icon(icon, color: color, size: 22),
                    const SizedBox(width: 10),
                    Text(
                      title,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF1E293B)),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: children,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPremiumField(String label, String suffix, TextEditingController controller, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 4, bottom: 8),
          child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF475569))),
        ),
        TextFormField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF1E293B)),
          decoration: InputDecoration(
            prefixIcon: Icon(icon, color: const Color(0xFF94A3B8), size: 20),
            suffixText: suffix,
            suffixStyle: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF6366F1)),
            filled: true,
            fillColor: const Color(0xFFF1F5F9).withValues(alpha: 0.7),
            contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Colors.transparent),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFF6366F1), width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: Colors.red.shade300, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}
