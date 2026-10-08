import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'helpers/sources_in.dart';
import 'helpers/strip_comments.dart';

/// **حقلٌ يَكتبُه الخادمُ على `users/{uid}` ولا يَقرؤه سطح.**
///
/// سبعةُ حقولٍ كانت كذلك (2026-10-08): خمسةٌ للاشتراك
/// (`has_active_subscription`، `visits_remaining`، `subscription_expiry`،
/// `subscription_total_visits`، `subscription_type`) واثنانِ للإحالة
/// (`used_referral_code`، `referred_by`). يَكتبُها الخادمُ، و
/// `ZyiarahUser.fromMap` يُحلّلُها، و**صفرُ قارئٍ** في العميلِ والخادمِ
/// واللوحة.
///
/// وثلاثُ حقائقَ تَجعلُ الحذفَ هو الجوابَ لا التوصيل:
///
///   • **الرصيدُ الحيُّ لكلِّ عقدٍ على العقد**: `contracts/{id}.visits_remaining`
///     تَقرؤه `contract_visits.dart` في ثلاثةِ أسطح، وبطاقةُ الرئيسيّةِ
///     تَبثُّ `contracts` ولا تَمَسُّ مستندَ المستخدم. وتعليقُ
///     `_activateContractNow` يَقولُ سببَ العدّاداتِ المستقلّةِ بنصِّه:
///     «بدل طمس حقول المستخدم المجمّعة بعضها بعضاً».
///   • **ونسخةُ المستخدمِ خاطئةٌ بالبناء** مع عقدَين نشطَين: الرصيدُ
///     `increment` (مجموعٌ على العقود) والثلاثةُ الأخرى يَغلِبُ فيها آخرُ
///     كاتب — فـ«١٦ من ٨».
///   • **والإحالةُ محفوظةٌ في مستندِها**: المعامَلةُ نفسُها تَكتبُ
///     `referrals/{uid}` بمعرّفٍ حتميٍّ هو uid المُحالِ إليه، وفيه
///     `referrer_id`/`referee_id`/`referral_code` — الحقائقُ الثلاثُ نفسُها.
///
/// وكانت الكلفةُ مكتوبةً لا نظريّةً: `settleVisitAccounting` يُحرّكُ النسخةَ
/// مع **كلِّ** زيارةٍ تُستهلَكُ أو تُردّ، وتنبيهُ الفشلِ الحيُّ كان يَقولُ
/// للأدمنِ أن يُسوّيَ «`users/{uid}.visits_remaining` وعلى عدّاد العقد» —
/// فنصفُ التعليماتِ إصلاحُ حقلٍ لا يَقرؤه أحد، ويَترُكُه يَحسبُ أنّ رصيدَ
/// العميلةِ أُصلِح.
void main() {
  final idx = stripComments(File('functions/index.js').readAsStringSync());
  final rewards = stripComments(File('functions/rewards.js').readAsStringSync());

  test('(أ) كلُّ حقلٍ يَكتبُه الخادمُ على users/{uid} له قارئ', () {
    final writes = _userWrites();
    // أرضيّةٌ للاستخراج: كاشفٌ يَنحلُّ يَمُرُّ أخضرَ على لا شيء.
    expect(writes.length, greaterThanOrEqualTo(1),
        reason: 'الاستخراجُ انحلَّ — لا كتابةَ واحدةً على `users/` وُجدت، '
            'والحارسُ بلا موضوع');
    final readers = _readerCorpus();
    final unread = <String>[];
    writes.forEach((field, where) {
      final re = RegExp('(?<![A-Za-z0-9_])${RegExp.escape(field)}'
          '(?![A-Za-z0-9_])');
      final hasReader = readers.entries.any((e) {
        for (final m in re.allMatches(e.value)) {
          // كتابةٌ لا قراءة: `field:` في حِمْلٍ، أو `field =`.
          final tail = e.value.substring(m.end).trimLeft();
          if (tail.startsWith(':') || tail.startsWith('=')) continue;
          return true;
        }
        return false;
      });
      if (!hasReader) unread.add('$field  ($where)');
    });
    expect(unread, isEmpty,
        reason: 'حقولٌ يَكتبُها الخادمُ على مستندِ المستخدمِ ولا يَقرؤها شيء — '
            'إمّا نُسِي توصيلُها أو كُتبت ولم تُستعمَل قطّ:\n'
            '${unread.map((x) => '    • $x').join('\n')}');
  });

  test('(ب) والكاشفُ يَعضُّ — والأشكالُ التي تُشبهُه ولا تُطابِقُه', () {
    // الحارسُ شفرةٌ تُختبَرُ كالشفرة: المصدرُ بعدَ الحذفِ لا يَحملُ حقلاً
    // بلا قارئ، فنجاحُ (أ) وحدَه لا يُبرهِنُ أنّ الاستخراجَ يَرى كتابةً.
    const sample = '''
      tx.set(db.collection("users").doc(c.userId), {
        visits_remaining: FieldValue.increment(pv),
        has_active_subscription: true,
      }, {merge: true});
      const walletRef = db.collection("wallets").doc(uid);
      walletRef.set({balance: 1});
      t.set(db.collection("contracts").doc(cId), {visits_remaining: 1});
''';
    final got = _fieldsOfUserWrites(sample);
    expect(got, containsAll(<String>['visits_remaining', 'has_active_subscription']),
        reason: 'الكاشفُ لا يَرى حِمْلَ `users/` — الحارسُ أجوف');
    expect(got, isNot(contains('balance')),
        reason: 'حِمْلُ `wallets/` ليس حِمْلَ المستخدم');
    expect(got.where((f) => f == 'visits_remaining').length, 1,
        reason: 'حِمْلُ `contracts/` دخلَ المجموعة — الكاشفُ لا يُفرّقُ الوجهة');
    // ومرجعٌ وسيطٌ يُحَلُّ: `const ref = ...users...; ref.set({...})`.
    const viaRef = '''
      const userRef = db.collection("users").doc(clientId);
      t.set(userRef, {visits_remaining: 1}, {merge: true});
''';
    expect(_fieldsOfUserWrites(viaRef), contains('visits_remaining'),
        reason: 'المرجعُ الوسيطُ لا يُحَلُّ — وهو الشكلُ الذي كان في '
            '`settleVisitAccounting` بعينِه');
  });

  test('(ج) ولا تَعودُ السبعةُ — قائمةُ منعٍ صريحة', () {
    // العمى المُعلَنُ في رأسِ `no_dead_code_test`: اسمٌ يَتصادمُ مع نظائرِه
    // لا يَراه الفحصُ العامّ، وعلاجُه المُعلَنُ قائمةٌ صريحةٌ كـ`no_tabby_test`.
    const gone = [
      'has_active_subscription',
      'subscription_total_visits',
      'subscription_type',
      'subscription_expiry',
      'used_referral_code',
      'referred_by',
    ];
    for (final f in gone) {
      expect(idx.contains('$f:'), isFalse, reason: '`$f` عادَ إلى index.js');
      expect(rewards.contains('$f:'), isFalse,
          reason: '`$f` عادَ إلى rewards.js');
    }
    // و`visits_remaining` يَبقى — **على العقدِ وحدَه**.
    expect(_userWrites().containsKey('visits_remaining'), isFalse,
        reason: 'عادت نسخةُ `users/{uid}.visits_remaining` — عدّادٌ ثانٍ '
            'بلا قارئ، ومجموعٌ على العقودِ بجوارِ ثلاثةٍ يَغلِبُ فيها '
            'آخرُ كاتب');
    expect(idx.contains('visits_remaining:'), isTrue,
        reason: 'عدّادُ العقدِ نفسُه زالَ — بطاقةُ الباقةِ بلا رصيد');
  });

  test('(د) ولا يَعودُ النوعانِ المحذوفانِ ولا جالباتُ الاشتراك', () {
    // نوعانِ بأسماءِ حقولٍ عامّةٍ (`id`/`items`/`status`) لا يَراهما الفحصُ
    // العامُّ كذلك: `StoreOrder` (طلباتُ المتجرِ خرائطُ خامّة) و
    // `WalletTransaction` (مجموعتُها `wallet_transactions` لا وجودَ لها —
    // السجلُّ الحقيقيُّ `transactions`، ولا شاشةَ تَقرؤه).
    final lib = _libCorpus();
    for (final t in ['class StoreOrder', 'class WalletTransaction']) {
      expect(lib.values.any((s) => s.contains(t)), isFalse,
          reason: '`$t` عاد — نوعٌ بلا مرجعٍ خارجَ ملفِّه');
    }
    // **والشكلانِ لا الاسمُ العاري**: وصولُ عضوٍ (`.name`) ووَسمُ البانيةِ
    // (`name:`) — وهما ما يَعودُ لو أُعيدَ الحقل. والاسمُ العاريُّ يُطابقُ
    // متغيّراً محلّيّاً مشروعاً: `final isHidden = data?['is_hidden'] != false`
    // في `admin_store_screen` سطحٌ إداريٌّ يَقرأُ الحقلَ خامّاً، وأوّلُ
    // صياغةٍ أسقطت الفحصَ عليه (فخُّ الاحتواء).
    for (final g in [
      'hasActiveSubscription',
      'visitsRemaining',
      'subscriptionExpiry',
      'subscriptionType',
      'subscriptionTotalVisits',
      'newPoints',
      'isHidden',
    ]) {
      for (final shape in ['.$g', '$g:']) {
        expect(lib.values.any((s) => s.contains(shape)), isFalse,
            reason: '`$shape` عادَ إلى lib/ — جالبٌ يُحلَّلُ ولا يُقرَأ');
      }
    }
  });

  test('(هـ) وشواهدُ التعليل: العدّادُ على العقدِ، والإحالةُ في مستندِها', () {
    // (١) بطاقةُ الرئيسيّةِ تَبثُّ `contracts` لا مستندَ المستخدم.
    final dash = stripComments(
        File('lib/screens/client_dashboard.dart').readAsStringSync());
    expect(dash.contains("collection('contracts')"), isTrue,
        reason: 'البطاقةُ لم تَعُد تَبثُّ `contracts` — يُراجَعُ تعليلُ الحذف');
    // (٢) والرصيدُ المعروضُ من قاعدةِ العقد.
    final cv = stripComments(
        File('lib/utils/contract_visits.dart').readAsStringSync());
    expect(cv.contains("'visits_remaining'"), isTrue,
        reason: 'قاعدةُ العقدِ لم تَعُد تَقرأُ العدّاد');
    // (٣) ومعامَلةُ الإحالةِ تَكتبُ الحقائقَ الثلاثَ في `referrals/{uid}`.
    for (final f in ['referrer_id:', 'referee_id:', 'referral_code:']) {
      expect(idx.contains(f), isTrue,
          reason: 'مستندُ الإحالةِ لم يَعُد يَحملُ `$f` — فنسخةُ المستخدمِ '
              'لم تَكن تكراراً، ويُراجَعُ الحذف');
    }
    // (٤) وتنبيهُ الفشلِ لم يَعُد يُحيلُ الأدمنَ إلى حقلٍ بلا قارئ.
    expect(rewards.contains('users/{uid}.visits_remaining'), isFalse,
        reason: 'التنبيهُ يَقولُ للأدمنِ أن يُسوّيَ حقلاً لا يَقرؤه أحد');
    expect(rewards.contains('contracts/{id}.visits_remaining'), isTrue,
        reason: 'التنبيهُ بلا الحقلِ الذي يُسوّى فعلاً');
  });
}

