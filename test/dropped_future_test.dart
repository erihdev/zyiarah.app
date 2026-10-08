import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'helpers/sources_in.dart';
import 'helpers/strip_comments.dart';

/// **نداءٌ مُسقَطٌ لا يَجدُ مَن يَلتقطُ رميَه (2026-10-08).**
///
/// `unawaited_futures` **ليست مُفعَّلةً** في `analysis_options.yaml` (ولا
/// يُفعّلُها `flutter_lints`)، ومستقبَلٌ مُسقَطٌ لا يُحذّرُ منه شيء. والنتيجةُ
/// أنّ رميَه **لا يَجدُ مُعالِجاً على الإطلاق**: لا `await` يَنقلُه إلى
/// `catch`، ولا مُنادِيَ يَنتظرُه — فيَصيرُ خطأً غيرَ مُعالَجٍ يَلتقطُه
/// `PlatformDispatcher.onError` في `main.dart` ويُسجّلُه **قاتلاً**، وكلُّ
/// ما كان بعدَ سطرِ الرميِ لا يُنفَّذ.
///
/// والقاعدةُ مقرَّرةٌ في هذا المستودعِ مرّتَين قبلَ اليوم — حُرّاسُ الإقلاعِ
/// في `main()`، وتحميلُ بياناتِ المستخدمِ في `contract_signing_screen` —
/// وكانت مُنفَّذةً **موضعاً موضعاً**. فهذا قارئُها العامّ: **ما لا يُنتظَرُ
/// لا يَجوزُ أن يَرمي.**
///
/// شكلانِ يَدخلانِ النطاق:
///
///  **(أ) `void f(…) async`** — مستقبَلُها لا يُمكِنُ انتظارُه **بالبناء**،
///      فلا مُنادِيَ قادرٌ على التقاطِ رميِها بحال. وهكذا كانت
///      `order_tracking._callDriver` تُنادي `launchUrl` عارية.
///  **(ب) نداءٌ في موضعِ جملةٍ** يُسقِطُ مستقبَلَ عضوٍ في المشروع — نمطُ
///      `initState` المعتاد — فالمُنادى يَجبُ أن يَكونَ محروساً داخليّاً.
///
/// وما يُقبَلُ `await`اً عارياً يُحَلُّ لا يُستثنى: `Future.delayed` وحوارٌ
/// وإلغاءُ اشتراكٍ لا تَرمي، وعضوٌ في المشروعِ محروسٌ بنفسِه يَكفي حرسُه
/// مُنادِيَه (حلٌّ متعدٍّ). فلا تَبقى في القائمةِ إلّا حالةٌ لا تُحَلُّ.
void main() {
  /// كلُّ `(` إلى إغلاقِها — لا `indexOf(')')`.
  int afterParens(String s, int from) {
    final o = s.indexOf('(', from);
    var d = 1;
    var i = o + 1;
    while (i < s.length && d > 0) {
      if (s[i] == '(') d++;
      if (s[i] == ')') d--;
      i++;
    }
    return i;
  }

  /// جسمُ عضوٍ من موضعِ إعلانِه — **بموازنةِ قائمةِ المعامَلاتِ أوّلاً** ثمّ
  /// المعقوفة (فخُّ الحدِّ، مسجَّلٌ عشرَ مرّاتٍ في هذا المستودع).
  (int, String)? bodyAt(String s, int declAt) {
    final i = afterParens(s, declAt);
    final brace = s.indexOf('{', i);
    if (brace < 0 || brace - i > 40) return null;
    var d = 1;
    var j = brace + 1;
    while (j < s.length && d > 0) {
      if (s[j] == '{') d++;
      if (s[j] == '}') d--;
      j++;
    }
    return (brace, s.substring(brace, j));
  }

  List<(int, int)> tryRanges(String body) {
    final out = <(int, int)>[];
    for (final m in RegExp(r'\btry\s*\{').allMatches(body)) {
      final b = m.end - 1;
      var d = 1;
      var i = b + 1;
      while (i < body.length && d > 0) {
        if (body[i] == '{') d++;
        if (body[i] == '}') d--;
        i++;
      }
      out.add((b, i));
    }
    return out;
  }

  // ── المصدرُ، مُجرَّداً من التعليقاتِ والنصوص ───────────────────────────
  final files = <String, String>{};
  for (final f in sourcesIn('lib', atLeast: 150)) {
    files[f.path] = stripComments(f.readAsStringSync());
  }

  /// أعضاءُ `Future` في المشروعِ: الاسمُ ← جسمُه (أوّلُ تعريفٍ يَفوز؛
  /// والأسماءُ المكرَّرةُ تُحَلُّ محافظةً — إن كان أيٌّ منها غيرَ محروسٍ
  /// عُدَّ غيرَ محروس).
  final futureBodies = <String, List<String>>{};
  final declRe = RegExp(r'\bFuture(?:<[^>]*>)?\s+(_?[a-zA-Z]\w*)\s*\(');
  for (final e in files.entries) {
    for (final m in declRe.allMatches(e.value)) {
      final got = bodyAt(e.value, m.start);
      if (got == null) continue;
      futureBodies.putIfAbsent(m.group(1)!, () => <String>[]).add(got.$2);
    }
  }

  /// `await` لا يَرمي، بالنوعِ لا بالاسم.
  bool benignAwait(String tail) =>
      RegExp(r'^\s*Future\.delayed\s*\(').hasMatch(tail) ||
      RegExp(r'^\s*showDialog\s*(?:<[^>()]*>)?\s*\(').hasMatch(tail) ||
      RegExp(r'^\s*[\w.$?!]*\.cancel\s*\(\s*\)').hasMatch(tail);

  final wrappedMemo = <String, bool>{};

  // تَعاودٌ متبادلٌ بين الدالّتَين — دارت تَلزمُها إحالةٌ مُؤجَّلة.
  late final bool Function(String name, int depth) memberWrapped;

  bool fullyWrapped(String body, [int depth = 0]) {
    final trs = tryRanges(body);
    for (final a in RegExp(r'\bawait\b').allMatches(body)) {
      if (trs.any((r) => r.$1 < a.start && a.start < r.$2)) continue;
      final tail = body.substring(a.end);
      if (benignAwait(tail)) continue;
      // عضوٌ في المشروعِ محروسٌ بنفسِه — حلٌّ متعدٍّ بعمقٍ محدود.
      // اسمُ العضوِ بعدَ سلسلةِ مُؤهِّلاتٍ اختياريّة (`A.b(`، `A().b(`،
      // `x.y.z(`) — وبلا ذلك يُقرأُ المُؤهِّلُ اسمَ العضوِ فلا يُحَلُّ شيء.
      final call = RegExp(r'^\s*(?:[A-Za-z_]\w*(?:\s*\(\s*\))?\s*[.!?]*\s*\.\s*)*'
              r'(_?[a-zA-Z]\w*)\s*\(')
          .firstMatch(tail);
      if (call != null && depth < 4 && memberWrapped(call.group(1)!, depth + 1)) {
        continue;
      }
      return false;
    }
    return true;
  }

  memberWrapped = (String name, int depth) {
    final cached = wrappedMemo[name];
    if (cached != null) return cached;
    final bodies = futureBodies[name];
    if (bodies == null || bodies.isEmpty) return false;
    wrappedMemo[name] = false; // يَكسِرُ الدورانَ محافظةً
    final ok = bodies.every((b) => fullyWrapped(b, depth));
    wrappedMemo[name] = ok;
    return ok;
  };

  // ── الاستثناءاتُ المُعلَنةُ، لكلٍّ سببُه ───────────────────────────────
  const declared = <String, String>{
    'lib/main.dart::main':
        'الـ`await` الوحيدُ العاري داخلَ إغلاقِ `LicenseRegistry.addLicense(() '
            'async* …)` **الكسول**: لا يَعملُ إلّا متى فُتحت صفحةُ التراخيص، '
            'ومستقبَلُه يَملكُه مَن يَستهلكُ المُولِّد. وحُرّاسُ الإقلاعِ '
            'نفسُها مشدودةٌ في `boot_resilience_test`.',
  };

  test('(أ) `void … async` لا يُمكِنُ انتظارُها — فلا يَجوزُ أن تَرمي', () {
    final voidAsync =
        RegExp(r'(?<![\w>])void\s+(_?[a-zA-Z]\w*)\s*\([^;{]*\)\s*async\s*\{');
    var seen = 0;
    final bad = <String>{};
    for (final e in files.entries) {
      for (final m in voidAsync.allMatches(e.value)) {
        seen++;
        final got = bodyAt(e.value, m.start);
        if (got == null) {
          throw StateError('اقتطاعُ جسمِ ${m.group(1)} في ${e.key} انهارَ');
        }
        if (!fullyWrapped(got.$2)) bad.add('${e.key}::${m.group(1)}');
      }
    }
    expect(seen, greaterThanOrEqualTo(15),
        reason: 'المسحُ انحلَّ — $seen عضواً `void async` فقط');
    expect(bad.difference(declared.keys.toSet()), isEmpty,
        reason: 'عضوٌ لا يُمكِنُ انتظارُه ويَرمي — الرميُ بلا مُعالِجٍ '
            'بالبناء، ويُسجَّلُ قاتلاً: ${bad.difference(declared.keys.toSet())}');
  });

  test('(ب) ونداءٌ مُسقَطٌ في موضعِ جملةٍ — المُنادى محروسٌ داخليّاً', () {
    final names = futureBodies.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    expect(names.length, greaterThanOrEqualTo(120),
        reason: 'لم تُجمَع أعضاءُ `Future` — فالفحصُ أجوف');
    final callRe = RegExp(
        r'(?<![\w.$])(' + names.map(RegExp.escape).join('|') + r')\s*\(');
    var dropped = 0;
    final bad = <String>{};
    for (final e in files.entries) {
      final s = e.value;
      for (final m in callRe.allMatches(s)) {
        // موضعُ جملةٍ: لا شيءَ بين آخرِ فاصلٍ وبين النداء.
        var start = 0;
        var sep = '';
        for (final ch in const [';', '{', '}', '=>', ',']) {
          final at = s.lastIndexOf(ch, m.start);
          if (at >= 0 && at + ch.length > start) {
            start = at + ch.length;
            sep = ch;
          }
        }
        if (s.substring(start, m.start).trim().isNotEmpty) continue;
        // و`=>` **تُعيدُ** المستقبَلَ لا تُسقِطُه — فجسمُ السهمِ يُحوّلُ
        // النداءَ إلى مُنادِيه. وهذا ما أعطى أوّلَ إبلاغٍ خاطئ:
        // `createDriverAccountViaAdmin(…) => createAccountViaAdmin(…)`.
        if (sep == '=>') continue;
        // والمستقبَلُ مُسقَطٌ: ما بعدَ الإغلاقِ فاصلُ جملةٍ لا `.`
        final after = s.substring(afterParens(s, m.start));
        if (!RegExp(r'^\s*;').hasMatch(after)) continue;
        dropped++;
        if (!memberWrapped(m.group(1)!, 0)) bad.add('${e.key}::${m.group(1)}');
      }
    }
    expect(dropped, greaterThanOrEqualTo(40),
        reason: 'المسحُ انحلَّ — $dropped نداءً مُسقَطاً فقط');
    expect(bad.difference(declared.keys.toSet()), isEmpty,
        reason: 'نداءٌ مُسقَطٌ لمُنادى يَرمي — فرميُه بلا مُعالِج: '
            '${bad.difference(declared.keys.toSet())}');
  });

  test('(ج) والحلُّ يَعملُ فعلاً — وإلّا كان الفحصُ أخضرَ بلا قراءة', () {
    // محروسٌ مباشرةً.
    expect(memberWrapped('_openExternalUrl', 0), isTrue,
        reason: 'الشكلُ المرجعيُّ (`try { ok = await launchUrl } catch`) '
            'لم يُقرَأْ محروساً — فالحلُّ معطوب');
    // ومحروسٌ **متعدٍّ**: يَنتظرُ عضواً محروساً.
    expect(fullyWrapped('{ await _openExternalUrl(u, failMessage: 1); }'),
        isTrue,
        reason: 'الحلُّ المتعدّي لا يَعمل — فالاستثناءاتُ كانت ستَتكاثر');
    expect(fullyWrapped('{ await ZyiarahZoneLocator.locate(z, lat: 1); }'),
        isTrue,
        reason: 'المُؤهِّلُ يَحجبُ اسمَ العضوِ — فلا يُحَلُّ شيء');
    // وغيرُ محروسٍ يُقرأُ كذلك: `launchUrl` حزمةٌ لا عضوٌ محروس.
    expect(fullyWrapped('{ await launchUrl(uri); }'), isFalse,
        reason: 'الكاشفُ لا يَرى `await` عارياً — فهو عقيم');
    expect(fullyWrapped('{ try { await launchUrl(uri); } catch (_) {} }'), isTrue);
    // والمسموحُ بالنوع.
    expect(fullyWrapped('{ await Future.delayed(const Duration(ms: 1)); }'),
        isTrue);
    expect(fullyWrapped('{ await _posSub?.cancel(); }'), isTrue);
    expect(fullyWrapped('{ await showDialog<bool>(context: c); }'), isTrue);
  });

  test('(د) وشواهدُ العِلاجِ الثلاثةُ قائمةٌ في موضعِها', () {
    final loc = stripComments(
        File('lib/services/location_service.dart').readAsStringSync());
    expect(loc.contains('location_permission_request_failed'), isTrue,
        reason: 'طلبُ الإذنِ بلا تقرير — «تعذّرَ السؤالُ» يَمضي بلا أثر');
    expect(RegExp(r'return false;').hasMatch(loc), isTrue,
        reason: 'تعذّرُ السؤالِ يَجبُ أن يُقرأَ «لم يُمنَح» — وهو ما يُشغّلُ '
            'الشريطَ وزرَّ الإعدادات');

    final drv = stripComments(
        File('lib/screens/driver_dashboard.dart').readAsStringSync());
    expect(drv.contains('driver_presence_read_failed'), isTrue,
        reason: 'قراءةُ حضورِ السائقِ تَرمي بلا أثر');

    final fb = stripComments(
        File('lib/services/firebase_service.dart').readAsStringSync());
    expect(fb.contains('sign_out_failed'), isTrue,
        reason: 'الخروجُ المركزيُّ يَرمي بلا أثر — وأربعةٌ من مُنادِيه '
            'يُسقِطونَ مستقبَلَه، ومنهم مسارا إقصاءٍ');
    final sIdx = fb.indexOf('_auth.signOut()');
    expect(sIdx, greaterThan(-1), reason: 'زالَ نداءُ الخروج');
    final tIdx = fb.lastIndexOf('try {', sIdx);
    expect(tIdx, greaterThan(-1), reason: 'نداءُ الخروجِ بلا try');
    expect(fb.substring(tIdx, sIdx).contains('}'), isFalse,
        reason: '`try` أقربُ منه كتلةٌ أخرى — النداءُ ما زال عارياً');

    final trk = stripComments(
        File('lib/screens/order_tracking_screen.dart').readAsStringSync());
    expect(RegExp(r'Future<void>\s+_callDriver').hasMatch(trk), isTrue,
        reason: '`void … async` لا يُمكِنُ انتظارُها بالبناء');
    expect(RegExp(r'_openExternal\s*\(').allMatches(trk).length,
        greaterThanOrEqualTo(3),
        reason: 'الزرّانِ لا يَمُرّانِ بمسارٍ واحدٍ محروس');
    // والمضادّة: شرحُ العطلِ ما زال في الخامّ (الحارسُ يَقرأُ المُجرَّد).
    final trkRaw = File('lib/screens/order_tracking_screen.dart').readAsStringSync();
    expect(trkRaw.contains('void … async'), isTrue,
        reason: 'زالَ شرحُ سببِ التحويلِ — فالقرارُ يُنقَضُ بلا علم');
  });

  test('(هـ) والاستثناءُ المُعلَنُ سببُه مقروءٌ لا مزاجيّ', () {
    final m = File('lib/main.dart').readAsStringSync();
    expect(m.contains('LicenseRegistry.addLicense'), isTrue,
        reason: 'زالَ الإغلاقُ الكسولُ الذي يُبرِّرُ استثناءَ `main`');
    expect(RegExp(r'addLicense\(\(\)\s*async\*').hasMatch(m), isTrue,
        reason: 'الإغلاقُ لم يَبقَ مُولِّداً كسولاً — فالاستثناءُ يُراجَع');
    expect(declared.length, 1,
        reason: 'استثناءٌ ثانٍ — يُقرأُ سببُه بدلَ أن يُضافَ بصمت');
  });
}
