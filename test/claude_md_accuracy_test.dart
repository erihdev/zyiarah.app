// حارس دائم: **CLAUDE.md تطابق الشفرة** — لا تعود أخطاؤها الأربعة.
//
// CLAUDE.md ليست وثيقة للقراءة فقط: كل جلسة مساعد تقرأها أولاً وتبني عليها.
// فالمعلومة الخاطئة فيها ليست سهواً تحريرياً — هي تعليمة تُنفَّذ. وُجدت أربع
// منها في فحص 2026-10-03، وهذا الحارس يمنع رجوعها:
//
//   ١. «استخدم ZyiarahFirebaseService.instance» — لا وجود لـ.instance
//      (المُنشئ factory و_instance خاص)، فأي شفرة تتبع التوثيق **لا تُصرَّف**.
//   ٢. «لا تستخدم Text() للعربية، استخدم arabic_reshaper» — خطأ للواجهة:
//      Flutter يشكّل العربية أصلاً، والتشكيل المسبق يُفسد النص بتشكيل مزدوج.
//      reshaper يلزم في خدمة PDF وحدها (حزمة pdf ترسم بلا تشكيل).
//   ٣. «~37 functions» والعدد ٦٢.
//   ٤. توثيق zyiarah_capacity_service.dart كخدمة عاملة وهي شفرة ميتة.
//
// الفحوص أدناه تقارن الوثيقة بالشفرة لا بثابت مكتوب، فتبقى صحيحة مع تغيّر
// المشروع: إن أُضيفت دالة خادمية سقط فحص العدد حتى تُحدَّث الوثيقة، وإن استورد
// ملفٌ آخر arabic_reshaper سقط فحص العربية حتى يُراجَع القرار.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _doc = 'CLAUDE.md';

String _read(String path) => File(path).readAsStringSync();

void main() {
  group('CLAUDE.md تطابق الشفرة', () {
    test('لا تدّعي وجود ZyiarahFirebaseService.instance', () {
      final doc = _read(_doc);
      expect(
        doc.contains('ZyiarahFirebaseService.instance'),
        isFalse,
        reason: 'لا يوجد getter بهذا الاسم — شفرة تتبع هذا التوثيق لا تُصرَّف. '
            'النداء الصحيح ZyiarahFirebaseService().',
      );

      // والسبب يُفحَص من المصدر لا من الذاكرة: الخدمة factory بـ_instance خاص.
      final svc = _read('lib/services/firebase_service.dart');
      expect(svc, contains('factory ZyiarahFirebaseService() => _instance;'));
      expect(
        RegExp(r'static\s+\w+\s+get\s+instance').hasMatch(svc),
        isFalse,
        reason: 'إن أُضيف getter باسم instance فعلاً، فراجِع هذا الحارس '
            'والوثيقة معاً — لا تُسقط أحدهما وحده.',
      );
    });

    test('لا تنهى عن استخدام Text() للنصوص العربية', () {
      final doc = _read(_doc);
      expect(
        doc.contains('do not use plain `Text()`'),
        isFalse,
        reason: 'Flutter يشكّل العربية ويرتّبها اتجاهياً أصلاً؛ النهي عن Text() '
            'يدفع لتشكيل مسبق يُفسد النص.',
      );
      expect(
        doc.contains('plain `Text()` is **correct** for Arabic'),
        isTrue,
        reason: 'القاعدة الصحيحة يجب أن تبقى منصوصة، لا أن تُحذف الخاطئة فقط.',
      );
    });

    test('arabic_reshaper محصور في بوّابة الـPDF — والوثيقة تقول ذلك', () {
      // **انتقلَ الحصرُ من ملفٍّ إلى بوّابةٍ (2026-10-06).** كان المُشكِّلُ
      // في `zyiarah_pdf_service` وحدَه، والتشكيلُ **لا يَكفي**: الخطُّ
      // المُضمَّنُ لا يَملكُ أشكالَ الانفصالِ فتَسقطُ حروفٌ من الفاتورة،
      // و`pdf_report_util` لم يُشكّلْ أصلاً. فصارَ في
      // `lib/utils/arabic_pdf_text.dart` بوّابةً واحدةً يُنادِيها المسارانِ
      // (`test/arabic_pdf_text_test.dart`). والحصرُ ما زال حصراً: ملفٌّ
      // ثالثٌ يَستوردُ المُشكِّلَ يُسقطُ الفحص.
      final importers = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) => f.readAsStringSync().contains('arabic_reshaper'))
          .map((f) => f.path)
          .toList()
        ..sort();

      expect(
        importers,
        ['lib/utils/arabic_pdf_text.dart'],
        reason: 'reshaper يلزم لمخرجات PDF وحدها، ومن بوّابةٍ واحدة. إن ظهر '
            'في ملف واجهة فهو تشكيل مزدوج يُفسد النص؛ وإن ظهر في ملفِّ PDF '
            'آخر فهو تخطٍّ لردِّ أشكالِ الانفصال — أو قرار جديد يستوجب '
            'تحديث الوثيقة.',
      );

      expect(_read(_doc), contains('arabic_pdf_text.dart'));
    });

    test('عدد الدوال الخادمية في الوثيقة يطابق index.js', () {
      final actual = RegExp(r'^exports\.', multiLine: true)
          .allMatches(_read('functions/index.js'))
          .length;

      expect(
        _read(_doc),
        contains('**$actual exported functions'),
        reason: 'index.js يصدّر $actual دالة. حدِّث الرقم في CLAUDE.md '
            'مع كل إضافة أو حذف.',
      );
    });

    test('لا تُدرَج خدمة السعة الميتة كخدمة عاملة', () {
      final doc = _read(_doc);

      // الملف ما زال في الشجرة (حذفه بند منفصل)، فالحارس يفحص **كيف** تذكره
      // الوثيقة: لا كصفٍّ في جدول الخدمات، بل موصوفةً بأنها ميتة.
      expect(
        doc.contains('| `zyiarah_capacity_service.dart` |'),
        isFalse,
        reason: 'لا يستوردها أي ملف — إدراجها في جدول الخدمات يوحي بأنها '
            'المسار الحيّ للسعة، وهو day_capacity.dart وcapacity.js.',
      );
      expect(doc, contains('day_capacity.dart'));
      expect(doc, contains('capacity.js'));
    });
  });
}
