import 'dart:async';
import 'dart:convert';

import 'package:zyiarah/services/zyiarah_messaging_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:zyiarah/services/tamara_service.dart';
import 'package:zyiarah/screens/checkout_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:zyiarah/models/user_model.dart';
import 'package:zyiarah/services/order_service.dart';
import 'package:zyiarah/utils/order_util.dart';
import 'package:zyiarah/utils/moyasar_util.dart';
import 'package:zyiarah/screens/order_success_screen.dart';
import 'package:intl/intl.dart' as intl;
import 'package:zyiarah/services/zatca_service.dart';
import 'package:zyiarah/services/zyiarah_pdf_service.dart';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:pay/pay.dart';
import 'package:zyiarah/services/moyasar_service.dart';
import 'package:zyiarah/services/tabby_service.dart';
import 'package:zyiarah/screens/moyasar_card_screen.dart';
import 'package:zyiarah/screens/moyasar_stc_screen.dart';
import 'package:moyasar/moyasar.dart';
import 'package:zyiarah/services/zyiarah_wallet_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:zyiarah/providers/config_provider.dart';
import 'package:provider/provider.dart';
import 'package:zyiarah/utils/global_error_handler.dart';
import 'package:zyiarah/services/counter_service.dart';
import 'package:cloud_functions/cloud_functions.dart';



class PaymentSummaryScreen extends StatefulWidget {
  final String serviceName;
  final double amount;
  final GeoPoint? location;
  final int? hours;
  final DateTime? serviceDate;
  final String? zoneName;

  /// تفصيل الخدمة كما اختارته العميلة (قطع الكنب/السجاد بمقاساتها، أنواع المكيفات
  /// وأعدادها…). يُكتب على الطلب في `service_meta` — بدونه يصل الطلب للإدارة والسائق
  /// بمبلغٍ مجرّد بلا بيان: كم قطعة؟ ما مقاسها؟ فلا يعرف السائق ما يحمل ولا الإدارة
  /// ما تدقّق. القيم بدائية (أرقام/نصوص/قوائم) لتُكتب في Firestore كما هي.
  final Map<String, dynamic>? serviceMeta;

  final int workerCount;
  final String? contractId;
  final int? planVisits;

  const PaymentSummaryScreen({
    super.key,
    required this.serviceName,
    required this.amount,
    this.location,
    this.hours,
    this.serviceDate,
    this.zoneName,
    this.serviceMeta,
    this.workerCount = 1,
    this.contractId,
    this.planVisits,
  });

  @override
  State<PaymentSummaryScreen> createState() => _PaymentSummaryScreenState();
}

class _PaymentSummaryScreenState extends State<PaymentSummaryScreen> {
  final TamaraService _tamaraService = TamaraService();
  final ZyiarahOrderService _orderService = ZyiarahOrderService();

  // 'cod' أُزيل من الجذور: الدفع مقدَّم دائماً.
  String _selectedPaymentMethod = 'card'; // card | apple_pay | google_pay | tamara | tabby | stc_pay | wallet | subscription
  bool _isLoading = false;
  // سبب امتلاء السعة (للطلبات بالساعة) — يُفحص عند فتح الشاشة ويُستخدم لمنع أزرار
  // الدفع الأصلية (Apple/Google/Samsung Pay) التي تخصم فوراً وتتجاوز فحص _handlePayment.
  String? _capacityError;
  Timer? _capacityWatch; // تحديث دوري لفحص السعة (يحمي مسار الدفع الأصلي)
  ZyiarahUser? _currentUser;
  bool _agreeToTerms = false;
  bool _tamaraEnabled = false;
  // null = لم يُجلب بعد أو فشل الجلب — كان double بقيمة 0.0 فيُعرض «الرصيد: 0.00»
  // كاذباً عند فشل الجلب ويُرفض الدفع بالمحفظة برسالة «رصيدك 0.00» لعميلٍ يملك
  // رصيداً حقيقياً (الاسترداد يُقيَّد للمحفظة خادمياً). null يميّز «لا نعرف» عن «صفر».
  double? _walletBalance;
  bool _walletFetchFailed = false;
  double _surgeFactor = 1.0;

  /// هل أُنشئ مستند orders/{_pendingOrderId} في محاولة دفع سابقة؟ إعادة كتابته
  /// تُرفض من قواعد Firestore (permission-denied) ومبلغه مجمّد على قديمه —
  /// فحين يصير المعرّف «محروقاً» نسكّ غيره (انظر _mintFreshPendingOrderId).
  bool _pendingOrderCreated = false;

  final TextEditingController _couponController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  double _discountAmount = 0.0;
  String? _appliedCoupon;
  bool _isValidatingCoupon = false;
  bool _needsPhoneUpdate = false;

  late String _pendingOrderId;
  late final Future<PaymentConfiguration>? _googlePayConfigFuture;

  // dart:io Platform **يرمي على الويب** (Unsupported operation: Platform._operatingSystem)
  // فيقتل الشاشة كاملة بشاشة حمراء لحظة فتحها. نحرسه بـ kIsWeb: على الويب لا
  // Apple/Google/Samsung Pay (حِزمها أصلية فقط) — تُخفى أزرارها وتبقى البطاقة
  // وSTC وتمارا وتابي والمحفظة. iOS/أندرويد بلا تغيير.
  static final bool _isNativeIOS = !kIsWeb && Platform.isIOS;
  static final bool _isNativeAndroid = !kIsWeb && Platform.isAndroid;

  @override
  void initState() {
    super.initState();
    _pendingOrderId =
        FirebaseFirestore.instance.collection('orders').doc().id;
    if (_isNativeAndroid) {
      _googlePayConfigFuture =
          PaymentConfiguration.fromAsset('assets/google_pay_config.json');
    } else {
      _googlePayConfigFuture = null;
    }
    _loadUserData();
    // فحص السعة مبكّراً للطلبات بالساعة — كي نمنع أزرار الدفع الأصلية عند الامتلاء.
    // **ويتجدد دورياً**: أزرار Apple/Google/Samsung Pay تخصم قبل أي رد نداء لنا،
    // ففحصُ الفتح وحده كان يتقادم — يمتلئ اليوم والعميل على الشاشة فيدفع لحجزٍ
    // لم يعد متاحاً. التحديث كل 45ث يُحدّث المنع والسماح معاً (مسارات _handlePayment
    // الأخرى تفحص لحظة الدفع أصلاً).
    if (widget.hours != null && widget.serviceDate != null) {
      Future<void> refresh() => _checkHourlyCapacity().then((err) {
            if (mounted) setState(() => _capacityError = err);
          });
      refresh();
      _capacityWatch =
          Timer.periodic(const Duration(seconds: 45), (_) => refresh());
    }
  }

