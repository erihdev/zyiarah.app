// بطاقةُ التركيزِ عند السائقِ وترتيبُها، و«متأخرة»، وتأكيدُ الخروجِ الواحد —
// إصلاحاتُ 2026-10-11.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:zyiarah/models/driver_schedule.dart';
import 'package:zyiarah/screens/driver_tasks_screen.dart';

import 'helpers/strip_comments.dart';

DriverTask _t(String id, DateTime when,
        {String status = 'scheduled', String? slot, String? code}) =>
    DriverTask(
      id: id,
      code: code ?? id,
      serviceName: 'خدمة $id',
      clientName: 'c',
      zoneName: 'z',
      status: status,
      when: when,
      timeSlot: slot,
    );

String _dash() =>
    stripComments(File('lib/screens/driver_dashboard.dart').readAsStringSync());

void main() {
  group('ترتيبُ بطاقةِ التركيزِ حتميّ', () {
    final day = DateTime(2026, 10, 11);
    test('الأولويّةُ أوّلاً: الجاريةُ قبلَ المجدولة', () {
      final list = [
        _t('a', day, slot: '08:00'),
        _t('b', day, slot: '15:00', status: 'in_progress'),
      ]..sort(DriverSchedule.focusCompare);
      expect(list.first.id, 'b');
    });
    test('تساوي الأولويّة: الموعدُ الأقربُ أوّلاً', () {
      final list = [
        _t('late', day.add(const Duration(days: 1))),
        _t('early', day),
      ]..sort(DriverSchedule.focusCompare);
      expect(list.first.id, 'early');
    });
    test('تساوي الموعد: الرمزُ ثمّ المعرّف — أيّاً كان ترتيبُ الوصول', () {
      final a = _t('x2', day, slot: '10:00', code: 'ZY-102');
      final b = _t('x1', day, slot: '10:00', code: 'ZY-101');
      final c = _t('x0', day, slot: '10:00', code: 'ZY-101');
      for (final input in [
        [a, b, c],
        [c, b, a],
        [b, a, c],
      ]) {
        final sorted = [...input]..sort(DriverSchedule.focusCompare);
        expect(sorted.map((t) => t.id).toList(), ['x0', 'x1', 'x2']);
      }
    });
    test('الرئيسيّةُ تُرتّبُ بالقاعدةِ لا بالأولويّةِ وحدَها', () {
      final dash = _dash();
      expect(dash, contains('DriverSchedule.focusCompare('));
      expect(dash, isNot(contains('_focusRank(')),
          reason: 'عادَ الترتيبُ بالأولويّةِ وحدَها');
    });
  });

  group('المتأخّرة: فات موعدُها ولم تبدأ', () {
    final now = DateTime(2026, 10, 11, 14, 0);
    test('مجدولةٌ فات وقتُها ⇒ متأخّرة؛ قبلَ وقتِها ⇒ لا', () {
      expect(_t('a', DateTime(2026, 10, 11), slot: '09:00').isOverdue(now),
          isTrue);
      expect(_t('b', DateTime(2026, 10, 11), slot: '16:00').isOverdue(now),
          isFalse);
      expect(_t('c', DateTime(2026, 10, 10)).isOverdue(now), isTrue,
          reason: 'أمسُ بلا ساعة');
      expect(_t('d', DateTime(2026, 10, 11)).isOverdue(now), isFalse,
          reason: 'اليومُ بلا ساعةٍ لا يَتأخّرُ قبلَ انتهاءِ اليوم');
    });
    test('الجاريةُ والمنتهيةُ ليست «متأخّرة»', () {
      final past = DateTime(2026, 10, 10);
      for (final st in [
        'in_progress',
        'on_the_way',
        'accepted',
        'completed',
        'cancelled'
      ]) {
        expect(_t('x', past, status: st).isOverdue(now), isFalse, reason: st);
      }
      expect(_t('y', past, status: 'assigned').isOverdue(now), isTrue);
    });
    test('ساعةٌ بلاحقةِ «م» تُقرأُ مساءً', () {
      expect(_t('a', DateTime(2026, 10, 11), slot: '1:00 م').isOverdue(now),
          isTrue);
      expect(_t('b', DateTime(2026, 10, 11), slot: '3:00 م').isOverdue(now),
          isFalse);
    });

    testWidgets('بطاقةُ «مهامي» تقول «متأخرة» لا «قادمة»', (tester) async {
      GoogleFonts.config.allowRuntimeFetching = false;
      await tester.pumpWidget(MaterialApp(
        home: DriverTasksScreen(
          items: Stream.value([
            _t('late', DateTime(2026, 10, 11), slot: '09:00'),
            _t('soon', DateTime(2026, 10, 11), slot: '18:00'),
          ]),
          uid: 'd1',
          now: now,
        ),
      ));
      await tester.pump();
      await tester.pump();
      expect(find.text('متأخرة — فات موعدها'), findsOneWidget);
      expect(find.text('قادمة ⏳'), findsOneWidget);
    });

    test('الرئيسيّةُ تُسمّي المتأخّرةَ في البطاقتَين', () {
      final dash = _dash();
      expect('.isOverdue('.allMatches(dash).length, greaterThanOrEqualTo(2));
      expect(dash, contains("'متأخرة — فات موعدها'"));
      expect(dash, contains('مهمة متأخرة — فات موعدها'));
    });
  });

  test('الخروجُ بتأكيدٍ واحد: الرئيسيّةُ لا تَسألُ بعدَ «حسابي»', () {
    final dash = _dash();
    final i = dash.indexOf('Future<void> _performLogout()');
    expect(i, greaterThan(0));
    final body = dash.substring(i, dash.indexOf('\n  }\n', i));
    expect(body, isNot(contains('showDialog')),
        reason: 'عادت نافذةُ تأكيدٍ ثانية بعدَ تأكيدِ شاشةِ «حسابي»');
    final profile = stripComments(
        File('lib/screens/driver_profile_screen.dart').readAsStringSync());
    expect(profile, contains('showDialog<bool>'),
        reason: 'زالَ التأكيدُ الوحيد — فالخروجُ صارَ بلا سؤالٍ أصلاً');
    expect(dash, contains('DriverProfileScreen(onLogout: _performLogout)'));
  });
}
