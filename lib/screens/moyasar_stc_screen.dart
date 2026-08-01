import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:moyasar/moyasar.dart';
import 'package:zyiarah/utils/moyasar_util.dart';

/// STC Pay OTP payment screen powered by Moyasar SDK.
///
/// Flow:
///  1. User enters STC Pay phone number (05xxxxxxxx).
///  2. [Moyasar.pay] initiates payment → Moyasar sends OTP to the phone.
///  3. Screen transitions to OTP entry.
///  4. [Moyasar.verifyOTP] confirms OTP → payment completes.
///  5. Success → [onSuccess] called with payment ID.
///  6. Failure → [onFailure] called with Arabic error string, screen pops.
class MoyasarStcScreen extends StatefulWidget {
  const MoyasarStcScreen({
    super.key,
    required this.amountSAR,
    required this.description,
    required this.orderId,
    required this.onSuccess,
    required this.onFailure,
  });

  final double amountSAR;
  final String description;
  final String orderId;
  final void Function(String paymentId) onSuccess;
  final void Function(String error) onFailure;

  @override
  State<MoyasarStcScreen> createState() => _MoyasarStcScreenState();
}

// ── Phase enum ───────────────────────────────────────────────────────────────

enum _Phase { phone, otp }

// ── State ────────────────────────────────────────────────────────────────────

class _MoyasarStcScreenState extends State<MoyasarStcScreen> {
  // Shared
  final Color _brand = const Color(0xFF660033);
  final Color _brandLight = const Color(0xFFE8D0E8);

  _Phase _phase = _Phase.phone;
  bool _isSubmitting = false;

  // Phone phase
  final TextEditingController _phoneController = TextEditingController();
  bool _phoneValid = false;

