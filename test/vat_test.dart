// فحص خاصيّة لا أمثلة: يثبت أن دوال `lib/utils/vat.dart` تُعيد **نفس** ما كانت
// تُعيده الصيغ الحرفية المكتوبة يدوياً في سبعة عشر ملفاً قبل التوحيد، على نطاق
// أسعار واقعي كامل — لا على قيمٍ مختارة تُخفي الانحراف عند الحدود.
//
// الغرض ليس التأكّد أن ٠.١٥ تساوي ٠.١٥، بل إثبات أن `1 + 0.15` و`1.15` واحدٌ
// في IEEE754 (كلاهما 1.1499999999999999112) فلا يتسلّل فرقٌ في آخر بتة يقلب
// حدَّ تقريب فيغيّر قرشاً. والقرش هنا ليس تجميلاً: التسعير الخادمي يقارن المدفوع
// بالمتوقَّع بسماحية `> 0.01`، فانحرافٌ على الحدّ = رفض دفعٍ سليم أو قبول ناقص.
//
// ويثبّت أيضاً أن النسبة لم تعد مكتوبة يدوياً في أي ملف حيّ — مع استثناء صريح
// للقيم التي تساوي 0.15 أو 1.15 عرَضاً ولا علاقة لها بالضريبة (شفافية الألوان
// `withValues(alpha: 0.15)`، و`childAspectRatio: 1.15`، وإزاحات إحداثيات
// الخريطة). سقوط هذا الفحص يعني موضعاً جديداً يفلت من المصدر الموحَّد.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/utils/vat.dart';

/// القيم التي يُسمح أن تحمل 0.15 أو 1.15 وليست ضريبة.
final _notVat = RegExp(
  r'withValues\(\s*alpha:|withOpacity\(|childAspectRatio:|'
  r'latitude|longitude|LatLng\(',
);

void main() {
  group('المصدر الموحَّد للضريبة', () {
    test('النسبة ١٥٪ والمعامل يطابق الحرفيّ بتةً ببتة', () {
      expect(kVatRate, 0.15);
      expect(kVatMultiplier, 1.15);
      // ليس تحصيلَ حاصل: 0.15 و1.15 غير قابلين للتمثيل تماماً، والمطلوب أن
      // يكون ناتج الجمع هو **نفس** المضاعف الحرفيّ المستعمل قبل التوحيد.
      expect(1 + kVatRate == 1.15, isTrue);
    });

    test('netFromGross يطابق `x / 1.15` الحرفية', () {
      for (var i = 0; i <= 200000; i += 7) {
        final x = i / 100;
        expect(netFromGross(x), x / 1.15, reason: 'انحراف عند $x');
      }
    });

    test('vatInGross يطابق `x - x / 1.15` الحرفية', () {
      for (var i = 0; i <= 200000; i += 7) {
        final x = i / 100;
        expect(vatInGross(x), x - x / 1.15, reason: 'انحراف عند $x');
      }
    });

    test('vatOnBase يطابق `x * 0.15` الحرفية', () {
      for (var i = 0; i <= 200000; i += 7) {
        final x = i / 100;
        expect(vatOnBase(x), x * 0.15, reason: 'انحراف عند $x');
      }
    });

    test('grossFromBase يطابق `x * 1.15` الحرفية', () {
      for (var i = 0; i <= 200000; i += 7) {
        final x = i / 100;
        expect(grossFromBase(x), x * 1.15, reason: 'انحراف عند $x');
      }
    });

    test('grossFromBaseRounded يطابق `((x * 1.15) * 100).roundToDouble() / 100`',
        () {
      for (var i = 0; i <= 200000; i += 7) {
        final x = i / 100;
        expect(
          grossFromBaseRounded(x),
          ((x * 1.15) * 100).roundToDouble() / 100,
          reason: 'انحراف عند $x',
        );
      }
    });

    test('النموذجان متّسقان: netFromGross يعكس grossFromBase', () {
      // الضريبة فوق الأساس ثم استخراجها من الإجمالي يعود إلى الأساس — في حدود
      // دقّة التعويم. يثبّت أن الدالتين تصفان نموذجاً واحداً لا نموذجين.
      for (var i = 1; i <= 200000; i += 97) {
        final base = i / 100;
        expect(netFromGross(grossFromBase(base)), closeTo(base, 1e-9));
      }
    });

    test('لا نسبة مكتوبة يدوياً في أي ملف حيّ', () {
      final offenders = <String>[];
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        if (f.path == 'lib/utils/vat.dart') continue;
        final lines = f.readAsStringSync().split('\n');
        for (var i = 0; i < lines.length; i++) {
          final idx = lines[i].indexOf('//');
          final code = idx == -1 ? lines[i] : lines[i].substring(0, idx);
          if (!RegExp(r'\b1\.15\b|\b0\.15\b').hasMatch(code)) continue;
          if (_notVat.hasMatch(code)) continue;
          offenders.add('${f.path}:${i + 1}: ${code.trim()}');
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: 'النسبة عادت مكتوبة يدوياً — استورد lib/utils/vat.dart:\n'
            '${offenders.join('\n')}',
      );
    });
  });
}
