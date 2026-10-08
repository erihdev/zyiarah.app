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
//
// ثمّ تبيّن أنّ القاعدةَ نفسَها كانت ناقصة: «سائقٌ وموقع» وحدَهما. فالزياراتُ
// الأربعُ ذاتُها — ولها سائقٌ وموقع — عادت تعرض الزرَّ في تشغيلٍ حيٍّ لاحقٍ
// في اليوم نفسه. شرطُ «ولم يفُت الموعد» هو ما كان ناقصاً، ومعه استثناءُ
// الجاري الآن (`on_the_way`/`in_progress`) كي لا تُخفى الخريطةُ عن سائقٍ
// يعمل بعد منتصف الليل.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/utils/order_tracking.dart';

void main() {
  // **العلاجُ الأوّل كان ناقصاً، وهذا الملفُّ كان يثبّت نقصَه.** الحارسُ الأوّل
  // قال «أيُّ حالةٍ بسائقٍ وموقعٍ تُتتبَّع» — فمرّ أخضرَ على الزياراتِ ذاتِها
  // حين ظهرت ثانيةً في تشغيلٍ حيّ لاحقٍ في اليوم نفسه: لها سائقٌ وموقع،
  // فالزرُّ يظهر، والبطاقةُ فوقه تقول «انتهى الموعد». أُعيد توجيهُ الفحوص إلى
  // القاعدة الكاملة — سائقٌ وموقعٌ **ولم يفُت الموعد** — لا إلى نصفها.
  group('canTrackOrder — سائقٌ وموقعٌ ولم يفُت الموعد', () {
    test('يحتاج السائقَ والموقعَ معاً', () {
      expect(
          canTrackOrder({'driver_id': 'd1', 'location': {'lat': 1}},
              passed: false),
          isTrue);
      expect(canTrackOrder({'driver_id': 'd1'}, passed: false), isFalse);
      expect(canTrackOrder({'location': {'lat': 1}}, passed: false), isFalse);
      expect(canTrackOrder({}, passed: false), isFalse);
      expect(canTrackOrder({'driver_id': null, 'location': null}, passed: false),
          isFalse);
    });

    test('بلا سائقٍ لا تتبّعَ مهما كانت الحالة', () {
      for (final st in [
        'pending', 'scheduled', 'assigned', 'accepted',
        'on_the_way', 'in_progress', 'under_review', 'completed',
      ]) {
        expect(canTrackOrder({'status': st}, passed: false), isFalse,
            reason: '$st بلا سائق يجب ألّا يُتتبَّع');
      }
    });

    test('موعدٌ قائم: أيُّ حالةٍ بسائقٍ وموقع تُتتبَّع', () {
      for (final st in [
        'pending', 'scheduled', 'assigned', 'accepted',
        'on_the_way', 'in_progress', 'under_review', 'completed',
      ]) {
        expect(
            canTrackOrder({'status': st, 'driver_id': 'd', 'location': {}},
                passed: false),
            isTrue,
            reason: '$st بسائقٍ وموقعٍ وموعدٍ قائم يُتتبَّع');
      }
    });

    test('فات الموعد: لا تتبّعَ ولو كان السائقُ مُسنَداً', () {
      // هذه هي الحالةُ التي رُئيت حيّةً: زيارةُ اشتراكٍ في يوليو، حالتُها
      // `scheduled`، لها سائقٌ وموقع — وزرُّ تتبّعٍ في أكتوبر.
      for (final st in ['pending', 'scheduled', 'assigned', 'accepted',
        'under_review', 'completed']) {
        expect(
            canTrackOrder({'status': st, 'driver_id': 'd', 'location': {}},
                passed: true),
            isFalse,
            reason: '$st بعد فوات الموعد: الزرُّ وعدٌ كاذب');
      }
    });

    test('الجاري الآن يُستثنى — ولولاه لأُخفيت الخريطةُ عن سائقٍ في الطريق', () {
      // عملٌ يبدأ 23:00 ويمتدّ بعد منتصف الليل: الموعدُ «فات» بدقّة اليوم
      // بينما الكادرُ يعمل. استثناءُ الحالتين هو ما يمنع هذا الانقلاب.
      for (final st in kTrackableAfterAppointment) {
        expect(
            canTrackOrder({'status': st, 'driver_id': 'd', 'location': {}},
                passed: true),
            isTrue,
            reason: '$st بعد منتصف الليل ما زال جارياً');
      }
      expect(kTrackableAfterAppointment, {'on_the_way', 'in_progress'});
    });

    test('الاستثناءُ لا يُنقذ طلباً بلا سائق', () {
      for (final st in kTrackableAfterAppointment) {
        expect(canTrackOrder({'status': st}, passed: true), isFalse);
      }
    });
  });

  group('orderAppointment', () {
    test('حقلا الحجزِ يَتقدّمانِ `service_date` — التسميةُ التي اختارَها البشر',
        () {
      // **كانت الأسبقيّةُ معكوسةً، وأُعيد توجيهُ هذا الفحصِ بوعيٍ لا إسكاتاً.**
      // حقلا الحجزِ ساعةُ حائطٍ من مكوّناتِ ما اختارَه الإنسانُ، فمستقلّانِ عن
      // منطقةِ الجهاز؛ و`service_date` لحظةٌ تُعرَضُ بمنطقةِ قارئها. فعلى
      // جهازٍ خارجَ +03 كانت البطاقةُ تُظهرُ ساعةً لم تَختَرْها العميلةُ —
      // وساعاتُ جدولِ المنطقةِ ساعاتُ الرياض.
      final sd = DateTime(2026, 7, 18, 6);
      expect(
          orderAppointment(
              serviceDate: sd, bookingDate: '2026-09-01', bookingTimeSlot: '10:00'),
          DateTime(2026, 9, 1, 10));
      // وطلبٌ كُتبَ داخلَ السعوديّةِ يَحملُ التمثيلَين متّفقَين: لا تغيُّر.
      expect(
          orderAppointment(
              serviceDate: DateTime(2026, 7, 18, 6),
              bookingDate: '2026-07-18',
              bookingTimeSlot: '06:00'),
          DateTime(2026, 7, 18, 6));
    });

    test('`service_date` احتياطٌ: بلا حقلَي حجزٍ، أو بتاريخٍ تالف', () {
      final sd = DateTime(2026, 7, 18, 6);
      // خدمةٌ لا تَكتبُ حقلَي الحجزِ (بلا موعدٍ مُجدوَل) — اللحظةُ هي ما يوجد.
      expect(orderAppointment(serviceDate: sd), sd);
      // وتاريخٌ تالفٌ لا يُخفي الشارةَ كلَّها متى وُجدت لحظةٌ سليمة.
      expect(orderAppointment(serviceDate: sd, bookingDate: 'ليس تاريخاً'), sd);
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

    test('شرطُ ظهور الزرّ هو canTrackOrder بشِقَّيه', () {
      expect(
          src.contains(
              'else if (!canTrackOrder(order, passed: _apptPassed(order)))'),
          isTrue,
          reason: 'عودةُ التعداد — أو إسقاطُ شرطِ الموعد — تُعيد العطل');
    });

    test('لا تعدادَ حالاتٍ يقرّر التتبّع', () {
      expect(src.contains("status == 'under_review' ||"), isFalse,
          reason: 'التعدادُ القديم عاد — القرار قاعدةٌ لا قائمة');
    });

    test('الضغطةُ لم تعد تحرس نفسها — الحارسُ في الظهور', () {
      expect(src.contains('لم يُعيَّن سائق بعد، يُرجى الانتظار'), isFalse,
          reason: 'هذه الرسالةُ كانت تعني زرّاً ظهر وما كان ينبغي');
    });

    test('قراءةُ الموعد واحدةٌ للزرّ وللشارة', () {
      // قراءتان للموعد قد تختلفان، فيختفي الزرُّ وتقول الشارةُ «لم يُعيَّن سائق
      // بعد» — أو العكس. مساعدٌ واحدٌ يُقرأ من الموضعين.
      expect(src.contains('bool _apptPassed(Map<String, dynamic> order)'), isTrue);
      expect('_apptPassed(order)'.allMatches(src).length, 2,
          reason: 'الموضعان كلاهما يقرأ المساعدَ نفسَه، لا أحدُهما');
      // موضعان اثنان لا ثالث: `_apptPassed` (قرارُ التتبّع) وشارةُ الموعد
      // (العرض) — كلاهما يستدعي المُحلِّلَ نفسَه، فالبطاقةُ والزرُّ لا يفترقان.
      expect('orderAppointment('.allMatches(src).length, 2,
          reason: 'تحليلٌ ثالثٌ للموعد في الشاشة = مصدرٌ قد يفترق');
      expect(src.contains("DateTime.parse('\${order['booking_date']}"), isFalse,
          reason: 'عاد تحليلُ الموعد يدويّاً داخل الشاشة');
    });
  });
}