  @override
  void dispose() {
    _capacityWatch?.cancel();
    _couponController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final List<DocumentSnapshot<Map<String, dynamic>>> results;
      try {
        results = await Future.wait([
          FirebaseFirestore.instance.collection('users').doc(user.uid).get(),
          FirebaseFirestore.instance.collection('system_configs').doc('main_settings').get(),
        ]);
      } catch (e) {
        // فشل جلب المستخدم/الإعدادات (شبكة عابرة) كان بلا التقاط: يبقى
        // _currentUser=null للأبد فتُحجب كل أزرار الدفع برسالة «جارٍ تحميل
        // بيانات حسابك» الكاذبة — ولا شيء يعيد الاستدعاء أبداً. نعرض السبب
        // مع زرّ إعادة محاولة حقيقي بدل ترك الشاشة عالقة.
        debugPrint('[loadUserData] failed: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('تعذّر تحميل بيانات حسابك: $e',
                style: GoogleFonts.tajawal()),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: 'إعادة المحاولة',
              textColor: Colors.white,
              onPressed: _loadUserData,
            ),
          ));
        }
        return;
      }
      final userDoc = results[0];
      final configDoc = results[1];
      if (userDoc.exists && mounted) {
        setState(() {
          _currentUser = ZyiarahUser.fromMap(user.uid, userDoc.data()!);

          final phone = _currentUser?.phone ?? '';
          if (phone.isEmpty || phone == '000000000' || phone.length < 9) {
            _needsPhoneUpdate = true;
          } else {
            _phoneController.text = phone;
          }


          _tamaraEnabled = configDoc.data()?['tamara_enabled'] as bool? ?? false;
        });

        // Fetch wallet balance separately
        await _fetchWalletBalance();

        // Fetch surge pricing factor — يُطبَّق على المبلغ قبل عرضه للعميل
        try {
          final surgeResult = await FirebaseFunctions.instance
              .httpsCallable('getSurgePricingFactor').call();
          final factor = (surgeResult.data['surgeFactor'] as num? ?? 1.0).toDouble();
          if (mounted && factor != _surgeFactor) {
            setState(() {
              _surgeFactor = factor;
              // تغيّر الإجمالي بعد إنشاء مستند الطلب = مبلغه مجمّد متقادم — معرّف جديد.
              if (_pendingOrderCreated) _mintFreshPendingOrderId();
            });
          }
        } catch (e) {
          debugPrint('Surge pricing fetch failed, using 1.0: $e');
        }
      }
    }
  }

  /// جلب رصيد المحفظة — قابل لإعادة الاستدعاء من زر «إعادة المحاولة» في بطاقة
  /// المحفظة. الفشل كان يُبتلع بـ debugPrint فقط فيبقى الرصيد 0.00 كاذباً بلا
  /// أي مسار لإعادة الجلب.
  Future<void> _fetchWalletBalance() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (mounted && _walletFetchFailed) {
      // إظهار «جارٍ تحميل الرصيد…» أثناء إعادة المحاولة بدل إبقاء رسالة الفشل.
      setState(() => _walletFetchFailed = false);
    }
    try {
      final wallet = await ZyiarahWalletService().getOrCreateWallet(user.uid);
      if (mounted) {
        setState(() {
          _walletBalance = wallet.balance;
          _walletFetchFailed = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching wallet balance: $e');
      if (mounted) setState(() => _walletFetchFailed = true);
    }
  }

  /// يسكّ معرّف طلب جديداً (ومعه يتغيّر given_id المشتق منه لميسر) — يُستدعى حين
  /// يصير المعرّف الحالي «محروقاً»:
  ///  • مستنده أُنشئ في محاولة سابقة: إعادة كتابته تُرفض من قواعد Firestore
  ///    (فكانت كل محاولة دفع ثانية تفشل بـ permission-denied)، ومبلغه مجمّد على
  ///    قديمه فيرفض الخادم تطابق المبلغ إن تغيّر الإجمالي (كوبون/ذروة).
  ///  • أو استهلكت دفعةٌ فاشلة نهائياً given_id المشتق منه لدى ميسر، فإعادة
  ///    المحاولة بنفسه تُعيد الدفعة الفاشلة ذاتها.
  /// يُستدعى داخل setState كي تُعاد بناء أزرار الدفع الأصلية بالمعرّف الجديد.
  void _mintFreshPendingOrderId() {
    _pendingOrderId = FirebaseFirestore.instance.collection('orders').doc().id;
    _pendingOrderCreated = false;
  }

  // الحسابات المالية الصحيحة (بافتراض أن المبلغ شامل للضريبة، مع تطبيق Surge)
  // مقرّب لخانتين عشريتين — يمنع أرقاماً مثل 57.4999999999 في المبلغ المخزَّن/المعروض.
  double get totalWithVat {
    // Surge يُطبَّق فقط على الطلبات عند الطلب (بالساعة/الكنب) — لا على الأسعار الثابتة:
    // الاشتراك (planPrice) والصيانة (quotePrice) أسعار معلَنة ثابتة، وضربُها في surge
    // كان يفرض دفعاً زائداً + يجعل الخادم يرفض تطابق المبلغ فلا يُفعَّل العقد/الصيانة.
    final bool fixedPrice = widget.contractId != null;
    final double surge = fixedPrice ? 1.0 : _surgeFactor;
    // الخصم (الكوبون) لا يُطبَّق على السعر الثابت (الاشتراك): الخادم يطابق planPrice
    // بلا خصم بالضبط، فأي خصم يجعل المشحون ≠ planPrice → يُرفض الدفع ولا يُفعَّل العقد
    // رغم خصم المال. ونحدّ الخصم بألا يتجاوز المبلغ (كوبون أكبر من الطلب = مبلغ سالب).
    final double discount = fixedPrice ? 0.0 : _discountAmount;
    final raw = (widget.amount * surge) - discount;
    final clamped = raw < 0 ? 0.0 : raw;
    return (clamped * 100).roundToDouble() / 100;
  }
  double get subtotal => totalWithVat / 1.15;
  double get vatAmount => totalWithVat - subtotal;

  /// طلب متجر (توصيل منتجات) — نخفي «المدة» و«عدد العاملات» فهما مضلّلان هنا،
  /// ونعرض «عدد المنتجات» بدلاً منهما. يُكتشف من نوع service_meta.
  bool get _isStoreOrder =>
      widget.serviceMeta != null &&
      widget.serviceMeta!['kind'] == 'store_products';

  /// سبب منع الدفع الأصلي (Apple/Google/Samsung) — نفس فحوص _handlePayment
  /// المتزامنة (الشروط/الهاتف/المستخدم). لولاها تتجاوز الأزرار الأصلية الفحوص
  /// لأنها تستدعي النجاح مباشرةً.
  String? _nativePayBlockReason() {
    // السعة أولاً: الأزرار الأصلية تخصم فوراً، فنمنعها إن امتلأ الموعد (منع الحجز الزائد).
    if (_capacityError != null) return _capacityError;
    if (_needsPhoneUpdate && _phoneController.text.trim().isEmpty) {
      return 'يرجى إدخال رقم جوالك أولاً';
    }
    if (!_agreeToTerms) return 'يرجى الموافقة على الشروط والأحكام أولاً';
    if (_currentUser == null) {
      return FirebaseAuth.instance.currentUser == null
          ? 'يرجى تسجيل الدخول لإتمام الدفع'
          : 'جارٍ تحميل بيانات حسابك، حاول بعد لحظة';
    }
    return null;
  }

  /// يلفّ زر دفع أصلي ببوابة: يعتّمه ويمنع النقر ويُظهر السبب حين لا تتحقق الشروط.
  Widget _gateNative(Widget child) {
    final reason = _nativePayBlockReason();
    if (reason == null) return child;
    return Stack(
      children: [
        child,
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              // بيانات الحساب غائبة رغم تسجيل الدخول = فشل الجلب الأول —
              // نعيد المحاولة فعلياً كي تكون «حاول بعد لحظة» صادقة (لا شيء
              // آخر كان يعيد استدعاء _loadUserData بعد فشله).
              if (_currentUser == null &&
                  FirebaseAuth.instance.currentUser != null) {
                _loadUserData();
              }
              final r = _nativePayBlockReason();
              if (r != null && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(r, style: GoogleFonts.tajawal())),
                );
              }
            },
            child: Opacity(
              opacity: 0.5,
              child: Container(color: const Color(0xFFF1F5F9)),
            ),
          ),
        ),
      ],
    );
  }

  /// Apple Pay via Moyasar SDK — يُستدعى من ApplePay widget callback
  Future<void> _onApplePayResult(dynamic result) async {
    if (!mounted) return;

    // PaymentResponse when paid/authorized, error types otherwise
    if (result is PaymentResponse &&
        (result.status == PaymentStatus.paid ||
         result.status == PaymentStatus.authorized)) {
      setState(() => _isLoading = true);
      await _processUnifiedSuccess(_pendingOrderId, 'apple_pay', paymentId: result.id);
    } else {
      String msg = 'فشل الدفع عبر Apple Pay';
      if (result is ApiError) msg = result.message;
      if (result is ValidationError) msg = result.message;
      // فشل نهائي سجّلته ميسر (رفض/PaymentResponse غير مدفوعة أو ApiError)
      // يستهلك given_id الحالي — إعادة المحاولة به تُعيد الدفعة الفاشلة نفسها.
      // نسكّ معرّفاً جديداً للمحاولة التالية. (ValidationError محلي بلا سجل لدى
      // ميسر، وNetworkError مجهول النتيجة — نُبقي المعرّف لمنع الشحن المزدوج.)
      if (result is ApiError || result is PaymentResponse) {
        setState(_mintFreshPendingOrderId);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(msg, style: GoogleFonts.tajawal()),
          backgroundColor: Colors.red.shade800,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(15),
        ));
      }
    }
  }

  /// Samsung Pay via Moyasar SDK — يُستدعى من SamsungPay widget callback
  Future<void> _onSamsungPayResult(dynamic result) async {
    if (!mounted) return;

    if (result is PaymentResponse &&
        (result.status == PaymentStatus.paid ||
         result.status == PaymentStatus.authorized)) {
      setState(() => _isLoading = true);
      await _processUnifiedSuccess(_pendingOrderId, 'samsung_pay', paymentId: result.id);
    } else {
      String msg = 'فشل الدفع عبر Samsung Pay';
      if (result is ApiError) msg = result.message;
      if (result is ValidationError) msg = result.message;
      if (result is NetworkError) msg = 'تعذّر الاتصال — يرجى المحاولة مجدداً';
      // فشل نهائي سجّلته ميسر يستهلك given_id — معرّف جديد للمحاولة التالية
      // (لا نسكّ على NetworkError: النتيجة مجهولة والثبات يمنع الشحن المزدوج).
      if (result is ApiError || result is PaymentResponse) {
        setState(_mintFreshPendingOrderId);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(msg, style: GoogleFonts.tajawal()),
          backgroundColor: Colors.red.shade800,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(15),
        ));
      }
    }
  }

  Future<void> _validateCoupon() async {
    if (_couponController.text.isEmpty) return;
    setState(() => _isValidatingCoupon = true);

    final Map<String, dynamic>? couponData;
    try {
      couponData = await _orderService.validateCoupon(
        _couponController.text,
        currentUserZone: widget.zoneName,
      );
    } catch (e) {
      // فشل بنيوي (شبكة/صلاحيات) لا يعني أن الكود باطل — كانت الرسالة تتهم
      // كوبوناً سليماً بالبطلان أثناء انقطاع عابر (الخدمة كانت تبتلع الاستثناء
      // وتُرجع null فيُعامَل ككود خاطئ). نُبقي أي كوبون مُطبَّق سابقاً كما هو.
      if (mounted) {
        setState(() => _isValidatingCoupon = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('تعذّر الاتصال — يرجى المحاولة مجدداً: $e'),
          backgroundColor: Colors.red,
        ));
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isValidatingCoupon = false;
        if (couponData != null) {
          _appliedCoupon = _couponController.text.toUpperCase();
          double value = ((couponData['value'] as num?) ?? 0).toDouble();
          if (couponData['type'] == 'percentage') {
            // النسبة على المبلغ المُطبَّق عليه Surge (هو ما يُدفع فعلاً) — كان يُحسب على
            // المبلغ قبل Surge فيُخصَم أقل من المُعلَن أثناء ذروة التسعير.
            _discountAmount = widget.amount * _surgeFactor * (value / 100);
          } else {
            _discountAmount = value;
          }
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("تم تطبيق الكود بنجاح"), backgroundColor: Colors.green),
          );
        } else {
          _appliedCoupon = null;
          _discountAmount = 0.0;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("كود الخصم غير صحيح أو منتهي"), backgroundColor: Colors.red),
          );
        }
        // تغيّر الإجمالي (تطبيق/إبطال كوبون) بعد إنشاء مستند الطلب في محاولة
        // سابقة: مبلغ المستند مجمّد على القديم والقواعد تمنع تحديثه من العميل —
        // فالدفع الأصلي (Apple/Google/Samsung) يشحن الجديد ويرفض الخادم تطابق
        // المبلغ فيبقى الطلب غير مؤكد رغم الخصم. معرّف جديد ⇒ ينشئ الخادم
        // الطلب من metadata الدفعة بالمبلغ الصحيح.
        if (_pendingOrderCreated) _mintFreshPendingOrderId();
      });
    }
  }


  /// يتحقق من توفر سعة الحجز للخدمة بالساعة.
  /// يعيد رسالة خطأ إذا امتلأت السعة **أو تعذّر التحقق**، أو null إذا كان الحجز متاحاً.
  ///
  /// **كانت هذه البوابة ميتة تماماً — لم تمنع حجزاً واحداً منذ كُتبت.**
  /// الفحص السابق كان يستعلم `orders` مباشرةً من جهاز العميل بلا قيد `client_id`:
  ///
  ///     .collection('orders').where('booking_date', isEqualTo: bookingDate).get()
  ///
  /// وقاعدة القراءة الوحيدة للطلبات (firestore.rules) تسمح للعميل بطلباته هو فقط
  /// (`client_id == uid` أو `driver_id == uid` أو `isAdmin`). القواعد ليست مُرشِّحات:
  /// Firestore يرفض **الاستعلام كاملاً** بـ permission-denied. وكان `catch (_) {}`
  /// يبتلع الرفض، وجملتا `return '<رسالة>'` تقعان **داخل** الـ try — فتُتخطّيان،
  /// وتُرجع الدالة null أي «متاح» في كل مرة. النتيجة: العميل يدفع ليومٍ ممتلئ ولا
  /// يجد سائقاً — وهو بالضبط ما حذّر منه تعليق الشيفرة القديم («مدفوع بلا تنفيذ»).
  ///
  /// نستخدم الآن `getHourlyAvailability` الخادمية — وهي موجودة أصلاً لهذا الغرض
  /// حرفياً («server-side to bypass Firestore rules») — وتحسب السعة من **عدد
  /// السائقين المؤهّلين في المنطقة** لا من رقم ثابت في الإعدادات.
  ///
  /// **ويفشل مغلقاً عمداً:** أي تعذّر في التحقق يمنع الدفع بدل أن يسمح به صامتاً.
  /// حجزٌ مؤجَّل دقيقة أهون من طلبٍ مدفوع لا سائق له (استرداد + عميل غاضب).
  Future<String?> _checkHourlyCapacity() async {
    if (widget.hours == null || widget.serviceDate == null) return null;

    final String bookingDate = '${widget.serviceDate!.year}-'
        '${widget.serviceDate!.month.toString().padLeft(2, '0')}-'
        '${widget.serviceDate!.day.toString().padLeft(2, '0')}';

    final Map data;
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('getHourlyAvailability')
          // نمرّر المنطقة لجلب جدول فتحها (لا للسعة — السائقون بلا مناطق).
          .call({
            'startDate': bookingDate,
            'endDate': bookingDate,
            if (widget.zoneName != null) 'zoneName': widget.zoneName,
          })
          .timeout(const Duration(seconds: 20));
      data = result.data as Map;
    } catch (e) {
      debugPrint('[capacity] getHourlyAvailability failed: $e');
      return 'تعذّر التحقق من توفّر الموعد. تحقّق من اتصالك وأعد المحاولة.';
    }

    final Map daily = data['dailyCounts'] as Map? ?? {};
    final Map slots = data['slotCounts'] as Map? ?? {};
    final int maxOrdersPerDay = (data['maxOrdersPerDay'] as num?)?.toInt() ?? 10;
    // maxTeamsPerSlot = عدد السائقين النشطين (بلا مناطق — تحسبه الدالة).
    final int maxTeamsPerSlot = (data['maxTeamsPerSlot'] as num?)?.toInt() ?? 0;

    if (maxTeamsPerSlot <= 0) {
      return 'لا يوجد فريق متاح حالياً. تواصل معنا لتحديد موعد.';
    }

    final closedDates =
        ((data['closedDates'] as List?) ?? []).map((e) => e.toString()).toSet();
    if (closedDates.contains(bookingDate)) {
      return 'نعتذر، لا نخدم منطقتك في هذا اليوم. يرجى اختيار يوم آخر.';
    }

    if (((daily[bookingDate] as num?)?.toInt() ?? 0) >= maxOrdersPerDay) {
      return 'نعتذر، هذا اليوم محجوز بالكامل حالياً. يرجى اختيار تاريخ آخر.';
    }

    final openRaw = (data['openHours'] as Map? ?? {})[bookingDate];
    final int openStart =
        (openRaw is List && openRaw.isNotEmpty) ? (openRaw[0] as num).toInt() : 8;
    final int openEnd =
        (openRaw is List && openRaw.length > 1) ? (openRaw[1] as num).toInt() : 22;

    // مساران بحسب نوع الطلب:
    // • باقات السكن (home_package): العميل اختار **اليوم فقط** — الشرط وجود
    //   **أي** فترة بطول الخدمة كل ساعاتها دون عدد السائقين (قرار المالك).
    // • بقية الخدمات المجدولة (كنب/مكيفات/سيارات/متجر): العميل اختار **خانة
    //   محددة** — تُفحص خانته هي (ضمن الفتح + سائق حرّ طوالها) كما كان دائماً.
    final bool dayOnly =
        widget.serviceMeta != null && widget.serviceMeta!['kind'] == 'home_package';

    if (dayOnly) {
      bool anyWindowFree = false;
      for (int h = openStart; h <= openEnd - widget.hours!; h++) {
        bool free = true;
        for (int hh = h; hh < h + widget.hours!; hh++) {
          final key = '${bookingDate}_${hh.toString().padLeft(2, '0')}:00';
          if (((slots[key] as num?)?.toInt() ?? 0) >= maxTeamsPerSlot) {
            free = false;
            break;
          }
        }
        if (free) {
          anyWindowFree = true;
          break;
        }
      }
      if (!anyWindowFree) {
        return 'نعتذر، اكتملت مواعيد هذا اليوم — لا يوجد فريق متاح لمدة الخدمة. يرجى اختيار يوم آخر.';
      }
      return null;
    }

    final int reqStart = widget.serviceDate!.hour;
    final int reqEnd = reqStart + widget.hours!;
    if (reqStart < openStart || reqEnd > openEnd) {
      return 'الوقت المختار خارج ساعات عمل منطقتك في هذا اليوم. يرجى اختيار وقت آخر.';
    }
    for (int h = reqStart; h < reqEnd; h++) {
      final key = '${bookingDate}_${h.toString().padLeft(2, '0')}:00';
      if (((slots[key] as num?)?.toInt() ?? 0) >= maxTeamsPerSlot) {
        return 'نعتذر، هذا الوقت محجوز بالكامل حالياً. يرجى اختيار وقت بدء آخر.';
      }
    }

    return null;
  }

  Future<void> _handlePayment() async {
    if (_isLoading) return;

    if (_needsPhoneUpdate && _phoneController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("يرجى التأكد من بيانات التواصل")));
      return;
    }

    if (!_agreeToTerms) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("يرجى الموافقة على الشروط والأحكام")));
      return;
    }

    if (_currentUser == null) {
      final guest = FirebaseAuth.instance.currentUser == null;
      // مسجّل والبيانات غائبة = فشل الجلب الأول — نعيد المحاولة فعلياً كي تكون
      // «يرجى المحاولة مجدداً» صادقة (لا شيء آخر كان يعيد استدعاء _loadUserData).
      if (!guest) _loadUserData();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
          guest ? "يرجى تسجيل الدخول لإتمام الدفع"
                : "جارٍ تحميل بيانات الحساب، يرجى المحاولة مجدداً")));
      return;
    }

    setState(() => _isLoading = true);

    try {
      final bool isHourly = widget.hours != null && widget.serviceDate != null;
      if (isHourly) {
        final capacityError = await _checkHourlyCapacity();
        if (capacityError != null) {
          setState(() => _isLoading = false);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(capacityError, style: const TextStyle(fontWeight: FontWeight.bold)),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 4),
            ));
          }
          return;
        }
      }

      // 1. Update user phone if changed
      if (_needsPhoneUpdate) {
        await FirebaseFirestore.instance.collection('users').doc(_currentUser?.uid).update({
          'phone': _phoneController.text.trim(),
        });
      }

      // (إعادة محاولة) مستند الطلب أُنشئ في محاولة سابقة فشلت/أُلغيت: إعادة
      // كتابته كانت تُرفض من قواعد Firestore (permission-denied) فتفشل **كل**
      // محاولة دفع ثانية من هذه الشاشة حتى يهجر العميل الحجز كاملاً. نسكّ
      // معرّفاً جديداً للمحاولة — ومعه given_id جديد لميسر، فلا يصطدم بدفعة
      // فاشلة استهلكت القديم، وبمبلغٍ حاضر لا مجمّد من المحاولة الأولى.
      if (_pendingOrderCreated) {
        setState(_mintFreshPendingOrderId);
      }

      final String finalOrderId = _pendingOrderId;

      if (_selectedPaymentMethod == 'subscription') {
        await _processUnifiedSuccess(finalOrderId, 'subscription', isFree: true);

      } else if (_selectedPaymentMethod == 'wallet') {
        // --- Wallet Payment: Atomic balance deduction ---
        // رصيد غير مجلوب (فشل الجلب) ≠ رصيد صفري: لا نتهم العميل بأن «رصيدك
        // 0.00» من قيمة لم تُجلب أصلاً — نعيد الجلب فعلياً ونطلب المحاولة.
        if (_walletBalance == null) {
          setState(() => _isLoading = false);
          _fetchWalletBalance();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
              'تعذّر التحقق من رصيد محفظتك — يرجى المحاولة مجدداً',
              style: GoogleFonts.tajawal(),
            ),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ));
          return;
        }
        if (_walletBalance! < totalWithVat) {
          setState(() => _isLoading = false);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
              'رصيد محفظتك غير كافٍ. رصيدك الحالي: ${_walletBalance!.toStringAsFixed(2)} ر.س',
              style: GoogleFonts.tajawal(),
            ),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ));
          return;
        }
        // الخصم من المحفظة يتم خادمياً داخل _processUnifiedSuccess عبر
        // payWithWallet(orderId) بعد إنشاء الطلب — ذرّياً مع قلب is_paid على الطلب،
        // فلا يمكن تزوير is_paid ولا الخصم من العميل.
        await _processUnifiedSuccess(finalOrderId, 'wallet', isFree: false);

      } else if (_selectedPaymentMethod == 'tamara') {
        // تمارا تتطلّب وجود الطلب مسبقاً كي يجلب الخادم المبلغ الحقيقي (منع التلاعب)
        // — ننشئه is_paid=false قبل فتح الجلسة، والـ webhook يؤكّده لاحقاً.
        if (widget.contractId == null) {
          await _createUnpaidServiceOrder(finalOrderId);
        }
        String? checkoutUrl = await _tamaraService.createCheckoutSession(
          // للعقد: مرجع تمارا = معرّف العقد كي يقلب الـ webhook is_paid عليه فيُفعّله.
          orderId: widget.contractId ?? finalOrderId,
          amount: totalWithVat,
          customerPhone: _phoneController.text.trim(),
          customerName: _currentUser?.name ?? 'عميل زيارة',
        );

        if (checkoutUrl != null && mounted) {
          setState(() => _isLoading = false);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => TamaraCheckoutScreen(
                checkoutUrl: checkoutUrl,
                amount: totalWithVat,
                orderId: finalOrderId,
                serviceType: widget.serviceName,
                location: widget.location ?? const GeoPoint(24.7136, 46.6753),
                hours: widget.hours,
                serviceDate: widget.serviceDate,
                zoneName: widget.zoneName,
                workerCount: widget.workerCount,
                customerName: _currentUser?.name,
                customerPhone: _phoneController.text,
                couponCode: _appliedCoupon,
                discountAmount: _discountAmount,
                contractId: widget.contractId,
                planVisits: widget.planVisits,
                serviceMeta: widget.serviceMeta,
                onOrderCreated: (code) async {
                  if (!mounted) return;
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(
                      builder: (_) => ZyiarahOrderSuccessScreen(
                        orderCode: code,
                        title: widget.contractId != null
                            ? 'تم تفعيل الباقة بنجاح! 🎉'
                            : 'تم استلام طلبك بنجاح!',
                        subtitle: widget.contractId != null
                            ? 'تم تفعيل باقتك وإضافة الزيارات لحسابك.'
                            : 'شكراً لثقتك بزيارة، طلبك الآن قيد المعالجة.',
                      ),
                    ),
                    (route) => route.isFirst,
                  );
                },
              ),
            ),
          );
        } else {
          throw Exception('خطأ في بدء جلسة تمارا');
        }

      } else if (_selectedPaymentMethod == 'card') {
        // Moyasar SDK — Credit Card
        // ننشئ الطلب is_paid=false قبل فتح شاشة الدفع (كتمارا): لو نجح الخصم ثم
        // فشلت كتابة الطلب، يظل موجوداً ويؤكّده الـ webhook — فلا دفعة يتيمة بلا طلب.
        if (widget.contractId == null) {
          await _createUnpaidServiceOrder(finalOrderId, method: 'card');
        }
        setState(() => _isLoading = false);
        if (!mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MoyasarCardScreen(
              amountSAR: totalWithVat,
              description: 'خدمة زيارة - ${widget.serviceName}',
              orderId: finalOrderId,
              onSuccess: (paymentId) async {
                setState(() => _isLoading = true);
                await _processUnifiedSuccess(finalOrderId, 'card', paymentId: paymentId);
              },
              onFailure: (error) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(error, style: GoogleFonts.tajawal()),
                    backgroundColor: Colors.red.shade800,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    margin: const EdgeInsets.all(15),
                  ));
                }
              },
            ),
          ),
        );
        return;

      } else if (_selectedPaymentMethod == 'tabby') {
        // Tabby BNPL — أنشئ الطلب is_paid=false قبل فتح تابي (كالبطاقة/تمارا) كي يجده
        // الـ webhook ويؤكّده؛ بدونه دفعة تابي ناجحة قد لا تجد طلباً فيبقى يتيماً.
        if (widget.contractId == null) {
          await _createUnpaidServiceOrder(finalOrderId, method: 'tabby');
        }
        final webUrl = await TabbyService.createCheckoutUrl(
          amountSAR: totalWithVat,
          customerPhone: _phoneController.text.trim().isNotEmpty
              ? _phoneController.text.trim()
              : (_currentUser?.phone ?? '0500000000'),
          customerName: _currentUser?.name ?? 'عميل زيارة',
          customerEmail: _currentUser?.email ?? 'customer@zyiarah.com',
          // للعقد: مرجع تابي = معرّف العقد كي يقلب الـ webhook is_paid عليه فيُفعّله (كتمارا).
          orderId: widget.contractId ?? finalOrderId,
        );

        if (webUrl == null) {
          setState(() => _isLoading = false);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('تابي غير متاح لهذا الطلب حالياً'),
              backgroundColor: Colors.red,
            ));
          }
          return;
        }

        setState(() => _isLoading = false);
        if (!mounted) return;

        TabbyService.showCheckout(
          context: context,
          webUrl: webUrl,
          onSuccess: () async {
            setState(() => _isLoading = true);
            await _processUnifiedSuccess(finalOrderId, 'tabby');
          },
          onFailure: () {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('تم إلغاء الدفع عبر تابي'),
                backgroundColor: Colors.orange,
              ));
            }
          },
        );
        return;

      } else if (_selectedPaymentMethod == 'stc_pay') {
        // Moyasar STC Pay — أنشئ الطلب is_paid=false قبل شاشة الدفع (كالبطاقة/تمارا).
        if (widget.contractId == null) {
          await _createUnpaidServiceOrder(finalOrderId, method: 'stc_pay');
        }
        setState(() => _isLoading = false);
        if (!mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MoyasarStcScreen(
              amountSAR: totalWithVat,
              description: 'خدمة زيارة - ${widget.serviceName}',
              orderId: finalOrderId,
              onSuccess: (paymentId) async {
                setState(() => _isLoading = true);
                await _processUnifiedSuccess(finalOrderId, 'stc_pay', paymentId: paymentId);
              },
              onFailure: (error) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(error, style: GoogleFonts.tajawal()),
                    backgroundColor: Colors.red.shade800,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    margin: const EdgeInsets.all(15),
                  ));
                }
              },
            ),
          ),
        );
        return;
      }

    } catch (e) {
      debugPrint("PAYMENT_ERROR: $e");
      if (mounted) {
        setState(() => _isLoading = false);
        GlobalErrorHandler.handleError(e);
      }
    }
  }

  /// ينشئ طلب خدمة (ساعة/كنب) بـ is_paid=false قبل فتح جلسة تمارا — كي يجد
  /// الخادم المبلغ الحقيقي. لا يُعيّن سائقاً (يتكفّل به sweepUnassignedPaidOrders
  /// بعد أن يقلب الـ webhook is_paid). checkout_screen يتخطّى الإنشاء إن وُجد.
  Future<void> _createUnpaidServiceOrder(String id, {String method = 'tamara'}) async {
    final bool isHourly = widget.hours != null && widget.serviceDate != null;
    final orderRef = FirebaseFirestore.instance.collection('orders').doc(id);
    await FirebaseFirestore.instance.runTransaction((transaction) async {
      // حارس وجود (كما في _processUnifiedSuccess): إعادة كتابة مستند قائم تُقيَّم
      // كتحديث تمنعه قواعد Firestore فتفشل المعاملة كلها بـ permission-denied.
      // القراءة قبل العدّاد (قراءات المعاملة قبل كتاباتها إلزاماً) — وتوفّر أيضاً
      // حرق رقم طلب على محاولة مكررة (نقرة مزدوجة متسارعة مثلاً).
      final snap = await transaction.get(orderRef);
      if (snap.exists) return;
      final nextId = await ZyiarahCounterService().getNextOrderNumber(transaction);
      final code = ZyiarahOrderUtil.formatSmartCode(nextId);
      transaction.set(orderRef, {
        'code': code,
        'client_id': _currentUser?.uid,
        'client_name': _currentUser?.name ?? 'عميل زيارة',
        'client_phone': _phoneController.text.trim(),
        'user_phone': _phoneController.text.trim(),
        'client_email': _currentUser?.email,
        'service_type': widget.serviceName,
        'service_name': widget.serviceName,
        'amount': totalWithVat,
        'is_paid': false,
        'status': 'pending',
        'location': widget.location ?? const GeoPoint(24.7136, 46.6753),
        'payment_method': method,
        'created_at': FieldValue.serverTimestamp(),
        'hours_contracted': widget.hours ?? 4,
        'service_date': widget.serviceDate != null ? Timestamp.fromDate(widget.serviceDate!) : null,
        'zone_name': widget.zoneName,
        'worker_count': widget.workerCount,
        'coupon_code': _appliedCoupon,
        'discount_amount': _discountAmount,
        if (widget.serviceMeta != null) 'service_meta': widget.serviceMeta,
        if (isHourly && widget.serviceDate != null) ...{
          'booking_date': '${widget.serviceDate!.year}-'
              '${widget.serviceDate!.month.toString().padLeft(2, '0')}-'
              '${widget.serviceDate!.day.toString().padLeft(2, '0')}',
          'booking_time_slot':
              '${widget.serviceDate!.hour.toString().padLeft(2, '0')}:00',
        },
      });
    });
    // المستند الآن قائم بمبلغ هذه اللحظة — أي محاولة/تغيير لاحق يسكّ معرّفاً جديداً.
    _pendingOrderCreated = true;
  }

  /// بيانات الطلب الكاملة داخل metadata الدفعة — كي يستطيع verifyMoyasarPayment خادميّاً
  /// إنشاء الطلب إن فشل العميل في إنشائه (الدفع الأصلي Apple/Google/Samsung Pay ينشئ الطلب
  /// بعد الخصم، وقد يفشل بسبب الحالة/الخلفية بعد شاشة الدفع). القيم نصّية (شرط Moyasar).
  Map<String, String> _nativePayMeta() {
    final bool isHourly = widget.hours != null && widget.serviceDate != null;
    return {
      // للعقد/الصيانة نستخدم معرّفهما لا _pendingOrderId العشوائي — كي يجد المُصالِح
      // الخادمي السجلّ الصحيح فيؤكّده (العقد يُفعَّل عبر activateContractOnPaid) بدل
      // إنشاء «طلب خدمة» خاطئ لا يُفعّل الاشتراك.
      'order_id': widget.contractId ?? _pendingOrderId,
      'client_id': FirebaseAuth.instance.currentUser?.uid ?? '',
      'client_name': _currentUser?.name ?? 'عميل زيارة',
      'service_name': widget.serviceName,
      'is_hourly': isHourly ? '1' : '0',
      'hours': (widget.hours ?? 4).toString(),
      'worker_count': widget.workerCount.toString(),
      'zone_name': widget.zoneName ?? '',
      'lat': (widget.location?.latitude ?? 24.7136).toStringAsFixed(6),
      'lng': (widget.location?.longitude ?? 46.6753).toStringAsFixed(6),
      'service_date': widget.serviceDate?.toIso8601String() ?? '',
      'client_phone': _phoneController.text.trim(),
      // (تفصيل الخدمة عبر Apple/Google/Samsung Pay) نحمله كنصّ JSON كي يعيد الخادم
      // بناءه إن أنشأ الطلب من الـ metadata (سيناريو خلفية Apple Pay) — وإلّا ضاع
      // تفصيل المكيفات/الكنب/السيارة على الطلب المدفوع أصلياً، فلا تراه الإدارة/السائق.
      if (widget.serviceMeta != null)
        'service_meta_json': jsonEncode(widget.serviceMeta),
    };
  }

  /// Unified Success Handler
  Future<void> _processUnifiedSuccess(String id, String method, {bool isFree = false, String? paymentId}) async {
    final double amountToSave = isFree ? 0.0 : totalWithVat;
    // code is generated per-branch below; maintenance uses id, contract uses contractId,
    // regular order generates atomically inside the transaction
    String code = '';

    try {
    // (0) تأكيد خادمي فوري: verifyMoyasarPayment يُنشئ الطلب من metadata إن غاب ويقلب
    // is_paid — فوري وموثوق، لا يعتمد على كتابة العميل (تفشل مع Apple Pay بعد تعليق
    // الخلفية على iOS). بهذا يظهر الطلب مؤكّداً لحظةَ نجاح الدفع دون انتظار المُصالِح الدوري.
    if (!isFree && paymentId != null && method != 'wallet') {
      try {
        final vres = await FirebaseFunctions.instance
            .httpsCallable('verifyMoyasarPayment').call({
          'paymentId': paymentId,
          'orderId': widget.contractId ?? id,
        });
        // (#1) الخادم حجب الطلب لدفعٍ ناقص صارخ (Tier B) وأعاد المبلغ — لا نتابع للنجاح.
        // مطفأ فعليّاً ما دام ENFORCE_PRICE_TIER_B=false خادميّاً، لكنه العقد الجاهز للتفعيل.
        final vdata = vres.data;
        if (vdata is Map && vdata['blocked'] == true) {
          if (mounted) {
            setState(() => _isLoading = false);
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('تعذّر تأكيد الدفع — طلبكِ قيد المراجعة، وسيُعاد مبلغكِ إن لزم.'),
              backgroundColor: Colors.orange,
            ));
          }
          return;
        }
      } catch (e) {
        // لا نرمي: المُصالِح الخادمي الدوري يضمن الطلب احتياطاً خلال دقائق.
        debugPrint('[verify-first non-fatal] $e');
      }
    }
    // 1. Update Database
    if (widget.contractId != null) {
      code = widget.contractId!;
      // التفعيل (status='active') + منح visits_remaining + توليد الزيارات + إشعار
      // العميل يتم كلّه خادميّاً في activateContractOnPaid عند قلب is_paid — لا نكتب
      // من العميل (القواعد تمنعه وتُغلق منح زيارات بلا دفع). قلب is_paid في كتلة أدناه.
    } else {
      final bool isHourly = widget.hours != null && widget.serviceDate != null;

      // إن كان الطلب أُنشئ مسبقاً (بطاقة/STC/تمارا تنشئه is_paid=false قبل الدفع)
      // فلا نُعيد إنشاءه — يتفادى عدّاداً مزدوجاً وكتابةً فوق المستند؛ نكتفي بكوده.
      final existingOrder = await FirebaseFirestore.instance.collection('orders').doc(id).get();
      if (existingOrder.exists) {
        code = (existingOrder.data()?['code'] as String?) ?? id;
      } else {
        // حقول الطلب مُجمَّعة مرّة واحدة كي نستخدمها في المعاملة وفي الاحتياطي معاً.
        final orderRef = FirebaseFirestore.instance.collection('orders').doc(id);
        final Map<String, dynamic> orderPayload = {
          'client_id': _currentUser?.uid,
          'client_name': _currentUser?.name ?? 'عميل زيارة',
          'client_phone': _phoneController.text.trim(),
          'user_phone': _phoneController.text.trim(),
          'client_email': _currentUser?.email,
          'service_type': widget.serviceName,
          'service_name': widget.serviceName,
          'amount': amountToSave,
          // is_paid يقلبه الخادم بعد التأكيد (verify/payWithWallet) — العميل لا يكتبه.
          'is_paid': false,
          // (Direct Dispatch) كل خدمة تصل بموعد (hours + serviceDate) تمرّ مباشرةً:
          // pending ⇒ فحص سعة ⇒ إسناد تلقائي ⇒ scheduled. وهذا يشمل الآن الكنب/السجاد
          // بعد أن صار يختار يوماً ووقتاً. ما يصل بلا موعد يبقى pending ويُسنَد يدوياً
          // من إدارة الطلبات (نظام الاعتمادات حُذف من الجذور — قرار المالك).
          'status': 'pending',
          'location': widget.location ?? const GeoPoint(24.7136, 46.6753),
          'payment_method': method,
          'created_at': FieldValue.serverTimestamp(),
          'hours_contracted': widget.hours ?? 4,
          'service_date': widget.serviceDate != null ? Timestamp.fromDate(widget.serviceDate!) : null,
          'zone_name': widget.zoneName,
          'worker_count': widget.workerCount,
          'coupon_code': _appliedCoupon,
          'discount_amount': _discountAmount,
          if (widget.serviceMeta != null) 'service_meta': widget.serviceMeta,
          // Capacity index fields — queried by ZyiarahCapacityService
          if (isHourly && widget.serviceDate != null) ...{
            'booking_date': '${widget.serviceDate!.year}-'
                '${widget.serviceDate!.month.toString().padLeft(2, '0')}-'
                '${widget.serviceDate!.day.toString().padLeft(2, '0')}',
            'booking_time_slot':
                '${widget.serviceDate!.hour.toString().padLeft(2, '0')}:00',
          },
        };
        try {
          // Atomic: increment counter + create order in one Transaction
          await FirebaseFirestore.instance.runTransaction((transaction) async {
            final nextId = await ZyiarahCounterService().getNextOrderNumber(transaction);
            code = ZyiarahOrderUtil.formatSmartCode(nextId);
            transaction.set(orderRef, {...orderPayload, 'code': code});
          });
        } catch (txErr) {
          debugPrint('[order create tx failed → fallback set] $txErr');
          try {
            code = 'ZY-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}';
            await orderRef.set({...orderPayload, 'code': code, 'counter_fallback': true});
          } catch (fbErr) {
            // لا نرمي: الدفع الأصلي (Apple/Google/Samsung Pay) قد يفشل إنشاؤه للطلب بعد
            // الخصم (حالة/شبكة/خلفية بعد شاشة الدفع). نتابع إلى verifyMoyasarPayment الذي
            // يُنشئ الطلب خادميّاً من metadata الدفعة ويؤكّده — فلا تبقى «دفعة يتيمة» أبداً.
            debugPrint('[client create failed → server verify will create from metadata] $fbErr');
            if (code.isEmpty) code = _pendingOrderId.substring(0, 6).toUpperCase();
          }
        }
      }

      // تعيين السائق (للساعة) وإشعار العميل يُنقَلان لمهمة الخلفية أدناه حتى لا
      // يُبطئا ظهور شاشة النجاح — كلاهما غير حرج ولا يلمس واجهة المستخدم.
    }

    // 1b. تأكيد الدفع خادمياً → يقلب is_paid على الطلب المُنشأ للتوّ (أنشأه العميل
    // is_paid=false). هذا ما يُغلق سكّ المحفظة: لا يمكن تزوير is_paid من العميل.
    // يُتخطّى للعقد (لا مستند order) وللنقد والاشتراك المجاني.
    if (!isFree) {
      if (widget.contractId != null) {
        // اشتراك: نقلب is_paid على العقد خادميّاً → يُفعّله activateContractOnPaid
        // (status='active' + منح الزيارات + توليدها). تمارا تقلبه عبر webhook.
        if (method == 'wallet') {
          await FirebaseFunctions.instance.httpsCallable('payContractWithWallet').call({
            'contractId': widget.contractId,
          });
          if (mounted && _walletBalance != null) {
            setState(() => _walletBalance = _walletBalance! - amountToSave);
          }
        } else if (paymentId != null) {
          try {
            await FirebaseFunctions.instance.httpsCallable('verifyMoyasarPayment').call({
              'paymentId': paymentId,
              'orderId': widget.contractId,
            });
          } catch (e) {
            debugPrint('[verify contract] non-fatal: $e');
          }
        }
      } else if (method == 'wallet') {
        await FirebaseFunctions.instance.httpsCallable('payWithWallet').call({
          'amount': amountToSave,
          'orderId': id,
          'description': 'دفع خدمة: ${widget.serviceName}',
        });
        if (mounted && _walletBalance != null) {
          setState(() => _walletBalance = _walletBalance! - amountToSave);
        }
      } else if (paymentId != null) {
        try {
          await FirebaseFunctions.instance.httpsCallable('verifyMoyasarPayment').call({
            'paymentId': paymentId,
            'orderId': id,
          });
        } catch (e) {
          // الـ webhook يؤكّد خادمياً حتى لو فشل هذا النداء.
          debugPrint('[verifyMoyasar] non-fatal: $e');
        }
      }
    }

    // 2. الفاتورة (توليد PDF + رفعه للتخزين) وإشعار الإدارة بالبريد — الأثقل زمنياً
    // (2–5 ثوانٍ). لا يحتاجهما العميل قبل رؤية شاشة النجاح، فنُشغّلهما في الخلفية
    // بعد الانتقال مباشرةً. نلتقط القيم الأولية الآن لأن State يُتلَف عند الانتقال —
    // فلا نلمس widget/controllers داخل مهمة الخلفية.
    final String bgCollection = widget.contractId != null ? 'contracts' : 'orders';
    final double bgTotal = totalWithVat;
    final double bgVat = vatAmount;
    final double bgDiscount = _discountAmount;
    final String? bgCoupon = _appliedCoupon;
    final String bgServiceName = widget.serviceName;
    final String bgClientName = _currentUser?.name ?? 'عميل زيارة';
    final String bgClientPhone = _phoneController.text;
    final String? bgClientEmail = _currentUser?.email;
    final String bgDateTime = widget.serviceDate != null
        ? intl.DateFormat('yyyy-MM-dd').format(widget.serviceDate!)
        : 'غير محدد';
    final int bgWorkerCount = widget.workerCount;
    final String? bgZone = widget.zoneName;
    final bool bgIsRegularOrder = widget.contractId == null;
    final bool bgIsHourly = widget.hours != null && widget.serviceDate != null;
    final DateTime? bgServiceDate = widget.serviceDate;
    final int? bgHours = widget.hours;
    final String? bgUid = _currentUser?.uid;
    final ZyiarahOrderService bgOrderService = _orderService;

    // ignore: unawaited_futures
    Future(() async {
      try {
        // تعيين السائق (للساعة) + إشعار العميل بإنشاء الطلب — للطلبات العادية فقط.
        if (bgIsRegularOrder) {
          if (bgIsHourly) {
            try {
              await bgOrderService.autoAssignDriverForHourly(
                orderId: id,
                startDateTime: bgServiceDate!,
                durationHours: bgHours!,
              );
            } catch (e) {
              debugPrint('[AutoAssign bg] non-fatal: $e');
            }
          }
          try {
            await ZyiarahMessagingService().notifyOrderCreated(
              clientId: bgUid ?? '',
              orderCode: code,
              type: 'cleaning',
              serviceName: bgServiceName,
              orderId: id,
            );
          } catch (e) {
            debugPrint('[notifyOrderCreated bg] non-fatal: $e');
          }
        }

        final String qrData = ZatcaService.generateZatcaQrCode(
          timestamp: DateTime.now(),
          totalAmount: bgTotal,
          vatAmount: bgVat,
        );
        final String? invoiceUrl = await ZyiarahPdfService.generateAndUploadInvoice(
          orderId: id,
          orderCode: code,
          amount: bgTotal,
          qrData: qrData,
          serviceName: bgServiceName,
          discountAmount: bgDiscount,
          couponCode: bgCoupon,
          collectionPath: bgCollection,
        );
        await ZyiarahMessagingService().notifyNewOrder({
          'code': code,
          'client_name': bgClientName,
          'amount': amountToSave,
          'service_type': bgServiceName,
          'client_phone': bgClientPhone,
          'date_time': bgDateTime,
          'worker_count': bgWorkerCount,
          'zone': bgZone,
          'coupon': bgCoupon,
        }, customerEmail: bgClientEmail, invoiceUrl: invoiceUrl);
      } catch (e) {
        debugPrint('[post-order background: invoice/notify] non-fatal: $e');
      }
    });

    // 3. Final Step — شاشة نجاح موحدة لجميع المسارات (فوراً)
    if (mounted) {
      setState(() => _isLoading = false);
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => ZyiarahOrderSuccessScreen(
            orderCode: code,
            title: widget.contractId != null
                ? 'تم تفعيل الباقة بنجاح! 🎉'
                : 'تم استلام طلبك بنجاح!',
            subtitle: widget.contractId != null
                ? 'تم تفعيل باقتك وإضافة الزيارات لحسابك. يمكنك الآن حجز زياراتك.'
                : 'شكراً لثقتك بزيارة، طلبك الآن قيد المعالجة وسنقوم بإخطارك بكل جديد.',
          ),
        ),
        (route) => route.isFirst,
      );
    }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      if (paymentId != null) {
        // دفعٌ ناجح بمعرّف (بطاقة/Apple/Google/Samsung/STC) — لا نُظهر أي خطأ إطلاقاً.
        // الطلب مضمون خادميّاً (verifyMoyasarPayment الفوري أعلاه + المُصالِح الدوري)،
        // فنعرض شاشة النجاح دائماً كما طلب المالك: «لا خطأ بعد نجاح الدفع».
        debugPrint('[non-fatal after successful payment → show success] $e');
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => ZyiarahOrderSuccessScreen(
              orderCode: code.isNotEmpty ? code : id.substring(0, 6).toUpperCase(),
              title: widget.contractId != null
                  ? 'تم تفعيل الباقة بنجاح! 🎉'
                  : 'تم استلام طلبك بنجاح!',
              subtitle: widget.contractId != null
                  ? 'تم تفعيل باقتك وإضافة الزيارات لحسابك.'
                  : 'شكراً لثقتك بزيارة، طلبك الآن قيد المعالجة وسنخطرك بكل جديد.',
            ),
          ),
          (route) => route.isFirst,
        );
      } else {
        // مسار المحفظة/بلا معرّف دفع — قد يكون الخصم فشل فعلاً، فنُبقي رسالة الدعم.
        showDialog(
          context: context,
          builder: (ctx) => Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              title: const Text('تعذّر إتمام الطلب'),
              content: Text(
                  'إن كنت قد دُفعت فلا تقلق — سيُعالَج طلبك تلقائياً أو تواصل مع الدعم '
                  'مع الرقم المرجعي: ${code.isNotEmpty ? code : id}. لن يُخصم منك مرتين.'),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.of(context).popUntil((r) => r.isFirst);
                  },
                  child: const Text('حسناً'),
                ),
              ],
            ),
          ),
        );
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF1F5F9),
        body: Stack(
          children: [
            SingleChildScrollView(
              child: Column(
                children: [
                  _buildInvoiceHeader(),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        if (_needsPhoneUpdate) _buildPhoneUpdateCard(),
                        const SizedBox(height: 20),
                        _buildOrderDetailsCard(),
                        const SizedBox(height: 20),
                        // الكوبونات للطلبات فقط لا الاشتراكات — خصمُ اشتراكٍ يكسر
                        // تطابق planPrice الخادمي فلا يُفعَّل العقد رغم الدفع.
                        if (widget.contractId == null) ...[
                          _buildCouponSection(),
                          const SizedBox(height: 20),
                        ],
                        // الموافقة على الشروط تحت كود الخصم مباشرةً (بدل أسفل الصفحة).
                        _buildTermsAndConditions(),
                        const SizedBox(height: 20),
                        _buildPaymentMethods(),
                        const SizedBox(height: 100),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            _buildBottomButton(),
            if (_isLoading)
              Container(
                color: Colors.black.withValues(alpha: 0.3),
                child: const Center(child: CircularProgressIndicator(color: Color(0xFF660033))),
              ),
          ],
        ),
      ),
    ),
  );
  }

  Widget _buildInvoiceHeader() {
    // رأس مبسّط — زر الرجوع وعنوان فقط. حُذف ملخّص «الفاتورة التقديرية»
    // (المجموع/الضريبة/الإجمالي) بطلب المالك؛ التفصيل الكامل يظهر أسفل الشاشة في
    // بطاقة «تفاصيل الفاتورة» فلا داعي لتكراره هنا. (الشاشة مدفوعة بلا AppBar،
    // فزر الرجوع ضروري كي لا يعلق المستخدم في صفحة الدفع.)
    return Container(
      // نضيف ارتفاع شريط الحالة/النوتش للبادينغ العلوي (الشاشة مدفوعة بلا AppBar،
      // فبدونه يقع زر الرجوع والعنوان خلف الشريط في أعلى الشاشة).
      padding: EdgeInsets.fromLTRB(8, MediaQuery.of(context).padding.top + 10, 16, 16),
      decoration: const BoxDecoration(
        color: Color(0xFF660033),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
            onPressed: () => Navigator.of(context).maybePop(),
            tooltip: 'رجوع',
          ),
          const SizedBox(width: 4),
          Text(
            'إتمام الطلب',
            style: GoogleFonts.tajawal(
                color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildPhoneUpdateCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.phone_android_rounded, color: Colors.red),
              const SizedBox(width: 8),
              Text('مطلوب رقم الجوال للتواصل', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.red)),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              hintText: 'مثال: 0501234567',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderDetailsCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('تفاصيل الفاتورة', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 16)),
          const Divider(height: 30),
          _buildRowDetail('الخدمة', widget.serviceName),
          if (_isStoreOrder)
            _buildRowDetail('عدد المنتجات', '${widget.serviceMeta!['total_qty'] ?? ''}'),
          if (widget.hours != null && !_isStoreOrder)
            _buildRowDetail('المدة', '${widget.hours} ساعات'),
          if (!_isStoreOrder)
            _buildRowDetail('عدد العاملات',
                widget.workerCount == 1
                    ? 'عاملة واحدة'
                    : widget.workerCount == 2
                        ? 'عاملتان'
                        : '${widget.workerCount} عاملات'),
          if (widget.serviceDate != null)
            _buildRowDetail(_isStoreOrder ? 'موعد التوصيل' : 'التاريخ',
                intl.DateFormat('yyyy-MM-dd').format(widget.serviceDate!)),
          if (widget.zoneName != null) _buildRowDetail('المنطقة', widget.zoneName!),
          const Divider(height: 30),
          _buildRowDetail('المبلغ الأساسي', '${subtotal.toStringAsFixed(2)} ر.س'),
          if (_surgeFactor > 1.0)
            _buildRowDetail(
              '🔥 تسعيرة ذروة (+${((_surgeFactor - 1) * 100).toStringAsFixed(0)}%)',
              '+${(widget.amount * (_surgeFactor - 1)).toStringAsFixed(2)} ر.س',
              isSurge: true,
            ),
          if (_discountAmount > 0)
            _buildRowDetail('الخصم ($_appliedCoupon)', '-${_discountAmount.toStringAsFixed(2)} ر.س', isDiscount: true),
          _buildRowDetail('الضريبة (15%)', '${vatAmount.toStringAsFixed(2)} ر.س'),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('الإجمالي المستحق', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 18)),
              Text('${totalWithVat.toStringAsFixed(2)} ر.س', 
                style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 18, color: const Color(0xFF660033))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRowDetail(String label, String value, {bool isDiscount = false, bool isSurge = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.tajawal(color: Colors.grey[600], fontSize: 14)),
          Text(value, style: GoogleFonts.tajawal(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: isSurge ? Colors.orange.shade700 : isDiscount ? Colors.red : Colors.black,
          )),
        ],
      ),
    );
  }

  Widget _buildCouponSection() {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('كود الخصم', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _couponController,
                  decoration: InputDecoration(
                    hintText: 'أدخل كود الخصم هنا',
                    hintStyle: GoogleFonts.tajawal(fontSize: 13),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                  ),
                  onChanged: (val) {
                    if (_appliedCoupon != null) {
                      setState(() {
                        _appliedCoupon = null;
                        _discountAmount = 0.0;
                        // الإجمالي تغيّر ومستند الطلب (إن وُجد) مجمّد على القديم.
                        if (_pendingOrderCreated) _mintFreshPendingOrderId();
                      });
                    }
                  },
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: _isValidatingCoupon ? null : _validateCoupon,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF660033),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isValidatingCoupon 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text('تطبيق', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          if (_appliedCoupon != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('تم تطبيق الكود: $_appliedCoupon', 
                style: GoogleFonts.tajawal(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
    );
  }

  Widget _buildPaymentMethods() {
    final String publishableKey =
        dotenv.env['MOYASAR_PUBLISHABLE_KEY'] ?? '';
    final bool moyasarReady = publishableKey.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('اختر طريقة الدفع',
            style: GoogleFonts.tajawal(
                fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 15),

        // «الدفع بالباقة» أُزيل عمداً: زيارات الاشتراك مُولّدة ومجدولة مسبقاً (SUB-*)،
        // فليست رصيداً يُنفق على حجوزات عادية — استخدامها هنا كان يخصم مزدوجاً ويجعل
        // العدّاد سالباً. العميل يستهلك اشتراكه عبر زياراته المجدولة فقط.

        // --- بطاقة ائتمانية (Moyasar) ---
        if (moyasarReady)
          _buildPaymentOption(
            id: 'card',
            title: 'بطاقة فيزا / مدى',
            subtitle: 'دفع آمن عبر ميسر',
            icon: Icons.credit_card,
            logoAsset: 'assets/payment/mada.png',
          ),

        // --- Apple Pay (iOS only — Moyasar SDK) ---
        if (_isNativeIOS && moyasarReady) ...[
          const SizedBox(height: 16),
          Row(children: [
            const Expanded(child: Divider()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text('أو ادفع بـ',
                  style: GoogleFonts.tajawal(color: Colors.grey, fontSize: 13)),
            ),
            const Expanded(child: Divider()),
          ]),
          const SizedBox(height: 12),
          _gateNative(ApplePay(
            config: PaymentConfig(
              publishableApiKey: publishableKey,
              amount: (totalWithVat * 100).round(),
              description: 'زيارة - ${widget.serviceName}',
              givenID: MoyasarUtil.givenIdFromOrder(_pendingOrderId), // UUID صالح لـ Moyasar (منع الشحن المزدوج)
              metadata: _nativePayMeta(),
              applePay: ApplePayConfig(
                merchantId: 'merchant.com.zyiarah.app',
                label: 'زيارة',
                manual: false,
                saveCard: false,
              ),
            ),
            onPaymentResult: _onApplePayResult,
          )),
        ],

        // --- Google Pay (Android only) ---
        if (_isNativeAndroid && _googlePayConfigFuture != null) ...[
          const SizedBox(height: 16),
          Row(children: [
            const Expanded(child: Divider()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text('أو ادفع بـ',
                  style: GoogleFonts.tajawal(color: Colors.grey, fontSize: 13)),
            ),
            const Expanded(child: Divider()),
          ]),
          const SizedBox(height: 12),
          FutureBuilder<PaymentConfiguration>(
            future: _googlePayConfigFuture,
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const SizedBox.shrink();
              return _gateNative(GooglePayButton(
                paymentConfiguration: snapshot.data!,
                paymentItems: [
                  PaymentItem(
                    label: 'زيارة - ${widget.serviceName}',
                    amount: totalWithVat.toStringAsFixed(2),
                    status: PaymentItemStatus.final_price,
                  ),
                ],
                type: GooglePayButtonType.pay,
                margin: EdgeInsets.zero,
                onPaymentResult: (result) async {
                  setState(() => _isLoading = true);
                  final messenger = ScaffoldMessenger.of(context);
                  try {
                    final gpayPaymentId = await MoyasarService.processGooglePayToken(
                      googlePayToken: result,
                      amountSAR: totalWithVat,
                      description: 'خدمة زيارة - ${widget.serviceName}',
                      orderId: _pendingOrderId,
                      metadata: _nativePayMeta(),
                    );
                    if (mounted) {
                      await _processUnifiedSuccess(_pendingOrderId, 'google_pay', paymentId: gpayPaymentId);
                    }
                  } catch (e) {
                    if (mounted) setState(() => _isLoading = false);
                    messenger.showSnackBar(SnackBar(
                      content: Text(
                        e.toString().replaceAll('Exception: ', ''),
                        style: GoogleFonts.tajawal(),
                      ),
                      backgroundColor: Colors.red.shade800,
                    ));
                  }
                },
                loadingIndicator: const Center(
                  child: CircularProgressIndicator(),
                ),
              ));
            },
          ),
        ],

        // --- Samsung Pay (Android — Moyasar SDK, auto-hides if unavailable) ---
        if (_isNativeAndroid) ...[
          Builder(builder: (context) {
            final samsungServiceId =
                dotenv.env['SAMSUNG_PAY_SERVICE_ID'] ?? '';
            if (samsungServiceId.isEmpty ||
                samsungServiceId.startsWith('REPLACE')) {
              return const SizedBox.shrink();
            }
            return Column(
              children: [
                const SizedBox(height: 16),
                Row(children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text('أو ادفع بـ',
                        style:
                            GoogleFonts.tajawal(color: Colors.grey, fontSize: 13)),
                  ),
                  const Expanded(child: Divider()),
                ]),
                const SizedBox(height: 12),
                _gateNative(SamsungPay(
                  config: PaymentConfig(
                    publishableApiKey: publishableKey,
                    amount: (totalWithVat * 100).round(),
                    description: 'زيارة - ${widget.serviceName}',
                    givenID: MoyasarUtil.givenIdFromOrder(_pendingOrderId), // UUID صالح لـ Moyasar (منع الشحن المزدوج)
                    metadata: _nativePayMeta(),
                    samsungPay: SamsungPayConfig(
                      serviceId: samsungServiceId,
                      merchantName: 'زيارة',
                      orderNumber: _pendingOrderId.length > 36
                          ? _pendingOrderId.substring(0, 36)
                          : _pendingOrderId,
                    ),
                  ),
                  onPaymentResult: _onSamsungPayResult,
                )),
              ],
            );
          }),
        ],

        // --- Tamara — بلا حدّ مبلغ (بطلب الإدارة؛ تمارا معتمدة في الحساب) ---
        if (_tamaraEnabled) ...[
          const SizedBox(height: 12),
          _buildPaymentOption(
            id: 'tamara',
            title: 'تمارا | Tamara',
            subtitle: 'قسم فاتورتك على 4 دفعات',
            icon: Icons.timer_outlined,
            color: const Color(0xFFE5A170),
            logoAsset: 'assets/payment/tamara.jpg',
          ),
        ],

        // --- Tabby ---
        if (TabbyService.isAvailable && totalWithVat >= 100) ...[
          const SizedBox(height: 12),
          _buildPaymentOption(
            id: 'tabby',
            title: 'تابي | Tabby',
            subtitle: 'اشتري الآن وادفع لاحقاً',
            icon: Icons.calendar_month_outlined,
            color: const Color(0xFF3DBEA3),
          ),
        ],

        // --- STC Pay ---
        if (moyasarReady) ...[
          const SizedBox(height: 12),
          _buildPaymentOption(
            id: 'stc_pay',
            title: 'STC Pay',
            subtitle: 'الدفع عبر محفظة STC',
            icon: Icons.phone_android_rounded,
            color: const Color(0xFF6A1B9A),
            logoAsset: 'assets/payment/stc_pay.png',
          ),
        ],

        // لا «دفع عند الاستلام»: أُزيل من الجذور — الدفع مقدَّم دائماً.

        // --- Wallet ---
        const SizedBox(height: 12),
        _buildWalletPaymentOption(),
      ],
    );
  }

  Widget _buildWalletPaymentOption() {
    final bool isSelected = _selectedPaymentMethod == 'wallet';
    final double? balance = _walletBalance;
    final bool hasSufficientBalance = balance != null && balance >= totalWithVat;
    return InkWell(
      onTap: () => setState(() => _selectedPaymentMethod = 'wallet'),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFF3E8F4) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? const Color(0xFF660033) : Colors.grey.shade200,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              // شعار «زيارة» لمحفظة زيارة — يتراجع للأيقونة إن تعذّر.
              child: Image.asset(
                'assets/logo.png',
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(
                    Icons.account_balance_wallet_rounded, color: Color(0xFF660033)),
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('محفظة زيارة', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 14)),
                  // ثلاث حالات صادقة بدل «0.00» الكاذبة عند فشل الجلب:
                  // فشل ⇒ رسالة + «إعادة المحاولة» تعيد الجلب فعلاً؛ جارٍ ⇒ نص
                  // تحميل؛ رصيد حقيقي ⇒ العرض المعتاد.
                  if (balance == null && _walletFetchFailed)
                    Row(
                      children: [
                        Text(
                          'تعذّر جلب الرصيد',
                          style: GoogleFonts.tajawal(
                            fontSize: 11,
                            color: Colors.red.shade600,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 6),
                        InkWell(
                          onTap: _fetchWalletBalance,
                          child: Text(
                            'إعادة المحاولة',
                            style: GoogleFonts.tajawal(
                              fontSize: 11,
                              color: const Color(0xFF660033),
                              fontWeight: FontWeight.bold,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ],
                    )
                  else if (balance == null)
                    Text(
                      'جارٍ تحميل الرصيد…',
                      style: GoogleFonts.tajawal(
                        fontSize: 11,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  else
                    Row(
                      children: [
                        Text(
                          'الرصيد: ${balance.toStringAsFixed(2)} ر.س',
                          style: GoogleFonts.tajawal(
                            fontSize: 11,
                            color: hasSufficientBalance ? Colors.green.shade700 : Colors.red.shade600,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (!hasSufficientBalance)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Text(
                              '(رصيد غير كافٍ)',
                              style: GoogleFonts.tajawal(fontSize: 10, color: Colors.red.shade400),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
            if (isSelected) const Icon(Icons.check_circle, color: Color(0xFF660033)),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentOption({
    required String id,
    required String title,
    required String subtitle,
    required IconData icon,
    Color? color,
    String? logoAsset, // شعار حقيقي (اختياري) — يتراجع للأيقونة إن تعذّر تحميله
  }) {
    bool isSelected = _selectedPaymentMethod == id;
    return InkWell(
      onTap: () => setState(() => _selectedPaymentMethod = id),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFF3E8F4) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isSelected ? const Color(0xFF660033) : Colors.grey.shade200, width: 2),
        ),
        child: Row(
          children: [
            logoAsset != null
                ? Container(
                    width: 48,
                    height: 48,
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Image.asset(
                      logoAsset,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) =>
                          Icon(icon, color: color ?? const Color(0xFF660033)),
                    ),
                  )
                : Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFF660033).withValues(alpha: 0.1) : Colors.grey.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: color ?? const Color(0xFF660033)),
                  ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 14)),
                  Text(subtitle, style: GoogleFonts.tajawal(fontSize: 11, color: Colors.grey[600])),
                ],
              ),
            ),
            if (isSelected) const Icon(Icons.check_circle, color: Color(0xFF660033)),
          ],
        ),
      ),
    );
  }

  Widget _buildTermsAndConditions() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _agreeToTerms ? const Color(0xFF660033) : Colors.grey.shade200),
      ),
      child: CheckboxListTile(
        value: _agreeToTerms,
        onChanged: (val) => setState(() => _agreeToTerms = val ?? false),
        activeColor: const Color(0xFF660033),
        title: Text(
          "أوافق على شروط الخدمة وسياسة الخصوصية الخاصة بزيارة",
          style: GoogleFonts.tajawal(fontSize: 12, fontWeight: FontWeight.bold),
        ),
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
      ),
    );
  }

  Widget _buildBottomButton() {
    final config = Provider.of<ZyiarahConfigProvider>(context);

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: Colors.white,
          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -2))],
        ),
        child: ElevatedButton(
          onPressed: _isLoading ? null : _handlePayment,
          style: ElevatedButton.styleFrom(
            backgroundColor: _agreeToTerms ? config.checkoutButtonColor : Colors.grey.shade300,
            foregroundColor: Colors.white,
            disabledBackgroundColor: Colors.grey.shade300,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: _isLoading
              ? const SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                )
              : Text('تأكيد وإتمام الدفع', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 18)),
        ),
      ),
    );
  }
}
