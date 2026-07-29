// حارس: العرض 12 ساعة، والتخزين 24 ساعة — لا يختلطان أبداً.
//
// طلب العميل: تغيير عرض الوقت من 24 إلى 12 ساعة.
//
// **الخطر:** `booking_time_slot` مخزَّن "HH:00" (24)، والدالة الخادمية تحلّله بـ
// `parseInt(slot.split(":")[0])` لتعدّ السعة وتكشف التداخل. لو خُزِّن بصيغة 12
// ("3:00 م") لقُرئ 3 صباحاً ⇒ سلوت المساء يُحسب على الفجر ⇒ حجوزات بلا سائق.
// فالتحويل عرضٌ فقط، والتخزين يبقى 24 حرفياً.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/utils/time_format.dart';

String _code(String path) => File(path)
    .readAsStringSync()
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .split('\n')
    .map((l) {
      final i = l.indexOf('//');
      return i == -1 ? l : l.substring(0, i);
    })
    .join('\n');

void main() {
  group('تحويل 12 ساعة صحيح', () {
    test('منتصف الليل والظهر لا يصيران صفراً', () {
      expect(formatHour12(0), '12:00 ص');
      expect(formatHour12(12), '12:00 م');
    });
    test('الصباح', () {
      expect(formatHour12(8), '8:00 ص');
      expect(formatHour12(11), '11:00 ص');
    });
    test('المساء', () {
      expect(formatHour12(13), '1:00 م');
      expect(formatHour12(15), '3:00 م');
      expect(formatHour12(22), '10:00 م');
    });
    test('من خانة مخزَّنة', () {
      expect(formatSlot12('08:00'), '8:00 ص');
      expect(formatSlot12('15:00'), '3:00 م');
      expect(formatSlot12('00:00'), '12:00 ص');
    });
    test('خانة فارغة/تالفة لا تُسقط شيئاً', () {
      expect(formatSlot12(null), '');
      expect(formatSlot12(''), '');
      expect(formatSlot12('غير معروف'), 'غير معروف'); // تُعاد كما هي لا تُخفى
    });
    test('مدى', () {
      expect(formatRange12(8, 12), '8:00 ص – 12:00 م');
    });
  });

  group('التخزين يبقى 24 ساعة — حرج للسعة', () {
    test("كل كتابة لـ booking_time_slot بصيغة padLeft(2,'0'):00", () {
      // نفحص كل موضع يكتب الحقل: يجب أن يكون "HH:00" لا نصّ 12 ساعة.
      final writers = {
        'lib/screens/payment_summary_screen.dart',
        'lib/screens/checkout_screen.dart',
      };
      for (final p in writers) {
        final s = _code(p);
        final writeRe = RegExp(r"'booking_time_slot':\s*[\s\S]{0,120}?padLeft\(2, '0'\)\}:00");
        expect(writeRe.hasMatch(s), isTrue,
            reason: '$p يكتب booking_time_slot بصيغة غير 24 ساعة ⇒ تنهار السعة الخادمية');
        // ولا يكتبه بصيغة 12 ساعة (ص/م) إطلاقاً
        final badRe = RegExp(r"'booking_time_slot':[^,\n]*(ص|م|formatHour12|formatSlot12)");
        expect(badRe.hasMatch(s), isFalse,
            reason: '$p يخزّن وقتاً بصيغة 12 ساعة — يُقرأ خطأً في الخادم');
      }
    });

    test('الدالة الخادمية ما زالت تحلّل "HH:00"', () {
      final fn = _code('functions/index.js');
      expect(fn.contains('parseInt(String(ts).split(":")[0]'), isTrue,
          reason: 'إن تغيّر التحليل فقد يكون التخزين تغيّر — تأكّد يدوياً');
    });
  });

  group('العرض يستعمل المُنسّق المشترك', () {
    test('لا شاشة تعرض HH:00 خاماً للعميلة', () {
      // (باقات السكن) hourly_details لم تعد تعرض أي ساعة للعميلة إطلاقاً —
      // العميل يختار اليوم فقط والوقت يُرسى داخلياً، فخرجت من هذا الحارس.
      for (final p in [
        'lib/widgets/booking_slot_picker.dart',
        'lib/screens/subscription_plans_screen.dart',
      ]) {
        final s = _code(p);
        expect(s.contains("formatHour12"), isTrue, reason: '$p لا يستعمل مُنسّق 12 ساعة');
        // لا label خام بصيغة 24
        expect(s.contains(r"final label = '${h.toString().padLeft(2, '0')}:00'"), isFalse,
            reason: '$p ما زال يعرض 24 ساعة للعميلة');
      }
    });
  });
}
