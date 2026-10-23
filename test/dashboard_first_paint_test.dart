import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'helpers/strip_comments.dart';

/// لا قفزَ عند فتحِ الرئيسيّة (قرارُ المالك 2026-10-24): البطاقاتُ التي تَصِلُ
/// متأخّرةً (طلبٌ جارٍ، بانر، باقة) لا تَدفعُ الشبكةَ تحتَ الإصبع.
void main() {
  final code =
      stripComments(File('lib/screens/client_dashboard.dart').readAsStringSync());

  String body(String sig) {
    final i = code.indexOf(sig);
    expect(i, greaterThan(-1), reason: 'لم تُوجَد $sig');
    final open = code.indexOf('{', code.indexOf(')', i));
    var d = 0;
    for (var j = open; j < code.length; j++) {
      if (code[j] == '{') d++;
      if (code[j] == '}' && --d == 0) return code.substring(open, j + 1);
    }
    fail('جسمٌ غيرُ متوازن: $sig');
  }

  test('المحتوى خلفَ الشِمِرِّ حتى أوّلِ حدثٍ من البثوثِ الثلاثة', () {
    expect(code, contains('offstage: !_firstPaintReady'));
    expect(code, contains('if (!_firstPaintReady) _buildShimmerLoading()'));
    expect(code,
        contains("_firstSeen.containsAll(const ['active', 'banners', 'contracts'])"));
  });

  test('كلُّ بطاقةٍ متأخّرةٍ تُبلِغُ أوّلَ حدثٍ أو خطأ', () {
    for (final e in {
      'Widget _buildActiveTrackingCard(': 'active',
      'Widget _buildPromoBanners(': 'banners',
      'Widget _buildSubscriptionCards(': 'contracts',
    }.entries) {
      final b = body(e.key);
      expect(b,
          contains("if (snapshot.connectionState != ConnectionState.waiting) _markFirstSeen('${e.value}')"),
          reason: e.key);
    }
  });

  test('سقفٌ قصيرٌ يَكشفُ المحتوى ولا يَحجبُه خلفَ بثٍّ بطيء', () {
    expect(code, contains('kFirstPaintCap = Duration(seconds: 3)'));
    expect(code, contains('_firstPaintForced = true'));
    expect(body('void dispose('), contains('_firstPaintCap?.cancel()'));
  });
}
