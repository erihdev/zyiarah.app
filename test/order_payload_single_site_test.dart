// حارس: **حِملُ مستندِ طلبِ الخدمةِ له موضعٌ واحد** (2026-10-08).
//
// حِملُ `orders` يُكتَبُ من جهازِ العميلةِ — فهو ما تَقرؤه بطاقةُ تفصيلِ
// السعرِ عند الأدمنِ، وبطاقةُ مهمّةِ السائق، والفاتورة. وكان مكتوباً
// **ثلاثَ** مرّات:
//
//   ١) `payment_summary_screen._createUnpaidServiceOrder` — قبلَ الدفع
//      (البطاقةُ وSTC وتمارا تُنشئُ الطلبَ `is_paid: false` ثمّ تَدفع).
//   ٢) `payment_summary_screen._processUnifiedSuccess`   — بعدَ الدفع
//      (المحفظةُ والدفعُ الأصليُّ Apple/Google/Samsung لا يُنشئانِه قبلَه).
//   ٣) `checkout_screen` — «مسارُ الإنشاءِ الاحتياطيّ»، **غيرُ مبلوغٍ**:
//      `_createUnpaidServiceOrder` تُنتظَرُ قبلَ `createCheckoutSession`
//      وهي بلا `catch`، فرميُها يَمنعُ فتحَ جلسةِ تمارا أصلاً.
//
// والثلاثُ **انحرفت**. النسخةُ الميّتةُ (٣) فقدت `client_email` وحقلَي
// الوعورة — ٢٢ مفتاحاً مقابلَ ٢٥ — فلو عملت لأنشأت طلباً مبلغُه يَشملُ
// الوعورةَ وتفصيلُه لا يَذكرُها وبلا بريدٍ للفاتورة. وأهمُّ من ذلك أنّ
// **النسختَين الحيّتَين (١) و(٢) اختلفتا**: `terrain_surcharge_percent`
// و`terrain_surcharge_amount` تَكتبُهما (١) وتُغفلُهما (٢).
//
// فطلبٌ في منطقةٍ وعرةٍ يَحملُ سطرَ الوعورةِ إن دُفعَ **بالبطاقة** ولا
// يَحملُه إن دُفعَ **بـApple Pay أو من المحفظة**؛ وقارئُه
// `admin_order_details_screen` يُخفي السطرَ عند الغياب (شرطُه `> 0`) —
// فبطاقةُ التفصيلِ تُعرَضُ وبنودُها لا تَبلغُ المجموعَ، بلا كلمةٍ تُفسّر.
// **والمالُ سليمٌ في الحالتَين** ويُقالُ بحدِّه: `pricing.js` يُعيدُ حسابَ
// الوعورةِ من **مستندِ المنطقةِ** ولا يَقرأُ ما يَكتبُه العميل — فالعطلُ
// في التفصيلِ لا في المبلغ.
//
// والنطاقُ هنا **مُشتَقٌّ**: كلُّ حِملِ كتابةٍ في شفرةِ العميلِ يَحملُ
// `client_id` و`status` و`is_paid` معاً هو إنشاءُ طلب، وتُقابَلُ
// **المجموعةُ كاملةً** بقائمةٍ مُعلَنةٍ لكلٍّ سببُه — فنسخةٌ رابعةٌ
// تُراجَعُ بدلَ أن تَنحرِفَ بصمت.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'helpers/sources_in.dart';
import 'helpers/strip_comments.dart';

/// كلُّ ما يَكتبُه جهازُ العميلةِ أو السائق. `admin/` خارجَه: كتاباتُه
/// تحديثاتٌ على مستندٍ قائمٍ لا إنشاءُ طلبٍ من العميل.
List<String> _clientSources() {
  final out = <String>[];
  for (final e in const [
    ['lib/screens', 30],
    ['lib/services', 10],
    ['lib/utils', 20],
    ['lib/widgets', 8],
  ]) {
    for (final f in sourcesIn(e[0] as String, atLeast: e[1] as int)) {
      if (f.path.contains('/admin/')) continue;
      out.add(f.path);
    }
  }
  out.sort();
  return out;
}