/// حقولُ كلِّ حِمْلٍ يَكتبُه الخادمُ على `users/{uid}` ← موضعُه.
Map<String, String> _userWrites() {
  final out = <String, String>{};
  for (final f in sourcesIn('functions', atLeast: 12, exts: const ['.js'])) {
    final rel = f.path.replaceAll(r'\', '/');
    if (rel.contains('/node_modules/') ||
        rel.contains('/test/') ||
        rel.endsWith('eslint.config.js')) {
      continue;
    }
    final src = stripComments(f.readAsStringSync());
    for (final field in _fieldsOfUserWrites(src)) {
      out[field] = rel.split('/').last;
    }
  }
  return out;
}

/// أسماءُ الحقولِ في كلِّ `X.set|update(<مرجعُ users>, { … })`.
///
/// **بموازنةِ الأقواسِ لا بنافذةِ أحرف**، ومعه حلُّ مرجعٍ وسيطٍ
/// (`const userRef = db.collection("users").doc(uid)`) — وهو الشكلُ الذي
/// كان في `settleVisitAccounting`، فبلا الحلِّ يَعمى الكاشفُ عنه.
List<String> _fieldsOfUserWrites(String src) {
  final out = <String>[];
  for (final m in RegExp(r'\.(?:set|update)\s*\(').allMatches(src)) {
    final end = _balanced(src, m.end - 1, '(', ')');
    if (end < 0) continue;
    final args = src.substring(m.end, end);
    // أوّلُ `{` على العمقِ صفرٍ هو الحِمْل؛ ما قبلَه هو المرجع.
    var depth = 0, ob = -1;
    for (var i = 0; i < args.length; i++) {
      final c = args[i];
      if (c == '(' || c == '[') {
        depth++;
      } else if (c == ')' || c == ']') {
        depth--;
      } else if (c == '{' && depth == 0) {
        ob = i;
        break;
      }
    }
    if (ob < 0) continue;
    var target = args.substring(0, ob).trim();
    if (target.endsWith(',')) target = target.substring(0, target.length - 1);
    target = target.trim();
    if (RegExp(r'^[A-Za-z_$][\w$]*$').hasMatch(target)) {
      final decl = RegExp('(?:const|let|var)\\s+${RegExp.escape(target)}'
              r'\s*=\s*([^;]+);')
          .firstMatch(src);
      if (decl != null) target = decl.group(1)!;
    }
    if (!target.contains('"users"') && !target.contains("'users'")) continue;
    final pe = _balanced(args, ob, '{', '}');
    if (pe < 0) continue;
    final blk = args.substring(ob, pe + 1);
    for (final k
        in RegExp(r'[{,]\s*([a-z_][a-z0-9_]*)\s*:').allMatches(blk)) {
      out.add(k.group(1)!);
    }
  }
  return out;
}

int _balanced(String s, int i, String open, String close) {
  var d = 0;
  for (var j = i; j < s.length; j++) {
    if (s[j] == open) {
      d++;
    } else if (s[j] == close) {
      d--;
      if (d == 0) return j;
    }
  }
  return -1;
}

Map<String, String> _libCorpus() {
  final out = <String, String>{};
  for (final f in sourcesIn('lib', atLeast: 150)) {
    out[f.path.replaceAll(r'\', '/')] = stripComments(f.readAsStringSync());
  }
  return out;
}

/// كلُّ ما قد يَقرأُ حقلاً: العميلُ، والخادمُ، واللوحة.
Map<String, String> _readerCorpus() {
  final out = <String, String>{}..addAll(_libCorpus());
  for (final f in sourcesIn('functions', atLeast: 12, exts: const ['.js'])) {
    final rel = f.path.replaceAll(r'\', '/');
    if (rel.contains('/node_modules/')) continue;
    out[rel] = stripComments(f.readAsStringSync());
  }
  for (final f in sourcesIn('admin_panel/src',
      atLeast: 20, exts: const ['.ts', '.tsx'])) {
    out[f.path.replaceAll(r'\', '/')] =
        stripComments(f.readAsStringSync());
  }
  return out;
}
