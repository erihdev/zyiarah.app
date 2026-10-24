// حقولُ البطاقةِ داخلَ خيارِها — لا صفحةٌ ثانية (قرار المالك 2026-10-24).
//
// «بطاقة فيزا / مدى» كانت تَفتحُ `MoyasarCardScreen` بعد «تأكيد وإتمام
// الدفع»: زرُّ دفعٍ لا يَدفع ثمّ صفحةٌ بزرٍّ ثانٍ. الآن `MoyasarInlineCard`
// تَظهرُ تحتَ الخيارِ حين يُختار، وزرُّ ميسر هو زرُّ الدفعِ الوحيد.
//
// وما يَحرسُه هذا الملفّ ثلاثة: لا عودةَ للشاشةِ المنفصلة، ولا زرَّ دفعٍ
// ثانٍ فوقَ البطاقة، ولا حقولَ قابلةً للشحنِ قبلَ تحقّقِ الشروط (زرُّ ميسر
// يَشحنُ فوراً، فلا فحصَ بعدَه).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _src(String p) => File(p).readAsStringSync();

void main() {
  final summary = _src('lib/screens/payment_summary_screen.dart');
  final store = _src('lib/screens/store_payment_screen.dart');
  final widget = _src('lib/widgets/moyasar_inline_card.dart');

  test('الشاشةُ المنفصلةُ محذوفةٌ ولا يُنادِيها أحد', () {
    expect(File('lib/screens/moyasar_card_screen.dart').existsSync(), isFalse);
    for (final entry in {'summary': summary, 'store': store}.entries) {
      expect(entry.value.contains('MoyasarCardScreen('), isFalse,
          reason: '${entry.key}: عادت صفحةُ البطاقةِ المنفصلة');
    }
  });

  test('الحقولُ تحتَ خيارِ البطاقةِ حين يُختارُ وحدَه', () {
    expect(
        RegExp(r"_selectedPaymentMethod == 'card'\)\s*_gateNative\(MoyasarInlineCard\(")
            .hasMatch(summary),
        isTrue,
        reason: 'الخدمات: النموذجُ غائبٌ أو بلا بوّابةِ الشروط');
    expect(
        RegExp(r"_selectedMethod == 'card'\)\s*MoyasarInlineCard\(")
            .hasMatch(store),
        isTrue,
        reason: 'المتجر: النموذجُ غائب');
    expect(store.contains('blockedReason: _cardBlockReason()'), isTrue,
        reason: 'المتجر: حقولٌ تَشحنُ قبلَ العنوانِ والموافقة');
  });

  test('لا زرَّ «تأكيد وإتمام الدفع» فوقَ البطاقة', () {
    for (final entry in {
      'summary': (summary, "_selectedPaymentMethod == 'card' && !_isLoading"),
      'store': (store, "_selectedMethod == 'card' && !_isLoading"),
    }.entries) {
      final (src, cond) = entry.value;
      final at = src.indexOf('Widget _buildBottomButton()');
      expect(at, greaterThan(-1));
      final head = src.substring(at, at + 400);
      expect(head.contains(cond), isTrue,
          reason: '${entry.key}: زرٌّ ثانٍ يُضغَطُ فلا يَدفع');
    }
  });

  test('الخدماتُ على مسارِ Apple Pay: بياناتُ الحجزِ كاملةً وتأكيدٌ خادميّ', () {
    final at = summary.indexOf('_gateNative(MoyasarInlineCard(');
    final block = summary.substring(at, at + 900);
    // الطلبُ لا يُنشأ قبلَ الدفعِ هنا، فالخادمُ يَبنيه من البيانات.
    expect(block.contains('metadata: _nativePayMeta()'), isTrue,
        reason: 'بلا بياناتِ الحجزِ لا يَستطيعُ الخادمُ إنشاءَ الطلب');
    expect(block.contains('givenIdFromOrder(_pendingOrderId)'), isTrue,
        reason: 'بلا given_id ثابتٍ تَصيرُ الإعادةُ شحناً ثانياً');
    expect(block.contains("_processUnifiedSuccess(_pendingOrderId, 'card'"),
        isTrue);
    expect(block.contains("_handleNativePayFailure(raw, 'card')"), isTrue,
        reason: 'الفشلُ يَحتاجُ قرارَ تجديدِ المعرّفِ وتسجيلَ المجهول');
  });

  test('الودجةُ تَقرأُ النتيجةَ بالقاعدةِ الواحدة', () {
    expect(widget.contains('moyasarErrorText('), isTrue);
    expect(widget.contains('PaymentStatus.paid'), isTrue);
    expect(widget.contains('PaymentStatus.authorized'), isTrue);
    expect(widget.contains('result.message'), isFalse,
        reason: 'نصُّ البوّابةِ يَصِلُ العميلة');
  });
}