/// كلُّ **كتلةِ حقولٍ** تَذكرُ `'client_id':` — أيّاً كان موضعُها: وسيطَ
/// `.set(`، أو `return` من دالّةٍ، أو مُهيِّئَ متغيّر. تُقتطَعُ بالمشيِ إلى
/// الوراءِ حتى المعقوفةِ الحاوية ثمّ بموازنةٍ إلى الأمام.
///
/// والمشيُ إلى الوراءِ **لازم**: بعدَ جمعِ النسختَين صارَ الحِملُ `return`
/// من `_serviceOrderPayload`، فكاشفٌ يَقرأُ وسائطَ `.set(` وحدَها كان
/// سيُعلِنُ «لا كاتبَ إنشاءٍ في `payment_summary_screen`» — وهو إبلاغٌ
/// خاطئٌ كشفَه تشغيلُ الحارسِ على الشفرةِ المُصلَحة.
///
/// (فخُّ الحدِّ: `indexOf('}')` يَقفُ عند أوّلِ معقوفةٍ داخليّةٍ — عضَّ
/// في هذا المستودعِ عشرَ مرّات — فالاقتطاعُ موازنةٌ لا بحثٌ عن محرف.)
List<String> _fieldMapLiterals(String src) {
  final out = <String>[];
  for (final m in RegExp(r"'client_id'\s*:").allMatches(src)) {
    // إلى الوراء: `}` يُؤجّلُ، و`{` بلا مُؤجَّلٍ هو الحاوي.
    var close = 0, i = m.start - 1, open = -1;
    while (i >= 0) {
      final c = src[i];
      if (c == '}') {
        close++;
      } else if (c == '{') {
        if (close == 0) {
          open = i;
          break;
        }
        close--;
      }
      i--;
    }
    if (open == -1) continue;
    var d = 0, k = open;
    while (k < src.length) {
      if (src[k] == '{') {
        d++;
      } else if (src[k] == '}') {
        d--;
        if (d == 0) break;
      }
      k++;
    }
    if (k < src.length) out.add(src.substring(open, k + 1));
  }
  return out;
}