  // OTP phase
  final TextEditingController _otpController = TextEditingController();
  bool _otpValid = false;
  String _transactionUrl = '';

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _phoneController.addListener(_onPhoneChanged);
    _otpController.addListener(_onOtpChanged);
  }

  @override
  void dispose() {
    _phoneController
      ..removeListener(_onPhoneChanged)
      ..dispose();
    _otpController
      ..removeListener(_onOtpChanged)
      ..dispose();
    super.dispose();
  }

  // ── Listeners ──────────────────────────────────────────────────────────────

  void _onPhoneChanged() {
    final digits = _phoneController.text.replaceAll(RegExp(r'[^\d]'), '');
    final valid = digits.length == 10 && digits.startsWith('05');
    if (valid != _phoneValid) setState(() => _phoneValid = valid);
  }

  void _onOtpChanged() {
    final len = _otpController.text.trim().length;
    final valid = len >= 4 && len <= 10;
    if (valid != _otpValid) setState(() => _otpValid = valid);
  }

  // ── Phone formatting (mirrors Moyasar SDK logic) ──────────────────────────

  void _formatPhone(String text) {
    final digits = text.replaceAll(RegExp(r'[^\d]'), '');

    if (digits.isEmpty) {
      _phoneController.removeListener(_onPhoneChanged);
      _phoneController.value = const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
      _phoneController.addListener(_onPhoneChanged);
      return;
    }

    String processed;
    if (digits.startsWith('05')) {
      processed = digits.substring(0, min(digits.length, 10));
    } else {
      processed = '05${digits.substring(0, min(digits.length, 8))}';
    }

    String formatted;
    if (processed.length <= 3) {
      formatted = processed;
    } else if (processed.length <= 6) {
      formatted =
          '${processed.substring(0, 3)} ${processed.substring(3)}';
    } else {
      formatted =
          '${processed.substring(0, 3)} ${processed.substring(3, 6)} ${processed.substring(6)}';
    }

    if (_phoneController.text != formatted) {
      _phoneController.removeListener(_onPhoneChanged);
      _phoneController.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
      _phoneController.addListener(_onPhoneChanged);
      _onPhoneChanged();
    }
  }

  // ── API calls ──────────────────────────────────────────────────────────────

  String get _apiKey =>
      dotenv.env['MOYASAR_PUBLISHABLE_KEY'] ?? '';

  /// Step 1: initiate STC Pay — triggers OTP to phone.
  Future<void> _initiatePayment() async {
    if (!_phoneValid || _isSubmitting) return;
    setState(() => _isSubmitting = true);
    FocusManager.instance.primaryFocus?.unfocus();

    final config = PaymentConfig(
      publishableApiKey: _apiKey,
      amount: (widget.amountSAR * 100).round(),
      currency: 'SAR',
      description: widget.description,
      givenID: MoyasarUtil.givenIdFromOrder(widget.orderId), // UUID صالح لـ Moyasar (منع الشحن المزدوج)
      metadata: {'order_id': widget.orderId},
    );

    final digits =
        _phoneController.text.replaceAll(RegExp(r'[^\d]'), '');
    final request = PaymentRequest(config, StcRequestSource(mobile: digits));

    final result = await Moyasar.pay(
      apiKey: _apiKey,
      paymentRequest: request,
    );

    // لا نربط مصير النتيجة بحياة الشاشة: `if (!mounted) return` المبكر كان
    // يُسقط رد النداء كلياً إن رجعت المستخدمة أثناء الانتظار. ردود onSuccess/
    // onFailure تخاطب حالة **الأب** (ما زال حيّاً على شاشة الملخص) ولا تحتاج
    // هذه الشاشة — حارس mounted لأعمال الواجهة المحلية فقط.
    if (mounted) setState(() => _isSubmitting = false);

    if (result is PaymentResponse &&
        result.status == PaymentStatus.initiated) {
      // لم تكتمل دفعة بعد (مجرد إرسال OTP) — الرجوع هنا إلغاء مقصود بلا خصم.
      if (!mounted) return;
      final src = result.source as StcResponseSource;
      _transactionUrl = src.transactionUrl ?? '';
      setState(() => _phase = _Phase.otp);
    } else {
      final msg = _errorMessage(result);
      widget.onFailure(msg);
      if (mounted) Navigator.of(context).pop();
    }
  }

  /// Step 2: verify OTP — completes the payment.
  Future<void> _verifyOtp() async {
    if (!_otpValid || _isSubmitting) return;
    setState(() => _isSubmitting = true);
    FocusManager.instance.primaryFocus?.unfocus();

    final otpRequest = OtpRequestSource(otpValue: _otpController.text.trim());

    final result = await Moyasar.verifyOTP(
      transactionURL: _transactionUrl,
      otpRequest: otpRequest,
    );

    // حرج: `if (!mounted) return` كان **قبل** onSuccess — رجوعٌ أثناء نافذة
    // التحقق (1–3ث تبدو تعليقاً) كان يُسقط صامتاً دفعةً خصمتها ميسر فعلاً:
    // لا شاشة نجاح ولا تأكيد فوري، وتظنّها المستخدمة أُلغيت فتحجز من جديد
    // وتُخصم مرتين. الرد يخاطب حالة الأب الحيّة — يُستدعى دون شرط mounted.
    if (mounted) setState(() => _isSubmitting = false);

    if (result is PaymentResponse && result.status == PaymentStatus.paid) {
      widget.onSuccess(result.id);
      if (mounted) Navigator.of(context).pop();
    } else if (result is PaymentResponse &&
        result.status == PaymentStatus.initiated) {
      // Still pending — show message and let user retry
      if (mounted) _showSnack('رمز التحقق غير صحيح، يرجى المحاولة مجدداً');
    } else {
      final msg = _errorMessage(result);
      widget.onFailure(msg);
      if (mounted) Navigator.of(context).pop();
    }
  }

  String _errorMessage(dynamic result) {
    if (result is AuthError) return 'خطأ في المصادقة مع بوابة الدفع';
    if (result is ValidationError) {
      return result.message.isNotEmpty
          ? result.message
          : 'بيانات الدفع غير صحيحة';
    }
    if (result is NetworkError) return 'تعذّر الاتصال بالإنترنت';
    if (result is TimeoutError) return 'انتهت مهلة الاتصال، يرجى المحاولة مجدداً';
    if (result is ApiError) return result.message;
    if (result is PaymentResponse) {
      return 'فشلت عملية الدفع (${result.status.name})';
    }
    return 'حدث خطأ غير متوقع';
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.tajawal()),
        backgroundColor: _brand,
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // منع الرجوع أثناء إرسال/تحقق جارٍ: النتيجة قيد الوصول من ميسر — الخروج في
    // منتصفها يوحي بالإلغاء بينما قد تكون الدفعة خُصمت فعلاً (فتحجز المستخدمة
    // من جديد وتُخصم مرتين). يُفتح الرجوع تلقائياً فور انتهاء العملية.
    return PopScope(
      canPop: !_isSubmitting,
      child: Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: _brand,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'الدفع عبر STC Pay',
          style: GoogleFonts.tajawal(
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: _phase == _Phase.phone
              ? _PhoneStep(
                  key: const ValueKey('phone'),
                  controller: _phoneController,
                  isValid: _phoneValid,
                  isSubmitting: _isSubmitting,
                  brand: _brand,
                  brandLight: _brandLight,
                  amountSAR: widget.amountSAR,
                  onChanged: _formatPhone,
                  onSubmit: _initiatePayment,
                )
              : _OtpStep(
                  key: const ValueKey('otp'),
                  controller: _otpController,
                  isValid: _otpValid,
                  isSubmitting: _isSubmitting,
                  brand: _brand,
                  brandLight: _brandLight,
                  phone: _phoneController.text,
                  onSubmit: _verifyOtp,
                ),
        ),
      ),
      ),
    );
  }
}

