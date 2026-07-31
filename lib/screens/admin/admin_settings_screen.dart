import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
  // فشل تحميل الإعدادات = حقول فارغة، والحفظ حينها يكتب فوق إعدادات الإنتاج الحيّة
  // (اسم المنشأة/الرقم الضريبي/بنود العقد/سياسة الخصوصية) بنصوص فارغة — نعطّل زر
  // الحفظ حتى تنجح إعادة التحميل.
  bool _loadFailed = false;
  late AnimationController _fadeController;

  final TextEditingController _maxOrdersPerDayCtrl = TextEditingController();
  final TextEditingController _merchantNameCtrl = TextEditingController();
  final TextEditingController _vatNumberCtrl = TextEditingController();
  final TextEditingController _whatsappSupportCtrl = TextEditingController();
  final TextEditingController _phoneSupportCtrl = TextEditingController();
  final TextEditingController _adminEmailCtrl = TextEditingController();
  // نسبة سعر الذروة يدوياً — 0 = بلا ذروة. تحلّ محلّ الحساب الآلي من حالة السائقين.
  final TextEditingController _surgePercentCtrl = TextEditingController();
  final TextEditingController _contractTermsCtrl = TextEditingController();
  // (دمج من لوحة الويب) سياسة الخصوصية + التحكم بالتحديث الإجباري (يقرؤه app_update_service).
  final TextEditingController _privacyPolicyCtrl = TextEditingController();
  final TextEditingController _latestBuildCtrl = TextEditingController();
  final TextEditingController _updateMsgCtrl = TextEditingController();
  bool _updateEnabled = false;
  bool _updateForce = false;
  bool _maintenanceMode = false;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _fetchPricing();
  }

  Future<void> _fetchPricing() async {
    try {
      if (_loadFailed && mounted) setState(() => _loadFailed = false);
      final doc = await _db.collection('system_configs').doc('main_settings').get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        if (mounted) {
          setState(() {
            _merchantNameCtrl.text = data['merchant_name'] ?? "مؤسسة معاذ يحي محمد المالكي";
            _vatNumberCtrl.text = data['vat_number'] ?? "310885360200003";
            _whatsappSupportCtrl.text = data['support_whatsapp'] ?? "966500000000";
            _phoneSupportCtrl.text = data['support_phone'] ?? "920000000";
            _adminEmailCtrl.text = data['admin_email'] ?? "admin@zyiarah.com";
            _surgePercentCtrl.text = (data['surge_percent'] ?? 0).toString();
            _contractTermsCtrl.text = data['contract_terms'] ??
                "1. يتم تفعيل العقد تلقائياً فور سداد القيمة واعتماد الإدارة.\n"
                "2. يحق للعميل طلب الخدمة عبر التطبيق ضمن نطاق الباقة.\n"
                "3. يتعهد الطرف الأول بتقديم الخدمة بجودة مهنية معتمدة وفقاً للمعايير والأنظمة.\n"
                "4. يلتزم الطرف الثاني بتوفير بيئة عمل مناسبة وآمنة لمقدم الخدمة.";
            _privacyPolicyCtrl.text = data['privacy_policy'] ?? '';
            _maintenanceMode = data['maintenance_mode'] == true;
            _isLoading = false;
          });
          
          // (باقات السكن) لم يتبقَّ من hourly_settings إلا **السعة اليومية** —
          // allowed_hours/max_workers كانا يُعرضان ويُحفظان بلا أي قارئ (العميل
          // صار يختار باقةً وكوادرها من تسعير المنطقة، لا ساعات ولا عدد عاملات).
          final hourlyDoc = await _db.collection('system_configs').doc('hourly_settings').get();
          if (mounted) {
            setState(() {
              _maxOrdersPerDayCtrl.text =
                  (hourlyDoc.data()?['max_orders_per_day'] ?? 10).toString();
            });
          }

          // (دمج من الويب) إعداد التحديث الإجباري — system_configs/app_update
          // (يقرؤه app_update_service.dart لإجبار المستخدمين على التحديث).
          try {
            final updDoc =
                await _db.collection('system_configs').doc('app_update').get();
            if (updDoc.exists && updDoc.data() != null && mounted) {
              final u = updDoc.data()!;
              setState(() {
                _updateEnabled = u['enabled'] == true;
                _updateForce = u['force'] == true;
                _latestBuildCtrl.text = (u['latest_build'] ?? 0).toString();
                _updateMsgCtrl.text = u['message'] ?? '';
              });
            }
          } catch (_) {}
          _fadeController.forward();
        }
      } else {
        if (mounted) {
          setState(() => _isLoading = false);
          _fadeController.forward();
        }
      }
    } catch (e) {
      // كان الفشل صامتاً: نموذج فارغ + زر حفظ مفعّل = ضغطة واحدة تمسح الإعدادات
      // الحيّة بنصوص فارغة مع رسالة نجاح خضراء. نعلن الفشل ونقفل الحفظ مع زر إعادة.
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadFailed = true;
        });
        _fadeController.forward();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('فشل تحميل الإعدادات: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'إعادة المحاولة',
            textColor: Colors.white,
            onPressed: _fetchPricing,
          ),
        ));
      }
    }
  }

  Future<void> _savePricing() async {
    setState(() => _isSaving = true);
    try {
      await _db.collection('system_configs').doc('main_settings').set({
        'merchant_name': _merchantNameCtrl.text.trim(),
        'vat_number': _vatNumberCtrl.text.trim(),
        'support_whatsapp': _whatsappSupportCtrl.text.trim(),
        'support_phone': _phoneSupportCtrl.text.trim(),
        'admin_email': _adminEmailCtrl.text.trim(),
        'surge_percent':
            (double.tryParse(_surgePercentCtrl.text.trim()) ?? 0).clamp(0, 100),
        'contract_terms': _contractTermsCtrl.text.trim(),
        'privacy_policy': _privacyPolicyCtrl.text.trim(),
        'maintenance_mode': _maintenanceMode,
      }, SetOptions(merge: true));

      await _db.collection('system_configs').doc('hourly_settings').set({
        'max_orders_per_day': int.tryParse(_maxOrdersPerDayCtrl.text) ?? 10,
      }, SetOptions(merge: true));

      // (دمج من الويب) نشر سياسة الخصوصية لمستند عام تقرأه zyiarah.com/privacy بلا دخول.
      await _db.collection('public_content').doc('privacy').set({
        'content': _privacyPolicyCtrl.text.trim(),
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // (دمج من الويب) إعداد التحديث الإجباري — يقرؤه app_update_service.dart.
      await _db.collection('system_configs').doc('app_update').set({
        'enabled': _updateEnabled,
        'latest_build': int.tryParse(_latestBuildCtrl.text.trim()) ?? 0,
        'force': _updateForce,
        'message': _updateMsgCtrl.text.trim(),
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
    _maxOrdersPerDayCtrl.dispose();
    _merchantNameCtrl.dispose();
    _vatNumberCtrl.dispose();
    _whatsappSupportCtrl.dispose();
    _phoneSupportCtrl.dispose();
    _adminEmailCtrl.dispose();
    _surgePercentCtrl.dispose();
    _contractTermsCtrl.dispose();
    _privacyPolicyCtrl.dispose();
    _latestBuildCtrl.dispose();
    _updateMsgCtrl.dispose();
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
                          // زر رجوع — الشاشة مدفوعة بلا AppBar.
                          IconButton(
                            icon: const Icon(Icons.arrow_back_ios_new, color: Color(0xFF6366F1)),
                            onPressed: () => Navigator.of(context).maybePop(),
                            tooltip: 'رجوع',
                          ),
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
                          _buildPremiumField("نسبة سعر الذروة (%)", "0", _surgePercentCtrl, Icons.trending_up_rounded),
                          const Padding(
                            padding: EdgeInsets.only(top: 6, bottom: 4),
                            child: Text(
                              "تُضاف على أسعار الطلبات عند الطلب (بالساعة والكنب والمكيفات) وتظهر للعميل في الفاتورة.\n"
                              "0 = بلا ذروة (السعر كما هو). مثال: 15 = زيادة 15%. الحد الأقصى 100.",
                              style: TextStyle(fontSize: 11, color: Colors.grey, height: 1.5),
                            ),
                          ),
                          const Divider(),
                          _buildPremiumField("اسم المنشأة الضريبي (ZATCA)", "الاسم", _merchantNameCtrl, Icons.business_rounded, keyboardType: TextInputType.text),
                          const SizedBox(height: 16),
                          _buildPremiumField("الرقم الضريبي (VAT)", "رقم", _vatNumberCtrl, Icons.account_balance_wallet_rounded),
                        ],
                      ),

                       const SizedBox(height: 24),

                      // Support Contacts Card
                      _buildSectionCard(
                        title: "إعدادات العناية بالعملاء",
                        icon: Icons.support_agent_rounded,
                        color: const Color(0xFF10B981),
                        children: [
                           _buildPremiumField("رقم الواتساب (للدعم المباشر)", "WhatsApp", _whatsappSupportCtrl, Icons.chat_bubble_outline_rounded),
                           const SizedBox(height: 16),
                           _buildPremiumField("رقم الاتصال الموحد", "Call", _phoneSupportCtrl, Icons.phone_forwarded_rounded),
                           const SizedBox(height: 16),
                           _buildPremiumField("البريد الإلكتروني لاستلام التنبيهات", "Admin Email", _adminEmailCtrl, Icons.alternate_email_rounded, keyboardType: TextInputType.emailAddress),
                        ],
                      ),

                      const SizedBox(height: 24),

                      // Contract Terms Card
                      _buildSectionCard(
                        title: "شروط وأحكام العقد الإلكتروني الموحد",
                        icon: Icons.gavel_rounded,
                        color: Colors.amber.shade800,
                        children: [
                          const Text(
                            "اكتب بنود وشروط وأحكام العقد الإلكتروني التي ستظهر للعميل في شاشة التوقيع الإلكتروني مباشرة وتنعكس لحظياً.",
                            style: TextStyle(fontSize: 12, color: Colors.grey, height: 1.5),
                          ),
                          const SizedBox(height: 16),
                          _buildPremiumMultilineField("بنود العقد الإلكتروني", "اكتب البنود والشروط...", _contractTermsCtrl, Icons.edit_note_rounded),
                        ],
                      ),
                      
                      const SizedBox(height: 24),
                      
                      // Packages Pricing Card
                      _buildSectionCard(
                        title: "الطاقة الاستيعابية اليومية",
                        icon: Icons.timelapse_rounded,
                        color: const Color(0xFFEC4899),
                        children: [
                          // هذا هو **الضابط الوحيد** لسعة الحجز اليومي في نظام
                          // باقات السكن: العميل يختار اليوم فقط، واليوم يمتلئ
                          // عند بلوغ هذا السقف (مع شرط توفر سائق لمدة الباقة).
                          _buildPremiumField("سقف الطلبات المجدولة في اليوم الواحد", "طلبات/يوم", _maxOrdersPerDayCtrl, Icons.calendar_month_rounded),
                          const SizedBox(height: 16),
                          // السعة المتزامنة تُحسب تلقائياً = عدد السائقين النشطين (لا رقم يدوي)
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFF660033).withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: const Color(0xFF660033).withValues(alpha: 0.15)),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.info_outline_rounded, color: Color(0xFF660033), size: 20),
                                SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    "الحد الأقصى للطلبات المتزامنة في الفترة يُحسب تلقائياً = عدد السائقين النشطين المسجّلين. أضِف سائقين لزيادة السعة.",
                                    style: TextStyle(fontSize: 12, color: Color(0xFF475569), height: 1.5),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),

                      // (دمج من لوحة الويب) وضع الصيانة — يُقفل التطبيق للعملاء فقط.
                      _buildSectionCard(
                        title: "وضع الصيانة",
                        icon: Icons.engineering_rounded,
                        color: const Color(0xFFDC2626),
                        children: [
                          _buildToggle(
                            "إغلاق التطبيق للعملاء (صيانة)",
                            "عند التفعيل يرى العملاء شاشة صيانة ولا يستطيعون الطلب. الإدارة والسائقون لا يتأثّرون.",
                            _maintenanceMode,
                            (v) => setState(() => _maintenanceMode = v),
                            const Color(0xFFDC2626),
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),

                      // (دمج من لوحة الويب) التحكم بالتحديث الإجباري — يقرؤه التطبيق فعلاً.
                      _buildSectionCard(
                        title: "التحديث الإجباري للتطبيق",
                        icon: Icons.system_update_rounded,
                        color: const Color(0xFF660033),
                        children: [
                          _buildPremiumField("أحدث رقم بناء منشور (Latest Build)", "مثال 210", _latestBuildCtrl, Icons.numbers_rounded),
                          const Padding(
                            padding: EdgeInsets.only(top: 6, bottom: 4),
                            child: Text(
                              "يظهر إشعار التحديث لكل مستخدم رقم بنائه أقدم من هذا الرقم فقط.",
                              style: TextStyle(fontSize: 11, color: Colors.grey, height: 1.5),
                            ),
                          ),
                          const Divider(),
                          _buildToggle("تفعيل إشعار التحديث", "", _updateEnabled, (v) => setState(() => _updateEnabled = v), const Color(0xFF10B981)),
                          _buildToggle("إجباري (لا يمكن تجاهله)", "يمنع المستخدم من استخدام التطبيق حتى يُحدّث.", _updateForce, (v) => setState(() => _updateForce = v), const Color(0xFF660033)),
                          const SizedBox(height: 12),
                          _buildPremiumField("رسالة التحديث (اختياري)", "نص", _updateMsgCtrl, Icons.message_rounded, keyboardType: TextInputType.text),
                        ],
                      ),

                      const SizedBox(height: 24),

                      // (دمج من لوحة الويب) سياسة الخصوصية — تُنشَر لصفحة zyiarah.com/privacy.
                      _buildSectionCard(
                        title: "سياسة الخصوصية",
                        icon: Icons.privacy_tip_rounded,
                        color: const Color(0xFF0EA5E9),
                        children: [
                          const Text(
                            "تُنشَر للعملاء وعلى صفحة zyiarah.com/privacy العامة فور الحفظ. اترك سطراً فارغاً بين الفقرات.",
                            style: TextStyle(fontSize: 12, color: Colors.grey, height: 1.5),
                          ),
                          const SizedBox(height: 16),
                          _buildPremiumMultilineField("نص سياسة الخصوصية", "اكتب سياسة الخصوصية هنا...", _privacyPolicyCtrl, Icons.shield_outlined),
                        ],
                      ),

                      const SizedBox(height: 36),

                      // شريط دائم عند فشل التحميل — الـSnackBar يختفي ويبقى زر الحفظ
                      // معطّلاً بلا تفسير، فنعرض السبب وزر إعادة المحاولة هنا.
                      if (_loadFailed) ...[
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error_outline_rounded, color: Colors.red.shade700, size: 22),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  "تعذّر تحميل الإعدادات الحالية — الحفظ معطّل حتى لا تُستبدل البيانات الحيّة بحقول فارغة.",
                                  style: TextStyle(fontSize: 12, color: Colors.red.shade700, height: 1.5),
                                ),
                              ),
                              TextButton(
                                onPressed: _fetchPricing,
                                child: const Text("إعادة المحاولة", style: TextStyle(fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

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
                          // _loadFailed: لا حفظ فوق نموذج فارغ بعد فشل التحميل (مسح بيانات).
                          onPressed: (_isSaving || _loadFailed) ? null : _savePricing,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF660033),
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
                      
                      // (أُزيلت "أدوات اختبار النظام / محاكاة الانهيار" — لا يجوز وجود
                      // زر يُسقط التطبيق عمداً في بناء إنتاجي.)
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

  Widget _buildToggle(String label, String subtitle, bool value,
      ValueChanged<bool> onChanged, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E293B))),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFF94A3B8), height: 1.4)),
                ],
              ],
            ),
          ),
          Switch(value: value, activeThumbColor: color, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _buildPremiumField(String label, String suffix, TextEditingController controller, IconData icon, {TextInputType? keyboardType}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 4, bottom: 8),
          child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF475569))),
        ),
        TextFormField(
          controller: controller,
          // النوع الافتراضي رقمي لكن الحقول النصّية (اسم المنشأة/الويبهوك/البريد) تمرّر
          // نوعها الخاص — كان الرقمي مفروضاً عليها فيتعذّر إدخال الحروف و@ و/ إطلاقاً.
          keyboardType: keyboardType ?? const TextInputType.numberWithOptions(decimal: true),
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

  Widget _buildPremiumMultilineField(String label, String hint, TextEditingController controller, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 4, bottom: 8),
          child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF475569))),
        ),
        TextFormField(
          controller: controller,
          maxLines: 12,
          minLines: 5,
          keyboardType: TextInputType.multiline,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
          decoration: InputDecoration(
            prefixIcon: Padding(
              padding: const EdgeInsets.only(bottom: 80.0), // align icon to the top
              child: Icon(icon, color: const Color(0xFF94A3B8), size: 20),
            ),
            hintText: hint,
            filled: true,
            fillColor: const Color(0xFFF1F5F9).withValues(alpha: 0.7),
            contentPadding: const EdgeInsets.all(16),
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
          ),
        ),
      ],
    );
  }
}
