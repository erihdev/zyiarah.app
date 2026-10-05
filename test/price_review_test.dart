import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/utils/price_review.dart';

/// **وسمُ مراجعةِ السعرِ: قارئٌ، وتصريفٌ، ومرآةٌ لا تَنحرف.**
///
/// تحقّقُ السعرِ الخادميُّ سياستُه «وسمٌ وتنبيهٌ لا رفض» (قرارٌ مقصود: الرفضُ
/// يَحجبُ دفعةَ عميلةٍ حقيقيّةٍ إن أخطأنا في الضريبةِ أو التقريب)، فمُخرَجُه
/// أعلامٌ على المستندِ ودفعةٌ إداريّةٌ نصُّها «راجع المبالغ واسترد الفارق أو
/// اعتمده» — **ولم يكن لأيٍّ من تلك الأعلامِ قارئٌ في أيِّ واجهة**: صفرُ
/// ورودٍ في `lib/` وصفرُ ورودٍ في `admin_panel/src/`. فالإدارةُ تَفتحُ الطلبَ
/// المُبلَّغَ عنه فتَراه طلباً عاديّاً تماماً، ولا سبيلَ إلى القولِ «راجعتُه
/// واعتمدتُه» — فنافذةُ `opsHealthSweep` (`limit(200)`) لا تُصرَّفُ أبداً،
/// وهو عطلُ «نافذةٌ تَمتلئُ بما لا يُزيلُه أحد» ثالثةً في هذه الجلسة.
///
/// والإدارةُ تَعملُ من سطحَين (تطبيقُ الأدمن واللوحة)، فقارئٌ في أحدِهما
/// وحدَه يَترُكُ الطلبَ عاديَّ المنظرِ لمن يَعملُ من الآخر — شكلُ «حقلُ قرارٍ
/// يَعرفُه محرّرٌ واحد» الذي تَكرّرَ في هذا المستودعِ أربعَ مرّاتٍ من قبل.
void main() {
  String read(String p) => File(p).readAsStringSync();

  /// الملفُّ بلا أسطرِ التعليقات — الشفرةُ تَشرحُ القرارَ باسمِ الحقل.
  String codeOnly(String p) => read(p)
      .split('\n')
      .where((l) {
        final t = l.trimLeft();
        return !t.startsWith('//') && !t.startsWith('*') && !t.startsWith('/*');
      })
      .join('\n');

  /// يَستخرِجُ قائمةَ نصوصٍ من مصدرٍ بعد اسمٍ مُعطى.
  ///
  /// **لا `indexOf('[')`**: التصريحُ في TypeScript هو
  /// `NAME: string[] = [` — فأوّلُ قوسٍ مربّعٍ هو قوسُ **نوعِ** المصفوفةِ لا
  /// بدايتُها، وهو الفخُّ الذي أسقطَ حارسَين في هذا المستودعِ من قبل. فنَبدأُ
  /// من `= [` أو `= <String>[`.
  List<String> listAfter(String src, String name) {
    final int at = src.indexOf(name);
    expect(at, greaterThan(-1), reason: '$name غير موجود');
    int open = src.indexOf('= [', at);
    final int openDart = src.indexOf('= <String>[', at);
    if (openDart > -1 && (open == -1 || openDart < open)) {
      open = openDart + '= <String>'.length;
    } else {
      open = open + '= '.length;
    }
    int depth = 0;
    int end = -1;
    for (int i = open; i < src.length; i++) {
      if (src[i] == '[') depth++;
      if (src[i] == ']') {
        depth--;
        if (depth == 0) {
          end = i;
          break;
        }
      }
    }
    expect(end, greaterThan(open), reason: 'قائمةُ $name غير مغلقة');
    return RegExp("['\"]([a-z_]+)['\"]")
        .allMatches(src.substring(open, end))
        .map((m) => m.group(1)!)
        .toList();
  }

  group('الحالاتُ الثلاث', () {
    test('لا وسم ⇒ لا بطاقة', () {
      final r = priceReviewOf({'amount': 300, 'is_paid': true});
      expect(r.kind, PriceReviewKind.none);
      expect(r.needsCard, isFalse);
      expect(r.actionable, isFalse);
    });

    test('price_mismatch ⇒ underpaid بأرقامِ الخادم', () {
      final r = priceReviewOf({
        'price_mismatch': true,
        'price_paid': 120,
        'price_expected': 300,
        'price_expected_net': 300,
        'price_shadow_ratio': 0.4,
      });
      expect(r.kind, PriceReviewKind.underpaid);
      expect(r.paid, 120);
      expect(r.expected, 300);
      expect(r.ratio, 0.4);
      expect(r.shortfall, 180);
      expect(r.actionable, isTrue);
    });

    test('price_unverifiable ⇒ جهلٌ لا نقصٌ في الدفع', () {
      final r = priceReviewOf({'price_unverifiable': true, 'price_paid': 300});
      expect(r.kind, PriceReviewKind.unverifiable);
      expect(r.shortfall, isNull);
      expect(r.actionable, isTrue);
    });

    test('الوسمانِ معاً ⇒ الأولويّةُ للرقمِ على الجهل', () {
      final r =
          priceReviewOf({'price_mismatch': true, 'price_unverifiable': true});
      expect(r.kind, PriceReviewKind.underpaid);
    });
  });

  group('الصافي قبلَ الإجمالي — وإلّا ضُخّم الفارق', () {
    // مسارُ ميسر يَكتبُ `price_expected` قبلَ الخصمِ الموثوقِ و
    // `price_expected_net` بعدَه، والمقارنةُ التي أنتجت الوسمَ على الصافي.
    // فعرضُ الأوّلِ وحدَه يَجعلُ الفارقَ أكبرَ بقيمةِ الكوبون — فتَستردُّ
    // الإدارةُ مالاً لا تَملكُه.
    test('يُقدَّمُ الصافي', () {
      final r = priceReviewOf({
        'price_mismatch': true,
        'price_paid': 100,
        'price_expected': 300,
        'price_expected_net': 150,
      });
      expect(r.expected, 150);
      expect(r.shortfall, 50);
    });

    test('وعند غيابِه يُقرأُ الإجمالي (مسارُ المحفظةِ يَكتبُه وحدَه)', () {
      final r = priceReviewOf(
          {'price_mismatch': true, 'price_paid': 100, 'price_expected': 200});
      expect(r.expected, 200);
    });
  });

  group('الصفرُ قرارٌ لا غياب', () {
    test('متوقَّعٌ صفرٌ ودفعٌ موجب ⇒ مريبٌ بلا فارقٍ ولا نسبة', () {
      final r = priceReviewOf({
        'price_mismatch': true,
        'price_paid': 120,
        'price_expected_net': 0,
      });
      expect(r.suspiciousZero, isTrue);
      expect(r.shortfall, isNull);
    });

    test('ومتوقَّعٌ صفرٌ بلا دفعٍ ليس مريباً', () {
      final r = priceReviewOf({
        'price_mismatch': true,
        'price_paid': 0,
        'price_expected_net': 0,
      });
      expect(r.suspiciousZero, isFalse);
    });
  });

  group('سببُ رفضِ الكوبون', () {
    // كوبونُ 10% يُنتجُ نسبةَ 0.9 فلا يَبلغُ عتبةَ النصف: لا وسمَ ولا تنبيه،
    // والسببُ وحدَه على المستند — ولم يكن يُعرَضُ في أيِّ شاشة.
    test('يَظهرُ ولو بلا وسمٍ أصلاً، وبلا زرّ', () {
      final r = priceReviewOf({'coupon_rejected_reason': 'other_user'});
      expect(r.kind, PriceReviewKind.none);
      expect(r.needsCard, isTrue);
      expect(r.actionable, isFalse);
    });

    test('وفارغُه ليس سبباً', () {
      expect(
          priceReviewOf({'coupon_rejected_reason': '  '}).couponRejectedReason,
          isNull);
      expect(priceReviewOf({'coupon_rejected_reason': ''}).needsCard, isFalse);
    });

    test('والأسبابُ هي ما يُعيدُه الخادمُ بالضبط', () {
      // المصدرُ `functions/coupons.js` — سببٌ يُضافُ هناك بلا ترجمةٍ هنا
      // يُطبَعُ بالإنجليزيّةِ في واجهةٍ عربيّة.
      final cj = codeOnly('functions/coupons.js');
      final served = RegExp('return "([a-z_]+)";')
          .allMatches(cj)
          .map((m) => m.group(1)!)
          .toSet();
      expect(served.isNotEmpty, isTrue, reason: 'لم يُقرأ أيُّ سببٍ — نمطٌ معطوب');
      expect(kCouponRejectReasons.keys.toSet(), served,
          reason: 'مجموعةُ الأسبابِ انحرفت عن الخادم');
    });
  });

  group('المُعتمَدُ سابقاً يَبقى مرئيّاً', () {
    // الاعتمادُ يُبطِلُ علمَ الاستعلام، فلو كان الظهورُ معلَّقاً عليه وحدَه
    // لاختفى القرارُ وصاحبُه لحظةَ اتّخاذِه — صمتٌ من الجهةِ الأخرى.
    test('بلا وسمٍ ومع طابعِ مراجعةٍ ⇒ بطاقةٌ بلا زرّ', () {
      final r = priceReviewOf({
        'price_mismatch': false,
        'price_reviewed_at': 1,
        'price_reviewed_by': 'a@b.c',
      });
      expect(r.needsCard, isTrue);
      expect(r.actionable, isFalse);
      expect(r.reviewedAtPresent, isTrue);
    });
  });

  group('حِمْلُ الاعتماد', () {
    test('يُبطِلُ علمَي الاستعلامِ ويُوقّعُ القرار', () {
      final p = priceReviewApprovalPayload('a@b.c');
      for (final f in kPriceReviewQueryFlags) {
        expect(p[f], isFalse, reason: '$f لم يُبطَل — المستندُ يَبقى في النافذة');
      }
      expect(p['price_review_decision'], 'approved');
      expect(p['price_reviewed_by'], 'a@b.c');
    });

    test('ولا يَمحو حقلَ شاهدٍ واحداً', () {
      final p = priceReviewApprovalPayload('a@b.c');
      for (final f in kPriceReviewEvidenceFields) {
        expect(p.containsKey(f), isFalse,
            reason: '$f يُمحى — الرقمُ الذي بُني عليه القرارُ يَجبُ أن يَبقى');
      }
    });

    test('والطابعُ الزمنيُّ ليس في الحِمْل — يُضيفُه موضعُ النداء', () {
      // كي يَبقى `price_review.dart` نقيّاً قابلاً للاختبارِ بلا Firebase.
      expect(priceReviewApprovalPayload('x').containsKey('price_reviewed_at'),
          isFalse);
      for (final f in [
        'lib/screens/admin/admin_order_details_screen.dart',
        'lib/screens/admin/admin_store_orders_screen.dart',
      ]) {
        expect(codeOnly(f).contains("'price_reviewed_at': FieldValue.serverTimestamp()"),
            isTrue,
            reason: '$f لا يَكتبُ طابعَ المراجعةِ — فلا يُعرَفُ متى اعتُمد');
      }
    });
  });

  group('المرآةُ بين اللغتَين', () {
    test('قوائمُ الحقولِ متطابقةٌ حرفاً', () {
      final ts = read('admin_panel/src/utils/priceReview.ts');
      expect(listAfter(ts, 'PRICE_REVIEW_QUERY_FLAGS'), kPriceReviewQueryFlags);
      expect(listAfter(ts, 'PRICE_REVIEW_EVIDENCE_FIELDS'),
          kPriceReviewEvidenceFields);
      // وأسبابُ الكوبونِ بنفسِ المفاتيح.
      final tsReasons = RegExp(r'^\s{2}([a-z_]+):', multiLine: true)
          .allMatches(ts.substring(ts.indexOf('COUPON_REJECT_REASONS'),
              ts.indexOf('};', ts.indexOf('COUPON_REJECT_REASONS'))))
          .map((m) => m.group(1)!)
          .toSet();
      expect(tsReasons, kCouponRejectReasons.keys.toSet());
    });
  });

  group('مواضعُ النداء — قاعدةٌ لا تُنادى قاعدةٌ ميتة', () {
    test('تطبيقُ الإدارة: الطلبُ والمتجرُ يَعرضانِ الوسمَ ويَعتمدانِه', () {
      final det = codeOnly('lib/screens/admin/admin_order_details_screen.dart');
      expect(det.contains('priceReviewOf(data).needsCard'), isTrue,
          reason: 'البطاقةُ غيرُ مشروطةٍ بالحالة');
      expect(det.contains('_buildPriceReviewCard(data)'), isTrue);
      expect(det.contains('priceReviewApprovalPayload('), isTrue,
          reason: 'لا اعتماد ⇒ النافذةُ لا تُصرَّفُ أبداً');
      expect(det.contains('ZyiarahAuditService.actionReviewOrderPrice'), isTrue,
          reason: 'قرارٌ ماليٌّ بلا أثرٍ باسمِ من اتّخذَه');
      // والزرُّ وحدَه محكومٌ بالدور: المحاسبةُ في جمهورِ التنبيهِ فتَرى
      // البطاقةَ، والقواعدُ تَقصرُ الكتابةَ على مديري الطلبات.
      expect(det.contains('pending && _canEditOrders'), isTrue);

      final st = codeOnly('lib/screens/admin/admin_store_orders_screen.dart');
      expect(st.contains('_priceReviewBanner('), isTrue);
      expect(st.contains('priceReviewApprovalPayload('), isTrue);
      expect(st.contains('ZyiarahAuditService.actionReviewOrderPrice'), isTrue);
    });

    test('اللوحة: الصفحتانِ تَعرضانِ الشارةَ وتَعتمدانِ المبلغ', () {
      for (final f in [
        'admin_panel/src/pages/Orders.tsx',
        'admin_panel/src/pages/StoreOrders.tsx',
      ]) {
        final src = codeOnly(f);
        expect(src.contains('PriceReviewBadge'), isTrue, reason: '$f بلا شارة');
        expect(src.contains('priceReviewApprovalPayload('), isTrue,
            reason: '$f بلا اعتماد');
        expect(src.contains('AUDIT.REVIEW_ORDER_PRICE'), isTrue,
            reason: '$f بلا أثرِ تدقيق');
      }
    });

    test('وقائمةُ إجراءاتِ اللوحةِ تَظهرُ على الطلبِ النهائيِّ الموسوم', () {
      // الطلبُ الموسومُ قد يكون `completed`، وشرطُ ظهورِ القائمةِ كان
      // `!isFinalStatus(order) || canBnplRefund(order)` — فيَصيرُ الاعتمادُ
      // غيرَ قابلٍ للوصولِ على أكثرِ الطلباتِ وسماً.
      final src = codeOnly('admin_panel/src/pages/Orders.tsx');
      final i = src.indexOf('canBnplRefund(order) ||');
      expect(i, greaterThan(-1),
          reason: 'شرطُ ظهورِ القائمةِ لم يَعُد يَشملُ الوسمَ');
      expect(src.substring(i, i + 160).contains('.actionable'), isTrue);
    });

    test('ورمزُ الأثرِ واحدٌ على السطحَين', () {
      expect(read('lib/services/audit_service.dart')
          .contains("actionReviewOrderPrice = 'REVIEW_ORDER_PRICE'"), isTrue);
      expect(read('admin_panel/src/services/audit.ts')
          .contains("REVIEW_ORDER_PRICE: 'REVIEW_ORDER_PRICE'"), isTrue);
    });
  });

  group('الخادمُ يَكتبُ ما يَقرأُه القارئ', () {
    test('كلُّ حقلٍ تَقرأُه الواجهةُ له كاتبٌ في index.js', () {
      final idx = codeOnly('functions/index.js');
      for (final f in [
        ...kPriceReviewQueryFlags,
        'price_paid',
        'price_expected',
        'price_expected_net',
        'price_shadow_ratio',
        'coupon_rejected_reason',
      ]) {
        expect(idx.contains('$f:'), isTrue,
            reason: '$f تَقرأُه الواجهةُ ولا يَكتبُه الخادمُ — رقمٌ لا يَأتي');
      }
    });

    test('وأعلامُ الوسمِ محجوبةٌ عن الإنشاءِ العميليّ', () {
      // عميلةٌ تُنشئُ طلبَها بـ`price_mismatch: false` تُطفئُ الوسمَ قبلَ
      // كتابتِه؛ وبـ`price_review_decision: 'approved'` تَكتبُ شهادةً لم
      // يُوقّعها أحد.
      final rules = read('firestore.rules');
      for (final f in [
        'price_mismatch',
        'price_unverifiable',
        'price_paid',
        'ops_alerted_unverifiable',
        'price_review_decision',
        'price_reviewed_by',
        'price_reviewed_at',
      ]) {
        expect(rules.contains("'$f'"), isTrue,
            reason: '$f مكشوفٌ للإنشاءِ العميليّ');
      }
    });
  });
}
