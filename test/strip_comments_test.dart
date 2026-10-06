import 'package:flutter_test/flutter_test.dart';

import 'helpers/strip_comments.dart';

/// **مُجرِّدُ التعليقاتِ شفرةٌ تُختبَرُ كالشفرة.**
///
/// ثلاثُ صياغاتٍ سقطت قبلَ هذه، وكلُّ واحدةٍ أعمَت حارساً أو أنتجت إبلاغاً
/// خاطئاً: «السطرُ يَبدأُ بـ`//`» عمياءُ عن `{/* … */}` في JSX، و«من `/*` إلى
/// `*/`» ابتلعت ملفّاً كاملاً لأنّ `image/*` وردت **داخلَ تعليقِ سطر**.
/// فالفحصُ هنا على الحالاتِ التي أسقطَتها، لا على الشكلِ العامّ.
void main() {
  group('stripComments', () {
    test('تعليقُ سطرٍ يُمسَح، والنصُّ يُحفَظ', () {
      expect(stripComments("final x = 1; // سعرٌ\nfinal y = 2;"),
          "final x = 1; \nfinal y = 2;");
      expect(stripComments("const s = 'image/*'; final z = 3;"),
          "const s = 'image/*'; final z = 3;",
          reason: 'النصُّ يُحفَظُ: الحُرّاسُ تَشدُّ حروفَه');
    });

    test('`/*` داخلَ تعليقِ سطرٍ لا يَبتلعُ ما بعدَه — العطلُ الواقع', () {
      const src = "// القاعدةُ تَحصرُ المسارَ في `image/*`.\n"
          "final v = positiveNum(priceCtrl.text);";
      final out = stripComments(src);
      expect(out, contains('positiveNum(priceCtrl.text)'),
          reason: 'هذا بعينِه ما أعمى الحارسَ: الملفُّ كلُّه بَعدَ السطرِ '
              'صارَ فراغاً فقُرئ «الحقلُ لا يَمُرُّ بالقاعدة» وهو يَمُرّ');
    });

    test('كتلةُ `/* … */` تُمسَحُ عبرَ الأسطرِ والمواضعُ لا تَنزاح', () {
      const src = 'a\n/* تعليقٌ\n  يَمتدُّ */\nb';
      final out = stripComments(src);
      expect(out.contains('تعليقٌ'), isFalse);
      expect(out.contains('يَمتدُّ'), isFalse);
      expect(out.split('\n').length, src.split('\n').length,
          reason: 'عددُ الأسطرِ يَبقى — وإلّا انزاحت المواضعُ وأُعيدت الكتابةُ '
              'في غيرِ موضعِها (عطلٌ مسجَّلٌ في حارسِ الخطوط)');
    });

    test('تعليقُ JSX يُمسَحُ بأسطُرِه التاليةِ العارية', () {
      const src = '<div>\n  {/* سببُ القرارِ:\n      > 9999 عُرفٌ قديم */}\n'
          '  <span>{couponMaxUsesLabel(c.maxUses)}</span>\n</div>';
      final out = stripComments(src);
      expect(out.contains('9999'), isFalse,
          reason: 'السطرُ الثاني من تعليقِ JSX نصٌّ عارٍ بلا علامة — '
              'ومُرشِّحُ البادئةِ عاجزٌ عنه');
      expect(out, contains('couponMaxUsesLabel(c.maxUses)'));
    });

    test('`//` داخلَ نصٍّ ليس تعليقاً — فخُّ `https://`', () {
      const src = "const u = 'https://api.moyasar.com/v1'; final k = 1;";
      expect(stripComments(src), src,
          reason: 'حارسُ تمارا كان عقيماً لهذا السببِ بعينِه');
    });

    test('النصُّ متعدّدُ الأسطرِ والهروبُ لا يَخلعانِ الحالة', () {
      expect(stripComments("""const a = '''\n// ليس تعليقاً\n''';\nfinal b = 2;"""),
          contains('ليس تعليقاً'));
      expect(stripComments(r"""const a = 'it\'s // not'; final b = 2;"""),
          contains('// not'));
    });
  });
}
