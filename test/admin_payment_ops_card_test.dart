// حارس: **بطاقةُ عمليّات الدفع لا تُرسَم فارغةً بلا سبب.**
//
// `_buildMoyasarOperationsCard` يقرأ `moyasar_status ?? payment_status ?? ''`
// ويبني ثلاثة شروطٍ من مفردات ميسر وحدها (authorized / paid / captured /
// refunded / voided). فحالةٌ من خارج تلك المفردات تُسقط `canVoid` و`canRefund`
// و`canCapture` **و**`alreadyFinal` معاً — فيُرسم `Wrap` بلا أبناء: بطاقةٌ
// بعنوانٍ ومعرّفِ دفعةٍ وشارةِ حالة، ثمّ **لا شيء**: لا زرّ، ولا سبب.
//
// وذلك يقع بالضبط حيث يُحتاج الأدمنُ أكثر: طلبٌ مدفوعٌ بالمحفظة أو بتمارا لا
// يحمل `moyasar_status` أصلاً، فإن علِق على `payment_status` من خارج المفردات
// (كان `autoResolveUnfulfilledPaidOrder` يترك "refunding" في فرعَي فشل)
// فالبطاقةُ صامتة — بينما التنبيهُ الإداريُّ يقول إنّ استرداداً آليّاً فشل.
//
// والشارةُ كانت تطبع الحالةَ الخامَّة بحروفٍ لاتينيّة داخل واجهةٍ عربيّة
// (`_ => status`) — نفسُ عطلِ «نصّ الاستثناء في وجه العميلة».
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final src =
      File('lib/screens/admin/admin_order_details_screen.dart').readAsStringSync();

  group('الشارة تُترجم ما قد يصلها فعلاً', () {
    // هذه حالاتٌ يكتبها المشروعُ نفسُه في `payment_status`، والارتدادُ
    // `moyasar_status ?? payment_status` يجعلها تمرّ بهذه الدالّة.
    for (final st in const [
      'refunding',
      'payment_review',
      'awaiting_payment',
      'awaiting_confirmation',
    ]) {
      test('«$st» لها نصٌّ عربيّ', () {
        expect(src.contains("'$st' =>"), isTrue,
            reason: '«$st» تُعرض بحروفٍ لاتينيّة خامّة في شارةِ حالةٍ عربيّة');
      });
    }

    test('والحالةُ الفارغة تُسمّى، لا تُترك فراغاً', () {
      expect(src.contains("'' => 'غير معروفة'"), isTrue);
    });

    test('الاحتياطُ الأخير باقٍ (حالةٌ لم نتوقّعها تُعرض لا تُبتلع)', () {
      expect(src.contains('_ => status'), isTrue);
    });
  });

  group('لا بطاقةَ عمليّاتٍ صامتة', () {
    test('فرعٌ صريحٌ حين لا عمليةَ متاحة', () {
      expect(src.contains('else if (!canCapture && !canVoid && !canRefund)'),
          isTrue,
          reason: 'عاد `Wrap` الفارغ — بطاقةٌ بلا زرٍّ وبلا سبب');
    });

    test('ويُفرّق بين «لا دفعةَ بوابة» و«حالةٌ لا عملية لها»', () {
      // السببان مختلفان والإجراءُ مختلف: الأوّل لا شيء فيه لميسر أصلاً
      // (محفظة/تمارا/يدويّ)، والثاني دفعةٌ قائمةٌ بحالةٍ غير قابلة للعملية.
      expect(src.contains('لا عملية دفع بوابة على هذا الطلب'), isTrue);
      expect(src.contains('لا عملية متاحة على حالة'), isTrue);
    });

    test('والسببُ يذكر الحالةَ بنصِّها العربيّ لا بالرمز', () {
      expect(
          src.contains(
              "'لا عملية متاحة على حالة «\${_moyasarStatusLabel(moyasarStatus)}». '"),
          isTrue);
    });

    test('الفرعُ النهائيُّ ما زال سابقاً له (لا يبتلعه)', () {
      final fin = src.indexOf('if (alreadyFinal)');
      final none = src.indexOf('else if (!canCapture && !canVoid && !canRefund)');
      expect(fin, greaterThan(0));
      expect(none, greaterThan(fin),
          reason: 'لو سبق فرعُ «لا عملية» لابتلع الحالاتِ النهائيّة ولقال '
              'للأدمن «راجِع لوحة ميسر» عن عمليةٍ انتهت فعلاً');
    });
  });

  group('مصدرُ الحالة لم يتغيّر (وإلّا فالحارسُ يحرس شيئاً آخر)', () {
    test('الارتدادُ من moyasar_status إلى payment_status قائم', () {
      expect(
          src.contains(
              "data['moyasar_status'] as String? ?? data['payment_status'] as String? ?? ''"),
          isTrue,
          reason: 'لو زال الارتدادُ لما وصلت حالاتُ المحفظة/تمارا هذه البطاقةَ '
              'أصلاً — وهو تغييرٌ يُراجَع لا يُسكَت عنه');
    });
  });
}
