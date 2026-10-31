// نقلُ العاملاتِ عبر مواصلات — جهةُ التطبيق.
//
// ═══ ما يحرسه ═══
//
// (أ) `TransportLegView`: قراءةُ ما يَكتبُه الخادمُ على الطلبِ بلا Firebase —
//     ولا حرفَ لاتينيّاً خامّاً في واجهةٍ عربيّة.
// (ب) مرآةُ الحالاتِ: مجموعتا الحيِّ والنهائيِّ هنا تُساويانِ ما في
//     `functions/transport.js` حرفاً — تُقرأُ من الملفِّ لا تُكتَبُ ثانيةً.
// (ج) `transportSettingsPayload`: الفراغُ قرارٌ وخطأُ الكتابةِ ليس قراراً،
//     والمفاتيحُ المكتوبةُ **مجموعةً كاملةً** تُساوي ما يَقرؤه الخادمُ
//     (`normalizeConfig`) — نمطُ «قرارٌ يُقرأُ بافتراضٍ صامتٍ ويَعرفُه محرِّرٌ
//     واحد» المسجَّلُ في CLAUDE.md أربعَ مرّات.
// (د) الربطُ: شاشةُ الإدارةِ تُنادي `retryTransportRide` وتَعرضُ البطاقة،
//     وشاشةُ العاملةِ تَعرضُ السيارة، وشاشةُ الإعداداتِ تَكتبُ المستندَ عبرَ
//     البوّابةِ لا بيدِها.

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/utils/transport_ride.dart';
import 'package:zyiarah/utils/transport_settings.dart';

String _read(String p) => File(p).readAsStringSync();

/// مجموعةٌ من ثابتٍ جافاسكربتيٍّ `Object.freeze(["a", "b"])` في الخادم.
Set<String> _jsSet(String src, String name) {
  final m = RegExp('const $name = Object\\.freeze\\(\\[([^\\]]*)\\]\\)')
      .firstMatch(src);
  expect(m, isNotNull, reason: '$name غير موجود في transport.js');
  return RegExp(r'"(\w+)"')
      .allMatches(m!.group(1)!)
      .map((x) => x.group(1)!)
      .toSet();
}