void main() {
  final srcs = _clientSources();
  final code = {for (final p in srcs) p: stripComments(File(p).readAsStringSync())};

  group('حِملُ طلبِ الخدمةِ موضعٌ واحد', () {
    test('(أ) مجموعةُ مَن يُنشئُ طلباً من العميلِ كاملةً — لا قائمةٌ مكتوبة', () {
      // مُعلَنٌ لكلٍّ سببُه. المجموعةُ تُقارَنُ كاملةً فنسخةٌ رابعةٌ تَسقط.
      const declared = <String, String>{
        'lib/screens/payment_summary_screen.dart':
            'الموضعُ الواحدُ: `_serviceOrderPayload` يُنادَى من مَوضعَي الإنشاء',
        'lib/services/store_service.dart':
            'مجموعةٌ أخرى (`store_orders`) ولها قواعدُها وتسعيرُها الخادميّ',
      };
      final found = <String>[];
      var blocks = 0;
      for (final p in srcs) {
        for (final pl in _fieldMapLiterals(code[p]!)) {
          blocks++;
          if (pl.contains("'status':") && pl.contains("'is_paid':")) {
            if (!found.contains(p)) found.add(p);
          }
        }
      }
      expect(blocks, greaterThanOrEqualTo(3),
          reason: 'انحلَّ اقتطاعُ كتلِ الحقولِ إلى لا شيء — حارسٌ عقيمٌ أسوأُ من لا حارس');
      expect(found..sort(), equals(declared.keys.toList()..sort()),
          reason: 'كاتبُ إنشاءٍ رابعٌ لطلبٍ من العميلِ — يُراجَعُ بدلَ أن '
              'يَنحرِفَ حِملُه بصمت: ${found.join(", ")}');
      // ودعوى الاستثناءِ تُتحقَّق: مجموعتُه فعلاً ليست `orders`.
      expect(code['lib/services/store_service.dart']!.contains("collection('store_orders')"),
          isTrue,
          reason: 'store_service لم يَعُد يَكتبُ store_orders — يُراجَعُ استثناؤه');
    });

    test('(ب) مَوضعا الإنشاءِ يَرشّانِ الحِملَ ولا يُعيدانِ تعدادَه', () {
      final s = code['lib/screens/payment_summary_screen.dart']!;
      expect(
          RegExp(r'Map<String, dynamic> _serviceOrderPayload\(').allMatches(s).length,
          1,
          reason: 'تعريفانِ للحِملِ — النسختانِ تَنحرِفانِ كما انحرفتا');
      expect(RegExp(r'_serviceOrderPayload\(method:').allMatches(s).length, 2,
          reason: 'مُنادِيا الحِملِ ليسا اثنَين — موضعُ إنشاءٍ لا يَمُرُّ به '
              'يَفقدُ حقولاً كما فقدَ حقلَي الوعورة');
      // وكتلةُ حقولِ الطلبِ **واحدةٌ** في الملفِّ كلِّه — وهي جسمُ الدالّة.
      // (كتلةُ `_nativePayMeta` لا تَحملُ `status`/`is_paid` فتَخرُج.)
      final blocks = _fieldMapLiterals(s)
          .where((b) => b.contains("'status':") && b.contains("'is_paid':"))
          .toList();
      expect(blocks.length, 1,
          reason: 'كتلةُ حقولِ الطلبِ مكتوبةٌ ${blocks.length} مرّةً في '
              'payment_summary_screen — وهذا بعينُه ما أخفى حقلَي الوعورة');
      expect(blocks.single.contains("'terrain_surcharge_amount':"), isTrue,
          reason: 'الكتلةُ الباقيةُ ليست كتلةَ الحِملِ الكاملة');
      // و`amount` يُمرَّرُ **لقطةً** في مسارِ ما بعدَ الدفع: الشاشةُ
      // تَلتقطُ `amountToSave` قبلَ قراءةِ المستندِ وتَستعملُها في خصمِ
      // المحفظةِ وفي السجلِّ كذلك، فقراءةٌ حيّةٌ هنا تُخالِفُ تلك اللقطةَ
      // لو تغيّرَ التفصيلُ بينهما — حقلُ مالٍ على طلبٍ مدفوع.
      expect(s.contains('_serviceOrderPayload(method: method, amount: amountToSave)'),
          isTrue,
          reason: 'مسارُ ما بعدَ الدفعِ لم يَعُد يُمرّرُ لقطةَ المبلغِ — '
              'فالمكتوبُ على الطلبِ قد يُخالِفُ المخصومَ من المحفظة');
    });

    test('(ج) شاشةُ تمارا تَطلبُ الإنشاءَ ولا تَبنيه، والوسيطُ **مطلوب**', () {
      final c = code['lib/screens/checkout_screen.dart']!;
      // وسيطٌ مطلوبٌ لا مُفترَض: موضعُ نداءٍ منسيٌّ لا يَجوزُ أن يُبقي
      // السلوكَ القديمَ صامتاً — نفسُ قرارِ `passed` و`audience`.
      expect(RegExp(r'required\s+(?:final\s+)?Future<String>\s+Function\(\)\s+ensureOrder')
              .hasMatch(c) ||
          RegExp(r'required this\.ensureOrder').hasMatch(c),
          isTrue,
          reason: 'ensureOrder ليس وسيطاً مطلوباً — موضعُ نداءٍ منسيٌّ يَمُرُّ');
      expect(c.contains('widget.ensureOrder()'), isTrue,
          reason: 'شاشةُ تمارا لا تَطلبُ الإنشاءَ من موضعِه');
      // ولا تَبني حِملاً بنفسِها إطلاقاً
      for (final pl in _fieldMapLiterals(c)) {
        expect(pl.contains("'client_id':"), isFalse,
            reason: 'عادت نسخةُ حِملِ الإنشاءِ إلى checkout_screen — '
                'وهي التي انحرفت بثلاثةِ حقولٍ وهي ميّتة');
      }
      expect(c.contains('autoAssignDriverForHourly'), isFalse,
          reason: 'عادَ الإسنادُ من العميلِ في مسارِ تمارا — الإسنادُ خادميٌّ '
              '(sweepUnassignedPaidOrders بعد قلبِ tamaraWebhook العلَم)');
    });

    test('(د) شواهدُ التعليل: القارئُ يُخفي السطرَ، والخادمُ يُعيدُ الحساب', () {
      // لو زالَ أيٌّ منهما لَزِمَ مراجعةُ التعليلِ أعلاه لا إسكاتُه.
      final admin = stripComments(
          File('lib/screens/admin/admin_order_details_screen.dart').readAsStringSync());
      expect(
          RegExp(r"terrain_surcharge_amount'\] as num\?\)\?\.toDouble\(\) \?\? 0\) > 0")
              .hasMatch(admin),
          isTrue,
          reason: 'قارئُ سطرِ الوعورةِ لم يَعُد يُخفيه عند الغياب — '
              'فتعليلُ «بنودٌ لا تَبلغُ المجموعَ» يُراجَع');
      final pricing = stripComments(File('functions/pricing.js').readAsStringSync());
      expect(pricing.contains('zone.terrain_surcharge_percent'), isTrue,
          reason: 'الخادمُ لم يَعُد يَقرأُ الوعورةَ من مستندِ المنطقةِ — '
              'فدعوى «المالُ سليمٌ في الحالتَين» تُراجَع');
      // وحقلا الوعورةِ ما زالا داخلَ الموضعِ الواحد (وهما سببُ الشريحة)
      final s = code['lib/screens/payment_summary_screen.dart']!;
      final i = s.indexOf('Map<String, dynamic> _serviceOrderPayload(');
      expect(i, greaterThan(-1));
      var d = 0, k = s.indexOf('{', s.indexOf(')', i));
      final start = k;
      while (k < s.length) {
        if (s[k] == '{') {
          d++;
        } else if (s[k] == '}') {
          d--;
          if (d == 0) break;
        }
        k++;
      }
      final body = s.substring(start, k + 1);
      expect(body.contains("'terrain_surcharge_percent':"), isTrue);
      expect(body.contains("'terrain_surcharge_amount':"), isTrue,
          reason: 'حقلا الوعورةِ خرجا من الموضعِ الواحد — وهما بعينُهما '
              'ما كانت نسخةُ ما بعدَ الدفعِ تُغفلُه');
    });
  });
}
