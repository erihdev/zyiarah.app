import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// (قرار المالك 2026-07-18) لوحة السائق: أبسط وأذكى، بلا مفتاح اتصال/فصل
/// (متصل دائماً تصله الطلبات والإشعارات)، والمهام مرتّبة بمصدر واحد بلا تكرار.
String _strip(String src) {
  src = src.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
  return src.split('\n').map((l) {
    final i = l.indexOf('//');
    return i >= 0 ? l.substring(0, i) : l;
  }).join('\n');
}

void main() {
  final raw = File('lib/screens/driver_dashboard.dart').readAsStringSync();
  final code = _strip(raw);

  test('مفتاح الاتصال/الفصل محذوف من الجذور — السائق متصل دائماً', () {
    expect(code.contains('Switch('), isFalse,
        reason: 'مفتاح الاتصال يوقف السائق بالخطأ فتتوقّف عنه الطلبات');
    expect(code.contains('_isOnline'), isFalse,
        reason: 'أي أثر لحالة الاتصال المحلية يعيد المنطق المحذوف');
    expect(code.contains('أوفلاين'), isFalse);
    // مؤشّر «متصل» الثابت يبقى للطمأنة فقط.
    expect(raw.contains("'متصل'"), isTrue);
  });

  test('الضمان الخادمي: متاح دائماً كي تصله الطلبات والإشعارات', () {
    expect(code.contains('_ensureAlwaysAvailable'), isTrue);
    expect(code.contains("'is_available': true"), isTrue,
        reason: 'بلا كتابة التوفّر قد يبقى سائق قديم off فلا تصله مهام');
  });

  test('مصدر واحد للمهام: الحالية بالأعلى ثم القادمة بلا تكرار', () {
    // كان جدولٌ كامل + بطاقة نشطة منفصلة يعرضان المهمة نفسها مرتين.
    expect(code.contains('_buildUpcomingSchedule'), isFalse,
        reason: 'الجدول القديم بتياره المستقل يعيد ازدواج المهمة الحالية');
    expect(code.contains('_buildUpcomingList'), isTrue);
    expect(code.contains('_buildActivePipeline(focus)'), isTrue,
        reason: 'المهمة محل التركيز تُعرض من نفس المصدر المُصفّى');
    // القادمة تستبعد المهمة الحالية صراحةً.
    expect(code.contains('active.where((d) => d.id != focus.id)'), isTrue,
        reason: 'بلا الاستبعاد تظهر المهمة الحالية في القائمتين معاً');
  });

  test('تسلسل واجهة الرئيسية: المهام أولاً ثم الإحصاءات', () {
    final main = code.indexOf('_buildMainSection(),');
    final stats = code.indexOf('_buildStatsRow(),');
    expect(main, greaterThan(-1));
    expect(stats, greaterThan(-1));
    expect(main < stats, isTrue,
        reason: 'استقبال الطلبات يجب أن يتصدّر الشاشة لا الإحصاءات');
  });
}