void main() {
  group('TransportLegView', () {
    test('يَقرأُ ساقاً كاملةً، ويَرُدُّ null لما لم يُطلَب', () {
      final order = {
        'transport': {
          'outbound': {
            'state': 'accepted',
            'gen': 2,
            'driver': {'name': 'سالم', 'phone': '0509', 'plate': 'أ ب ج 123'},
            'pickup_at': Timestamp.fromMillisecondsSinceEpoch(1700000000000),
            'eta_minutes': 7,
          },
        },
      };
      final v = TransportLegView.fromOrder(order, 'outbound')!;
      expect(v.state, 'accepted');
      expect(v.isLive, isTrue);
      expect(v.isFinal, isFalse);
      expect(v.canRetry, isFalse);
      expect(v.driverLine, 'سالم — أ ب ج 123');
      expect(v.driverPhone, '0509');
      expect(v.etaMinutes, 7);
      expect(v.pickupAt, isNotNull);
      expect(v.legLabel, 'الذهاب');
      expect(TransportLegView.fromOrder(order, 'return'), isNull);
      expect(TransportLegView.fromOrder({}, 'outbound'), isNull);
      expect(
          TransportLegView.fromOrder({'transport': 'x'}, 'outbound'), isNull);
    });

    test('الفشلُ والإلغاءُ وحدَهما يُجيزانِ الإعادة، والمكتملُ نهائيّ', () {
      TransportLegView of(String st) => TransportLegView.fromOrder({
            'transport': {
              'return': {
                'state': st,
                'error': st == 'failed' ? 'HTTP 503' : ''
              },
            },
          }, 'return')!;
      expect(of('failed').canRetry, isTrue);
      expect(of('failed').error, 'HTTP 503');
      expect(of('cancelled').canRetry, isTrue);
      expect(of('completed').canRetry, isFalse);
      expect(of('completed').isFinal, isTrue);
      expect(of('requested').canRetry, isFalse);
      expect(of('cancelled').error, isNull, reason: 'الفراغُ ليس خطأً');
    });

    test('كلُّ حالةٍ يَعرفُها الخادمُ لها تسميةٌ عربيّةٌ لا لاتينيّة', () {
      final server = _read('functions/transport.js');
      final all = {
        ..._jsSet(server, 'LIVE_STATES'),
        ..._jsSet(server, 'FINAL_STATES')
      };
      for (final st in all) {
        final label = transportStateLabel(st);
        expect(label, isNot('غير معروفة'), reason: 'حالةُ $st بلا تسمية');
        expect(RegExp(r'[A-Za-z]').hasMatch(label), isFalse,
            reason: 'تسميةُ $st تَحملُ حروفاً لاتينيّة');
      }
      expect(transportStateLabel('teleported'), 'غير معروفة');
    });
  });

  group('مرآةُ الحالاتِ مع الخادم', () {
    test('kTransportLiveStates/kTransportFinalStates تُساويانِ transport.js',
        () {
      final server = _read('functions/transport.js');
      expect(kTransportLiveStates, _jsSet(server, 'LIVE_STATES'));
      expect(kTransportFinalStates, _jsSet(server, 'FINAL_STATES'));
    });

    test('المهلةُ الافتراضيّةُ تُطابقُ الخادم', () {
      final server = _read('functions/transport.js');
      final m =
          RegExp(r'const DEFAULT_LEAD_MINUTES = (\d+);').firstMatch(server);
      expect(int.parse(m!.group(1)!), kTransportDefaultLeadMinutes);
    });
  });

  group('transportSettingsPayload', () {
    TransportSettingsResult build({
      bool enabled = true,
      String provider = 'mowasalat',
      String lat = '17.15',
      String lng = '42.62',
      String label = 'المقرّ',
      String lead = '45',
      String url = 'https://api.example',
    }) =>
        transportSettingsPayload(
          enabled: enabled,
          provider: provider,
          lat: lat,
          lng: lng,
          label: label,
          leadMinutes: lead,
          baseUrl: url,
        );

    test('مستندٌ صالحٌ كاملُ المفاتيح، والأرقامُ العربيّةُ تُقبَل', () {
      final r = build(lat: '١٧٫١٥', lng: '٤٢٫٦٢', lead: '٣٠');
      expect(r.ok, isTrue, reason: r.error);
      final p = r.payload!;
      expect((p['hq_location'] as GeoPoint).latitude, 17.15);
      expect((p['hq_location'] as GeoPoint).longitude, 42.62);
      expect(p['lead_minutes'], 30);
      expect(p['provider'], 'mowasalat');
      expect(p['enabled'], isTrue);
    });

    test('الفراغُ قرار: مهلةٌ فارغةٌ = الافتراضيّ، واسمٌ فارغٌ = «مقر المؤسسة»',
        () {
      final r = build(lead: '', label: '  ');
      expect(r.ok, isTrue, reason: r.error);
      expect(r.payload!['lead_minutes'], kTransportDefaultLeadMinutes);
      expect(r.payload!['hq_label'], 'مقر المؤسسة');
    });

    test(
        'خطأُ الكتابةِ ليس قراراً: إحداثيٌّ أو مهلةٌ لا تَنحلُّ تُرفَضُ باسمِها',
        () {
      expect(build(lat: 'abc').error, contains('خط عرض'));
      expect(build(lng: '200').error, contains('خط طول'));
      expect(build(lat: '', lng: '42').error, contains('خط عرض'),
          reason: 'إحداثيٌّ واحدٌ بلا الآخر ليس مقرّاً');
      expect(build(lead: 'x').error, contains('مهلة'));
      expect(build(lead: '0').error, contains('مهلة'));
      expect(build(provider: 'uber').error, contains('مزوّد'));
    });

    test('التفعيلُ يَشترطُ مقرّاً، ومواصلات يَشترطُ عنوان https', () {
      expect(build(lat: '', lng: '').error, contains('موقع المقرّ'));
      final off = build(enabled: false, lat: '', lng: '', url: '');
      expect(off.ok, isTrue, reason: off.error);
      expect(off.payload!['hq_location'], isNull);
      expect(build(url: '').error, contains('https'));
      expect(build(url: 'http://x').error, contains('https'));
      final sim = build(provider: 'simulator', url: '');
      expect(sim.ok, isTrue, reason: sim.error);
    });

    test('المفاتيحُ المكتوبةُ مجموعةً كاملةً = ما يَقرؤه الخادم', () {
      final written = build().payload!.keys.toSet();
      final server = _read('functions/transport.js');
      final i = server.indexOf('function normalizeConfig(');
      final j = server.indexOf('\n}', i);
      final body = server.substring(i, j);
      final read = RegExp(r'\bd\.(\w+)')
          .allMatches(body)
          .map((m) => m.group(1)!)
          .toSet();
      expect(written, read,
          reason:
              'محرِّرُ الإعداداتِ والخادمُ اختلفا على مفاتيحِ system_configs/transport');
    });
  });

  group('الربط', () {
    test(
        'شاشةُ الإدارةِ تَعرضُ البطاقةَ وتُنادي retryTransportRide على الفشلِ وحدَه',
        () {
      final src = _read('lib/screens/admin/admin_order_details_screen.dart');
      expect(src, contains("httpsCallable('retryTransportRide')"));
      expect(src, contains('_buildTransportCard(data)'));
      expect(src, contains("if (data['transport'] is Map)"));
      expect(src, contains('if (leg.canRetry && _canEditOrders)'),
          reason:
              'زرُّ الإعادةِ على رحلةٍ حيّةٍ يُلغيها — يُعرَضُ للفشلِ والإلغاءِ فقط');
      // الحالةُ تُعرَضُ بتسميتِها العربيّةِ لا بالحقلِ الخامّ.
      expect(src, contains('leg.stateLabel'));
    });

    test('شاشةُ العاملةِ تَعرضُ سيارةَ الذهابِ ثمّ العودةِ بعدَ الإنجاز', () {
      final src = _read('lib/screens/driver_dashboard.dart');
      expect(src, contains('_buildTransportAlert(data, status)'));
      expect(src, contains("status == 'completed' ? 'return' : 'outbound'"));
    });

    test('شاشةُ الإعداداتِ تَكتبُ المستندَ عبرَ البوّابةِ لا بيدِها', () {
      final src = _read('lib/screens/admin/admin_settings_screen.dart');
      expect(src, contains('transportSettingsPayload('));
      expect(src, contains("doc('transport')"));
      // لا مفتاحَ من مفاتيحِ المستندِ مكتوباً بيدٍ في الشاشة (يُقرأُ فقط).
      expect(RegExp(r"'hq_location':\s").hasMatch(src), isFalse,
          reason: 'كتابةٌ يدويّةٌ لمفتاحِ النقلِ خارجَ البوّابة');
    });

    test(
        'المستندُ لا يَحملُ سرّاً: لا مفتاحَ واجهةٍ في الشاشةِ ولا في البوّابة',
        () {
      for (final f in [
        'lib/screens/admin/admin_settings_screen.dart',
        'lib/utils/transport_settings.dart',
      ]) {
        final src = _read(f);
        expect(RegExp(r"'api_key'|apiKey").hasMatch(src), isFalse,
            reason: '$f يَكتبُ مفتاحاً سرّيّاً في مستندٍ مقروءٍ لكلِّ مسجَّل');
      }
    });
  });
}