// ── Phone Step ────────────────────────────────────────────────────────────────

class _PhoneStep extends StatelessWidget {
  const _PhoneStep({
    super.key,
    required this.controller,
    required this.isValid,
    required this.isSubmitting,
    required this.brand,
    required this.brandLight,
    required this.amountSAR,
    required this.onChanged,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final bool isValid;
  final bool isSubmitting;
  final Color brand;
  final Color brandLight;
  final double amountSAR;
  final void Function(String) onChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // STC Pay logo / icon row
          Center(
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFF6B0F6E).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.phone_android_rounded,
                size: 36,
                color: Color(0xFF6B0F6E),
              ),
            ),
          ),
          const SizedBox(height: 24),

          Text(
            'أدخل رقم هاتف STC Pay',
            style: GoogleFonts.tajawal(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
            textAlign: TextAlign.center,
            textDirection: TextDirection.rtl,
          ),
          const SizedBox(height: 8),
          Text(
            'سيصلك رمز تحقق على رقمك المسجّل في STC Pay',
            style: GoogleFonts.tajawal(
              fontSize: 14,
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
            textDirection: TextDirection.rtl,
          ),
          const SizedBox(height: 32),

          // Phone field label
          Text(
            controller.text.isNotEmpty && !isValid
                ? 'رقم الهاتف غير صحيح'
                : 'رقم الجوال',
            style: GoogleFonts.tajawal(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: controller.text.isNotEmpty && !isValid
                  ? Colors.red
                  : Colors.black87,
            ),
            textDirection: TextDirection.rtl,
          ),
          const SizedBox(height: 8),

          TextField(
            controller: controller,
            keyboardType: TextInputType.phone,
            textDirection: TextDirection.ltr,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[\d ]')),
              LengthLimitingTextInputFormatter(12),
            ],
            onChanged: onChanged,
            decoration: InputDecoration(
              hintText: '05x xxx xxxx',
              hintStyle: TextStyle(color: Colors.grey[400], fontSize: 18),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                vertical: 14,
                horizontal: 16,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: brand, width: 1.5),
              ),
            ),
            style: const TextStyle(fontSize: 20, letterSpacing: 1),
          ),

          const SizedBox(height: 32),

          // Pay button
          SizedBox(
            height: 54,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: isValid ? brand : brandLight,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: isValid ? 2 : 0,
              ),
              onPressed: isValid && !isSubmitting ? onSubmit : null,
              child: isSubmitting
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      'دفع ${amountSAR.toStringAsFixed(2)} ريال',
                      style: GoogleFonts.tajawal(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── OTP Step ──────────────────────────────────────────────────────────────────

class _OtpStep extends StatelessWidget {
  const _OtpStep({
    super.key,
    required this.controller,
    required this.isValid,
    required this.isSubmitting,
    required this.brand,
    required this.brandLight,
    required this.phone,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final bool isValid;
  final bool isSubmitting;
  final Color brand;
  final Color brandLight;
  final String phone;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFF6B0F6E).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.lock_outline_rounded,
                size: 36,
                color: Color(0xFF6B0F6E),
              ),
            ),
          ),
          const SizedBox(height: 24),

          Text(
            'رمز التحقق',
            style: GoogleFonts.tajawal(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
            textAlign: TextAlign.center,
            textDirection: TextDirection.rtl,
          ),
          const SizedBox(height: 8),
          Text(
            'تم إرسال رمز التحقق إلى $phone',
            style: GoogleFonts.tajawal(
              fontSize: 14,
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
            textDirection: TextDirection.rtl,
          ),
          const SizedBox(height: 32),

          // OTP field label
          Text(
            controller.text.isNotEmpty && !isValid
                ? 'رمز التحقق غير مكتمل'
                : 'رمز التحقق OTP',
            style: GoogleFonts.tajawal(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: controller.text.isNotEmpty && !isValid
                  ? Colors.red
                  : Colors.black87,
            ),
            textDirection: TextDirection.rtl,
          ),
          const SizedBox(height: 8),

          TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 10,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
            ],
            decoration: InputDecoration(
              hintText: 'XXXXXX',
              hintStyle: TextStyle(
                color: Colors.grey[400],
                fontSize: 22,
                letterSpacing: 8,
              ),
              counterText: '',
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                vertical: 14,
                horizontal: 16,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: brand, width: 1.5),
              ),
            ),
            style: const TextStyle(
              fontSize: 22,
              letterSpacing: 8,
            ),
          ),

          const SizedBox(height: 32),

          SizedBox(
            height: 54,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: isValid ? brand : brandLight,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: isValid ? 2 : 0,
              ),
              onPressed: isValid && !isSubmitting ? onSubmit : null,
              child: isSubmitting
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      'تأكيد الدفع',
                      style: GoogleFonts.tajawal(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
