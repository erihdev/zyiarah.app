import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'helpers/sources_in.dart';

/// كتابةٌ تَفشلُ في لوحةِ الويبِ بلا كلمةٍ للأدمن.
///
/// `console.error` ليس تنبيهاً: وحدةُ التحكّمِ لا يَفتحُها أحدٌ، فالنقرةُ
/// تَنتهي بلا شيءٍ ظاهر — الصفُّ لا يَتغيّر (لا كتابةَ ⇒ لا مستمعَ يُحدِّث)
/// فيَظنُّ الأدمنُ أنّه أخطأَ الزرَّ ويُعيد. أربعةُ مواضعَ كانت كذلك،
/// و`Orders.tsx` كانت تُنبّه في كلِّ مواضعِها الخمسة — فالقاعدةُ موجودةٌ
/// والمواضعُ الأربعةُ شذَّت عنها.
///
/// والصامتُ **بقصدٍ** يَبقى صامتاً: التدقيقُ أفضلُ-جهدٍ (كما في
/// `lib/services/audit_service.dart`)، وفشلُ قراءةِ الإعداداتِ يُعرَض
/// بحالةِ فشلٍ في الصفحةِ نفسِها لا بنَفْشة.
void main() {
  String read(String p) => File(p).readAsStringSync();

  /// جسمُ أوّلِ `catch` يَلي [anchor] — بموازنةِ الأقواسِ لا بنمطٍ ثابت.
  String catchBodyAfter(String src, String anchor) {
    final a = src.indexOf(anchor);
    expect(a, greaterThan(-1), reason: 'لم يُوجد المرساة: $anchor');
    final c = src.indexOf('catch', a);
    expect(c, greaterThan(-1), reason: 'لا catch بعد $anchor');
    final open = src.indexOf('{', src.indexOf(')', c));
    var depth = 1;
    var i = open + 1;
    while (i < src.length && depth > 0) {
      if (src[i] == '{') depth++;
      if (src[i] == '}') depth--;
      i++;
    }
    return src.substring(open + 1, i - 1);
  }

  /// جسمُ `catch` الذي **يَحتوي** [needle] — للمواضعِ التي مرساتُها داخلَ
  /// الجسمِ نفسِه (نصُّ `console.error`)، فالبحثُ عن `catch` بعدَها يَقعُ على
  /// التالي لا عليه.
  String catchBodyContaining(String src, String needle) {
    final n = src.indexOf(needle);
    expect(n, greaterThan(-1), reason: 'لم يُوجد النص: $needle');
    final c = src.lastIndexOf('catch', n);
    expect(c, greaterThan(-1), reason: 'لا catch يَحتوي $needle');
    final open = src.indexOf('{', src.indexOf(')', c));
    var depth = 1;
    var i = open + 1;
    while (i < src.length && depth > 0) {
      if (src[i] == '{') depth++;
      if (src[i] == '}') depth--;
      i++;
    }
    final body = src.substring(open + 1, i - 1);
    expect(body.contains(needle), isTrue, reason: 'الجسمُ المُستخرَجُ لا يَحتويه');
    return body;
  }

  group('كلُّ كتابةٍ إداريّةٍ تَفشلُ تَقولُ ذلك', () {
    test('حالةُ طلبِ المتجر — «جاري التوصيل»/«تم التسليم»', () {
      final s = read('admin_panel/src/pages/StoreOrders.tsx');
      final body = catchBodyAfter(s, "updateDoc(doc(db, 'store_orders'");
      expect(body.contains('toast.error'), isTrue);
      expect(s.contains('useNotification'), isTrue);
    });

    test('الردُّ على تذكرةِ دعم', () {
      final s = read('admin_panel/src/pages/Support.tsx');
      final body = catchBodyAfter(s, "status: 'replied'");
      expect(body.contains('toast.error'), isTrue);
      // لا تَزعم «لم يُرسَل»: الرسالةُ تُكتبُ قبل وسمِ التذكرة، فقد يَفشلُ
      // الثاني وحدَه — والنصُّ يُحذّرُ من إعادةٍ تُكرّرُ الرسالةَ عند العميلة.
      expect(body.contains('راجع التذكرة'), isTrue);
      expect(body.contains('لم يُرسل'), isFalse);
    });

    test('حفظُ منتجٍ في المتجر', () {
      final s = read('admin_panel/src/pages/StoreProducts.tsx');
      final body = catchBodyAfter(s, "addDoc(collection(db, 'products')");
      expect(body.contains('toast.error'), isTrue);
      expect(s.contains('{ confirm, toast }'), isTrue,
          reason: 'الخُطّافُ كان يُفكِّكُ confirm وحدَه — وtsc هو ما أمسكَه');
    });

    test('تفعيل/تعطيلُ كوبون', () {
      final s = read('admin_panel/src/pages/Marketing.tsx');
      final body = catchBodyAfter(s, "doc(db, 'promo_codes', coupon.id)");
      expect(body.contains('toast.error'), isTrue);
    });
  });

  group('والصامتُ بقصدٍ يَبقى صامتاً', () {
    test('سجلُّ التدقيقِ أفضلُ-جهدٍ: لا نَفْشةَ على فشلِه', () {
      final s = read('admin_panel/src/services/audit.ts');
      final body = catchBodyAfter(s, "collection(db, 'audit_logs')");
      expect(body.contains('toast'), isFalse,
          reason: 'فشلُ التدقيقِ لا يَجوزُ أن يُظهرَ عملاً ناجحاً كأنّه فاشل');
    });

    test('فشلُ قراءةِ الإعداداتِ يُعرَضُ في الصفحةِ لا بنَفْشة', () {
      final s = read('admin_panel/src/pages/Settings.tsx');
      final body = catchBodyContaining(s, 'Error fetching settings');
      expect(body.contains('setLoadFailed(true)'), isTrue);
      expect(body.contains('toast'), isFalse);
    });
  });

  group('لا موضعَ خامسَ يَمرُّ بلا مراجعة', () {
    test('كلُّ catch يَلي كتابةً إمّا يُنبّه أو هو أحدُ الصامتَين بقصد', () {
      // المسحُ نفسُه الذي وَجدَ الأربعة: جسمُ catch فيه console. وبلا toast.
      const allowed = {
        'admin_panel/src/services/audit.ts',
        'admin_panel/src/pages/Settings.tsx',
      };
      final found = <String>[];
      for (final f in sourcesIn('admin_panel/src',
              atLeast: 20, exts: const ['.tsx', '.ts'])
          .where((f) => !f.path.contains('.test.'))) {
        final s = f.readAsStringSync();
        if (!RegExp(r'\b(updateDoc|setDoc|addDoc|deleteDoc|writeBatch|httpsCallable)\b')
            .hasMatch(s)) {
          continue;
        }
        for (final m in RegExp(r'catch\s*\([^)]*\)\s*\{').allMatches(s)) {
          var depth = 1;
          var i = m.end;
          while (i < s.length && depth > 0) {
            if (s[i] == '{') depth++;
            if (s[i] == '}') depth--;
            i++;
          }
          final body = s.substring(m.end, i - 1);
          if (body.contains('toast') || !body.contains('console.')) continue;
          found.add(f.path.replaceAll('\\', '/'));
        }
      }
      expect(found.toSet(), equals(allowed),
          reason: 'موضعٌ جديدٌ يَبتلعُ فشلَ كتابةٍ — أو صامتٌ بقصدٍ يَحتاجُ سطراً هنا');
    });

    // ═══ والعطلُ الآخرُ: كتابةٌ **بلا `catch` أصلاً** ═══
    //
    // الفحصُ أعلاه يَمسحُ **أجسامَ `catch`** — فكتابةٌ لا `catch` لها غيرُ
    // مرئيّةٍ له تماماً: الوعدُ يُرفَضُ بلا مُعالِج، فلا نَفْشةَ ولا سطرَ
    // وحدةٍ حتى، والصفُّ لا يَتغيّر (لا كتابةَ ⇒ لا مستمعَ يُحدِّث) فيُعيدُ
    // الأدمنُ النقرَ. أي أنّ الكاشفَ كان يَرى **شكلاً واحداً** من العطل
    // الذي وُجد له — وهو النمطُ المتكرّرُ في حُرّاسِ هذا المستودع.
    //
    // أربعةُ مواضعَ كانت كذلك: حذفُ منتجٍ وتبديلُ عرضِه (و`handleSubmit` في
    // الملفِّ نفسِه يُنبّه)، وإغلاقُ تذكرةٍ (والردُّ في الملفِّ نفسِه
    // يُنبّه)، ورفعُ صورةِ سائقٍ — وهذا الأخيرُ أسوأُها: الوعدُ لم يَكن
    // يُسوّى أصلاً (انظر `storage_hardening_test`).
    test('ولا كتابةَ بلا `try` — الحارسُ كان يَمسحُ أجسامَ `catch` وحدَها', () {
      /// النصُّ بلا تعليقات (الأقواسُ داخلَها تَكسِرُ الموازنة). النصوصُ
      /// الحرفيّةُ تَبقى: قوالبُ `${…}` متوازنةٌ بطبعِها.
      String noComments(String s) {
        final out = StringBuffer();
        int i = 0;
        String? quote;
        while (i < s.length) {
          final String c = s[i];
          if (quote == null) {
            if (s.startsWith('//', i)) {
              final int j = s.indexOf('\n', i);
              i = j < 0 ? s.length : j;
              continue;
            }
            if (s.startsWith('/*', i)) {
              final int j = s.indexOf('*/', i + 2);
              i = j < 0 ? s.length : j + 2;
              continue;
            }
            if (c == '"' || c == "'" || c == '`') quote = c;
            out.write(c);
            i++;
          } else {
            if (c == r'\') {
              out.write(s.substring(i, (i + 2).clamp(0, s.length)));
              i += 2;
              continue;
            }
            if (c == quote) quote = null;
            out.write(c);
            i++;
          }
        }
        return out.toString();
      }

      final RegExp write = RegExp(
          r'\b(?:updateDoc|setDoc|addDoc|deleteDoc)\s*\(');
      // **المفتاحُ ملفٌّ وترتيبٌ لا رقمُ سطر**: تعديلٌ أعلى الملفِّ لا
      // يُسقِطُ الحارسَ زوراً (عُرفُ `stream_timeout_sweep_test`).
      const Set<String> allowedOutsideTry = {};
      final List<String> outside = [];
      int insideTry = 0;
      for (final f in sourcesIn('admin_panel/src',
              atLeast: 20, exts: const ['.tsx', '.ts'])
          .where((f) => !f.path.contains('.test.'))) {
        final String src = noComments(f.readAsStringSync());
        int ordinal = 0;
        for (final m in write.allMatches(src)) {
          ordinal++;
          // الكتلُ المُحيطةُ: نمشي إلى الوراءِ ونَجمعُ كلَّ `{` غيرِ مُغلَق.
          int depth = 0;
          bool inTry = false;
          for (int k = m.start - 1; k >= 0; k--) {
            final String ch = src[k];
            if (ch == '}') {
              depth++;
            } else if (ch == '{') {
              if (depth == 0) {
                final String head =
                    src.substring((k - 120).clamp(0, k), k).trimRight();
                if (head.endsWith('try')) {
                  inTry = true;
                  break;
                }
              } else {
                depth--;
              }
            }
          }
          if (inTry) {
            insideTry++;
          } else {
            outside.add('${f.uri.pathSegments.last}#$ordinal');
          }
        }
      }
      // ضبطٌ موجبٌ: لو انهارَ المُوازِنُ لَقرأَ الكلَّ «خارجَ try».
      expect(insideTry, greaterThanOrEqualTo(15),
          reason: 'مُوازِنُ الكتلِ انحلّ — $insideTry كتابةً داخلَ try فقط');
      expect(outside.toSet(), allowedOutsideTry,
          reason: 'كتابةٌ بلا `try`: الرفضُ بلا مُعالِجٍ لا يُنبّهُ ولا '
              'يُسجّلُ شيئاً، والصفُّ لا يَتغيّر: ${outside.join(", ")}');
    });

  });
}
