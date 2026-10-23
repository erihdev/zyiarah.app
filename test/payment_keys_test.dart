import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/utils/payment_keys.dart';

import 'helpers/sources_in.dart';
import 'helpers/strip_comments.dart';

/// مفتاحُ ميسر القابلُ للنشرِ مضمَّنٌ في الشفرة (قرارُ المالك 2026-10-24).
void main() {
  test('المضمَّنُ مفتاحٌ قابلٌ للنشر — لا سرّيٌّ أبداً', () {
    expect(kMoyasarPublishableKey, startsWith('pk_'));
    expect(kMoyasarPublishableKey, isNot(contains('sk_')));
  });

  test('بلا .env يَرجعُ المضمَّن — فلا بناءَ بلا بطاقة', () {
    expect(moyasarPublishableKey(), kMoyasarPublishableKey);
  });

  test('لا مفتاحَ سرّيٌّ لميسر في lib/ ولا قراءةَ للمفتاحِ خارجَ موضعِه', () {
    final offenders = <String>[];
    for (final f in sourcesIn('lib', atLeast: 100)) {
      final raw = File(f.path).readAsStringSync();
      if (RegExp(r'sk_(live|test)_[A-Za-z0-9]').hasMatch(raw)) {
        offenders.add('${f.path}: sk_');
      }
      if (f.path.endsWith('payment_keys.dart')) continue;
      if (stripComments(raw).contains("'MOYASAR_PUBLISHABLE_KEY'")) {
        offenders.add('${f.path}: قراءةٌ مباشرة');
      }
    }
    expect(offenders, isEmpty);
  });
}
