// حارس: **زرُّ «تتبع السائق» لا يظهر إلّا والتتبّعُ ممكنٌ فعلاً.**
//
// وُجد بتشغيل التطبيق بحسابٍ حقيقيّ (2026-10-04): أربعُ زياراتِ اشتراكٍ مواعيدُها
// في **يوليو** تحت «الطلبات النشطة» بحالة «مجدول»، كلٌّ منها يعرض «تتبع السائق»
// والبطاقةُ فوقه تقول «انتهى الموعد». وضغطُه يردّ «لم يُعيَّن سائق بعد، يُرجى
// الانتظار» — لزيارةٍ فات موعدُها بثلاثة أشهر.
//
// والعطلُ **عولج مرّةً وبقي**: تعليقُ الشاشة يسجّل «كان زرّ تتبع السائق يظهر
// ويقول لم يُعيَّن سائق بعد للأبد»، لكنّ العلاج كُتب **تعداداً لحالتين**
// (`under_review`، و`in_progress` بلا سائق) بدل أن يُكتب قاعدةً — فبقيت
// `scheduled` بلا سائق خارجه. ولهذا يختبر هذا الملفّ **القاعدة** لا الحالات.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/utils/order_tracking.dart';

void main() {
  group('canTrackOrder — سائقٌ وموقعٌ، لا حالةُ الطلب', () {
    test('يحتاج الاثنين معاً', () {
      expect(canTrackOrder({'driver_id': 'd1', 'location': {'lat': 1}}), isTrue);
      expect(canTrackOrder({'driver_id': 'd1'}), isFalse);
      expect(canTrackOrder({'location': {'lat': 1}}), isFalse);
      expect(canTrackOrder({}), isFalse);
      expect(canTrackOrder({'driver_id': null, 'location': null}), isFalse);
    });

    test('لا يلتفت إلى الحالة — وهذا بيتُ القصيد', () {
      // الزياراتُ التي رأيتُها كانت `scheduled` بلا سائق: خارج التعداد القديم.
      for (final st in ['pending', 'scheduled', 'assigned', 'accepted',
        'on_the_way', 'in_progress', 'under_review', 'completed']) {
        expect(canTrackOrder({'status': st}), isFalse,
            reason: '$st بلا سائق يجب ألّا يُتتبَّع');
        expect(
            canTrackOrder({'status': st, 'driver_id': 'd', 'location': {}}),
            isTrue,
            reason: '$st بسائقٍ وموقع يُتتبَّع');
      }
    });
  });

  group('orderAppointment', () {
    test('service_date يتقدّم booking_date', () {
      final sd = DateTime(2026, 7, 18, 6);
      expect(
          orderAppointment(
              serviceDate: sd, bookingDate: '2026-09-01', bookingTimeSlot: '10:00'),
          sd);
    });

    test('booking_date + slot حين لا service_date', () {
      expect(orderAppointment(bookingDate: '2026-07-18', bookingTimeSlot: '06:00'),
          DateTime(2026, 7, 18, 6));
    });

    test('slot غيرُ صالح ⇒ منتصف الليل لا انهيار', () {
      expect(orderAppointment(bookingDate: '2026-07-18', bookingTimeSlot: '6'),
          DateTime(2026, 7, 18));
      expect(orderAppointment(bookingDate: '2026-07-18'),
          DateTime(2026, 7, 18));
    });

    test('بلا موعد ⇒ null، وتاريخٌ تالف ⇒ null لا استثناء', () {
      expect(orderAppointment(), isNull);
      expect(orderAppointment(bookingDate: ''), isNull);
      expect(orderAppointment(bookingDate: 'ليس تاريخاً'), isNull);
    });
  });

  group('appointmentPassed — بدقّة اليوم', () {
    final now = DateTime(2026, 10, 4, 14, 30);

    test('موعدُ يوليو فائت (الحالة التي شوهدت)', () {
      expect(appointmentPassed(DateTime(2026, 7, 18, 6), now), isTrue);
    });

    test('موعدُ اليوم ليس فائتاً ولو مضت ساعتُه', () {
      // الكادرُ قد يكون في الطريق؛ «فات» بالدقيقة يُخفي زيارةً قائمة.
      expect(appointmentPassed(DateTime(2026, 10, 4, 8), now), isFalse);
      expect(appointmentPassed(DateTime(2026, 10, 4, 23, 59), now), isFalse);
    });

    test('أمسِ فائت، وغداً ليس فائتاً، وبلا موعدٍ ليس فائتاً', () {
      expect(appointmentPassed(DateTime(2026, 10, 3, 23, 59), now), isTrue);
      expect(appointmentPassed(DateTime(2026, 10, 5), now), isFalse);
      expect(appointmentPassed(null, now), isFalse);
    });
  });

  group('trackingUnavailableLabel — كلُّ حالةٍ تقول سببَها', () {
    test('المراجعة والتنفيذ يحتفظان بنصّيهما', () {
      expect(trackingUnavailableLabel(status: 'under_review', passed: false),
          'تحت المراجعة — تصلك الإشعارات');
      expect(trackingUnavailableLabel(status: 'in_progress', passed: false),
          'جاري التنفيذ');
    });

    test('فات الموعد بلا سائق ⇒ لا يُقال لها «انتظري»', () {
      final t = trackingUnavailableLabel(status: 'scheduled', passed: true);
      expect(t.contains('انتهى الموعد'), isTrue);
      expect(t.contains('انتظ'), isFalse,
          reason: 'لم يعد هناك ما يُنتظر — هذه كانت الكذبة بعينها');
    });

    test('لم يفت الموعد ⇒ «لم يُعيَّن سائق بعد» وهي صادقة حينها', () {
      expect(trackingUnavailableLabel(status: 'scheduled', passed: false),
          'لم يُعيَّن سائق بعد');
    });
  });

  group('الشاشة تستعمل القاعدة ولا تُعيد تعداد الحالات', () {
    final src = File('lib/screens/orders_list_screen.dart').readAsStringSync();

    test('شرطُ ظهور الزرّ هو canTrackOrder', () {
      expect(src.contains('else if (!canTrackOrder(order))'), isTrue,
          reason: 'عودةُ التعداد تُعيد العطل في الحالة التي يغفلها');
    });

    test('لا تعدادَ حالاتٍ يقرّر التتبّع', () {
      expect(src.contains("status == 'under_review' ||"), isFalse,
          reason: 'التعدادُ القديم عاد — القرار قاعدةٌ لا قائمة');
    });

    test('الضغطةُ لم تعد تحرس نفسها — الحارسُ في الظهور', () {
      expect(src.contains('لم يُعيَّن سائق بعد، يُرجى الانتظار'), isFalse,
          reason: 'هذه الرسالةُ كانت تعني زرّاً ظهر وما كان ينبغي');
    });

    test('المُحلِّل واحدٌ للبطاقة والشارة', () {
      // قراءتان للموعد قد تختلفان، فتقول البطاقةُ «انتهى» ويقول الزرُّ غيرَه.
      expect('orderAppointment('.allMatches(src).length, greaterThanOrEqualTo(2));
      expect(src.contains("DateTime.parse('\${order['booking_date']}"), isFalse,
          reason: 'عاد تحليلُ الموعد يدويّاً داخل الشاشة');
    });
  });
}
