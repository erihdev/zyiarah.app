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

  final TextEditingController _maxWorkerCtrl = TextEditingController();
  final TextEditingController _merchantNameCtrl = TextEditingController();
  final TextEditingController _vatNumberCtrl = TextEditingController();
  List<int> _selectedHours = [4, 5, 6, 8];
  bool _codEnabled = false;

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
            _codEnabled = data['cod_enabled'] ?? false;
            _merchantNameCtrl.text = data['merchant_name'] ?? "مؤسسة معاذ يحي محمد المالكي";
            _vatNumberCtrl.text = data['vat_number'] ?? "310885360200003";
            _isLoading = false;
          });
          
          final hourlyDoc = await _db.collection('system_configs').doc('hourly_settings').get();
          if (hourlyDoc.exists) {
            final List<dynamic>? hoursList = hourlyDoc.data()?['allowed_hours'];
            if (hoursList != null && mounted) {
              setState(() {
                _selectedHours = hoursList.cast<int>();
              });
            }
            if (mounted) {
              setState(() {
                _maxWorkerCtrl.text = (hourlyDoc.data()?['max_workers'] ?? 5).toString();
              });
            }
          }
          else {
             _selectedHours = [4, 5, 6, 8];
             _maxWorkerCtrl.text = '5';
          }
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
        'cod_enabled': _codEnabled,
        'merchant_name': _merchantNameCtrl.text.trim(),
        'vat_number': _vatNumberCtrl.text.trim(),
      }, SetOptions(merge: true));

      List<int> validHours = List<int>.from(_selectedHours)..sort();
      if (validHours.isEmpty) validHours = [4];

      await _db.collection('system_configs').doc('hourly_settings').set({
        'allowed_hours': validHours,
        'max_workers': int.tryParse(_maxWorkerCtrl.text) ?? 5,
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
    _maxWorkerCtrl.dispose();
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

                      

                      
                      // Payment Settings Card
                      _buildSectionCard(
                        title: "إعدادات الدفع",
                        icon: Icons.payments_rounded,
                        color: const Color(0xFF8B5CF6),
                        children: [
                          SwitchListTile(
                            title: const Text("تفعيل الدفع عند الاستلام", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                            subtitle: const Text("السماح للعملاء باختيار الدفع نقداً", style: TextStyle(fontSize: 12, color: Colors.grey)),
                            value: _codEnabled,
                            activeThumbColor: const Color(0xFF8B5CF6),
                            onChanged: (val) {
                              setState(() {
                                _codEnabled = val;
                              });
                            },
                            contentPadding: EdgeInsets.zero,
                          ),
                          const Divider(),
                          _buildPremiumField("اسم المنشأة الضريبي (ZATCA)", "الاسم", _merchantNameCtrl, Icons.business_rounded),
                          const SizedBox(height: 16),
                          _buildPremiumField("الرقم الضريبي (VAT)", "رقم", _vatNumberCtrl, Icons.account_balance_wallet_rounded),
                        ],
                      ),

                       const SizedBox(height: 24),
                      
                      // Packages Pricing Card
                      _buildSectionCard(
                        title: "إعدادات باقات النظام",
                        icon: Icons.timelapse_rounded,
                        color: const Color(0xFFEC4899),
                        children: [
                          _buildHoursToggles(),
                          const SizedBox(height: 24),
                          _buildPremiumField("الحد الأقصى لعدد العاملات في الطلب الواحد", "عاملات", _maxWorkerCtrl, Icons.group_add_rounded),
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
                      const SizedBox(height: 32),

                      // About Zyiarah Card
                      _buildAboutCard(),

                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ],
            ),
      ),
    );
  }

  Widget _buildAboutCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A), // Deep Slate
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.2),
            blurRadius: 15,
            offset: const Offset(0, 8),
          )
        ],
      ),
      child: const Column(
        children: [
          Icon(Icons.verified_user_rounded, color: Color(0xFF38BDF8), size: 40),
          SizedBox(height: 16),
          Text(
            "زيارة - Zyiarah",
            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8),
          Text(
            "إصدار النظام: 1.2.0+21 (Production-Ready)",
            style: TextStyle(color: Colors.white60, fontSize: 13),
          ),
          Divider(color: Colors.white10, height: 32),
          Text(
            "مؤسسة معاذ يحي محمد المالكي\nسجل تجاري رقم: 7030376342",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.5),
          ),
          SizedBox(height: 16),
          Text(
            "تطوير وتشغيل: Erih Dev (إرث)",
            style: TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.bold),
          ),
        ],
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

  Widget _buildHoursToggles() {
    final allHours = [1, 2, 4, 5, 6, 8];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(right: 4, bottom: 12),
          child: Text("الساعات المتاحة للعميل (إظهار/إخفاء)", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF475569))),
        ),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: allHours.map((h) {
            final isSelected = _selectedHours.contains(h);
            return FilterChip(
              label: Text("$h ساعة"),
              selected: isSelected,
              onSelected: (val) {
                setState(() {
                  if (val) {
                    _selectedHours.add(h);
                  } else {
                    _selectedHours.remove(h);
                  }
                });
              },
              selectedColor: const Color(0xFF6366F1).withValues(alpha: 0.2),
              checkmarkColor: const Color(0xFF6366F1),
              labelStyle: TextStyle(
                color: isSelected ? const Color(0xFF6366F1) : const Color(0xFF64748B),
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: isSelected ? const Color(0xFF6366F1) : const Color(0xFFE2E8F0)),
              ),
            );
          }).toList(),
        ),
      ],
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
