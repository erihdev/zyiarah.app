import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

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
      for (final f in Directory('admin_panel/src')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) =>
              (f.path.endsWith('.tsx') || f.path.endsWith('.ts')) &&
              !f.path.contains('.test.'))) {
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
  });
}
