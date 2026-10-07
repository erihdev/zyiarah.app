import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/utils/crew_delay_notice.dart';

/// **عميلةٌ دَفعت، وفاتَ موعدُها، ولا فريق — ولم يكن يُقالُ لها شيء.**
///
/// `sweepUnassignedPaidOrders` يُنبّهُ **الإدارةَ** مرّةً حين يَفوتُ موعدُ
/// البدءِ بساعةٍ بلا إسناد، ويُواصلُ المحاولةَ حتى نهايةِ النافذة، فإن فَشل
/// استردَّ المبلغَ آليّاً. والعميلةُ في هذا كلِّه كانت لا تَسمعُ شيئاً — بل
/// تَلقّت قبلَ ساعتَين «فريقنا في الطريق إليكِ 🚗»، وهو وعدٌ عن فريقٍ لا وجودَ
/// له: تذكيرُ الساعتَين يُرسَلُ لطلبٍ مدفوعٍ ولو بلا سائقٍ إطلاقاً، لأنّ
/// `realAppointment` يَكفيه `is_paid === true` والاستعلامَ يَشملُ `pending`.
void main() {
  String read(String p) => File(p).readAsStringSync();
  String codeOnly(String p) => read(p)
      .split('\n')
      .where((l) {
        final t = l.trimLeft();
        return !t.startsWith('//') && !t.startsWith('*') && !t.startsWith('/*');
      })
      .join('\n');


  /// **جسمُ دالّةٍ خادميّةٍ بحدِّه الحقيقيّ — لا بعدِّ أحرف.**
  ///
  /// كانت الشرائحُ هنا `substring(i, i + 3200)`، و`sweepUnassignedPaidOrders`
  /// طولُه ٤٧٢١ حرفاً بعد التجريد: **٣٢٪ منه خارجَ نظرِ الحارس**. وذلك ليس
  /// تفصيلاً شكليّاً لأنّ فحصَين هنا **يَعُدّان** («لكلِّ جمهورٍ دفعةٌ
  /// واحدة») — وعَدٌّ على ثُلثَي الموضوعِ أجوفُ: دفعةٌ ثانيةٌ في الثُّلثِ
  /// غيرِ المرئيِّ تَمرُّ خضراء. وقد كان كذلك فعلاً: `ADMIN_BROADCAST` يَرِدُ
  /// **مرّتَين** في الدالّةِ والفحصُ يُثبّتُ «مرّةً واحدة» ويَمرّ.
  /// وبالمقابل كانت شريحةُ التذكيرِ (٤٢٠٠) **تَتجاوزُ** دالّتَها (٣٠٢٢)
  /// فتَشملُ ١١٧٨ حرفاً من التاليةِ لها.
  ///
  /// الحدُّ الآن أوّلُ إعلانٍ عُلويٍّ بعدَ المِرساة — فخُّ الحدِّ غيرِ
  /// المُوازَنِ مسجَّلٌ في هذا المستودعِ مرّاتٍ، وهذه صورتُه بعدِّ الأحرف.
  String fnBody(String src, String anchor) {
    final i = src.indexOf(anchor);
    expect(i, greaterThan(-1), reason: 'المِرساةُ «$anchor» اختفت');
    final ends = <int>[
      src.indexOf('\nexports.', i + 10),
      src.indexOf('\nasync function ', i + 10),
      src.indexOf('\nfunction ', i + 10),
    ].where((x) => x > 0);
    final j = ends.isEmpty ? src.length : ends.reduce((a, b) => a < b ? a : b);
    // أرضيّة: اقتطاعٌ يَنحلُّ إلى سطرٍ يُفرِغُ كلَّ فحصٍ بعدَه.
    expect(j - i, greaterThan(400), reason: 'اقتطاعُ «$anchor» انهار');
    return src.substring(i, j);
  }

  final DateTime appt = DateTime(2026, 10, 5, 10, 0);

  group('القاعدة', () {
    test('مدفوعٌ بلا سائقٍ وفاتَ موعدُه بساعة ⇒ يُقال', () {
      expect(
          crewDelayNotice(
              isPaid: true,
              driverId: null,
              status: 'pending',
              appointment: appt,
              now: appt.add(const Duration(hours: 1, minutes: 1))),
          isTrue);
    });

    test('وفي المهلةِ نفسِها لا يُقالُ بعد — نفسُ عتبةِ الخادم', () {
      expect(
          crewDelayNotice(
              isPaid: true,
              driverId: null,
              status: 'pending',
              appointment: appt,
              now: appt.add(const Duration(minutes: 59))),
          isFalse);
      // الحدُّ بالضبط ليس «بعد» — الخادمُ يُقارِنُ `<` كذلك.
      expect(
          crewDelayNotice(
              isPaid: true,
              driverId: null,
              status: 'pending',
              appointment: appt,
              now: appt.add(kCrewDelayGrace)),
          isFalse);
    });

    test('غيرُ مدفوعٍ لا يُقال — لا مالَ ولا وعد', () {
      expect(
          crewDelayNotice(
              isPaid: false,
              driverId: null,
              status: 'pending',
              appointment: appt,
              now: appt.add(const Duration(hours: 5))),
          isFalse);
    });

    test('وله سائقٌ لا يُقال — ولو كان المعرّفُ نصّاً فارغاً فهو بلا سائق', () {
      expect(
          crewDelayNotice(
              isPaid: true,
              driverId: 'drv1',
              status: 'pending',
              appointment: appt,
              now: appt.add(const Duration(hours: 5))),
          isFalse);
      expect(
          crewDelayNotice(
              isPaid: true,
              driverId: '',
              status: 'pending',
              appointment: appt,
              now: appt.add(const Duration(hours: 5))),
          isTrue);
    });

    test('وحالةٌ أخرى لا يُقال — لا نَقولُ «نعمل عليه» عمّا لا يَعملُ عليه أحد', () {
      for (final st in ['scheduled', 'under_review', 'cancelled', 'completed',
        'in_progress', 'awaiting_payment']) {
        expect(
            crewDelayNotice(
                isPaid: true,
                driverId: null,
                status: st,
                appointment: appt,
                now: appt.add(const Duration(hours: 5))),
            isFalse,
            reason: '$st خارجُ نطاقِ مكنسةِ الإسناد');
      }
    });

    test('وبلا موعدٍ لا يُقال', () {
      expect(
          crewDelayNotice(
              isPaid: true,
              driverId: null,
              status: 'pending',
              appointment: null,
              now: appt),
          isFalse);
    });

    test('ولا تُقيَّدُ بنهايةِ النافذة — فشلُ الاستردادِ يُبقي الطلبَ معلّقاً', () {
      // لو قُيّدت، ثمّ فَشل الاستردادُ الآليّ، بَقي الطلبُ `pending` للأبدِ
      // بلا إشعارٍ ولا سطرٍ على البطاقة — أسوأُ مما كان.
      expect(
          crewDelayNotice(
              isPaid: true,
              driverId: null,
              status: 'pending',
              appointment: appt,
              now: appt.add(const Duration(days: 3))),
          isTrue);
    });
  });

  group('المرآةُ مع الخادم', () {
    final String idx = codeOnly('functions/index.js');

    test('نفسُ المهلةِ ونفسُ الحالة', () {
      final body = fnBody(idx, 'exports.sweepUnassignedPaidOrders');
      expect(body.contains('start.getTime() < now - 60 * 60 * 1000'), isTrue,
          reason: 'عتبةُ الخادمِ تغيّرت — لو افترقَ الرقمان لرأت العميلةُ '
              'سطراً بلا إشعارٍ يُفسّره أو العكس');
      expect(kCrewDelayGrace, const Duration(hours: 1));
      expect(body.contains('.where("status", "==", "pending")'), isTrue);
      expect(kCrewDelayStatus, 'pending');
      // وشرطُ وجودِ الموعدِ هو `service_date` نفسُه الذي تُمرّرُه البطاقة.
      expect(body.contains('!d.service_date) continue'), isTrue);
    });

    test('والخادمُ يُخبرُها على علمٍ خاصٍّ بها لا على علمِ الإدارة', () {
      // علمٌ واحدٌ لجمهورَين يَجعلُ أسبقَهما يُسكِتُ الآخر — عطلٌ مسجَّلٌ
      // حرفيّاً في هذا المستودع (الإنذارُ المبكّرُ أسكتَ تنبيهَ الاستردادِ
      // الفاشل لأنّهما تَشاركا `stranded_alerted`).
      final body = fnBody(idx, 'exports.sweepUnassignedPaidOrders');
      expect(body.contains('d.client_stranded_notified !== true'), isTrue,
          reason: 'دفعةُ العميلةِ اختفت');
      expect(body.contains('client_stranded_notified: true'), isTrue);
      // ولا تُقرأُ داخلَ فرعِ علمِ الإدارة: الشرطانِ مستقلّان.
      final adminAt = body.indexOf('d.stranded_alerted !== true');
      final clientAt = body.indexOf('d.client_stranded_notified !== true');
      expect(adminAt, greaterThan(-1));
      expect(clientAt, greaterThan(adminAt),
          reason: 'ترتيبُ الفرعَين تغيّر — راجِعْ استقلالَهما');
      // وبينهما إغلاقُ فرعِ الإدارة، فليسا متداخلَين.
      expect(body.substring(adminAt, clientAt).contains('stranded_alerted: true'),
          isTrue,
          reason: 'دفعةُ العميلةِ صارت داخلَ فرعِ الإدارة — فعلمُ الإدارةِ '
              'يُسكِتُها');
    });

    test('ووعدُ «فريقنا في الطريق» صارَ مشروطاً بوجودِ فريق', () {
      final body = fnBody(idx, 'exports.remindClientsUpcomingAppointments');
      expect(body.contains('const hasCrew = !!d.driver_id;'), isTrue,
          reason: 'السؤالُ «هل يوجدُ فريق» يُجيبُه الحقلُ لا الحالة');
      // والوعدُ لا يُقالُ إلّا في فرعِ وجودِ الفريق.
      final promise = 'فريقنا في الطريق إليكِ';
      final at = body.indexOf(promise);
      expect(at, greaterThan(-1), reason: 'الوعدُ اختفى كاملاً — راجِعْ');
      expect(body.contains('hasCrew ?'), isTrue);
      expect(body.indexOf('hasCrew ?'), lessThan(at),
          reason: 'الوعدُ خارجَ الشرط — يُقالُ لطلبٍ بلا سائق');
    });

    test('وكلٌّ من الجمهورَين له دفعةٌ واحدةٌ **لكلِّ طلب**', () {
      // الصياغةُ الأولى كانت «`ADMIN_BROADCAST` مرّةً واحدةً في الدالّة» —
      // وهي **كاذبةٌ عن الدالّةِ الحقيقيّة**: فيها موضعانِ إداريّان، وإنّما
      // مرَّ الفحصُ لأنّ شريحتَه كانت تَحجبُ ثُلثَها فلا تَرى إلّا الأوّل.
      //
      // والموضعانِ صحيحانِ كلاهما وليسا تكراراً: الأوّلُ إنذارٌ مبكّرٌ
      // والنافذةُ قائمةٌ والمحاولةُ مستمرّة، والثاني بعد انقضائها لِما لا
      // يُستردُّ آليّاً (اشتراك/تقسيط/مفتاحٌ مفقود). والذي يَمنعُ الدفعتَين
      // معاً على طلبٍ واحدٍ هو **العلَمُ المشترَك**: الأوّلُ يَرفعُه،
      // والثاني يَخرجُ عليه صراحةً. فالثابتُ المَحروسُ «دفعةٌ لكلِّ طلب» لا
      // «دفعةٌ في الملفّ»، ويُشَدُّ بما يُنفّذُه: كلُّ موضعٍ محروسٌ بالعلَمِ،
      // وكلُّ موضعٍ يَرفعُه.
      final body = fnBody(idx, 'exports.sweepUnassignedPaidOrders');
      expect('ADMIN_BROADCAST'.allMatches(body).length, 2,
          reason: 'عددُ المواضعِ الإداريّةِ تغيّر — ثالثٌ يَعني تنبيهاً '
              'مكرّراً، وزوالُ أحدِهما يَعني صمتاً في إحدى الحالتَين');
      // الأوّلُ: لم يُنبَّهْ بعدُ ⇒ أنذِرْ.
      expect(body.contains("d.stranded_alerted !== true"), isTrue,
          reason: 'الإنذارُ المبكّرُ بلا حرسِ العلَم — فيُكرَّرُ كلَّ دورة');
      // والثاني: نُبِّهَ سلفاً ⇒ اخرُجْ. وهذا الشرطُ بعينِه كان **خارجَ**
      // الشريحةِ القديمةِ، فلا فحصَ في المستودعِ كلِّه يَشدُّه — وهو وحدَه
      // ما يَمنعُ تنبيهاً ثانياً عن الطلبِ نفسِه.
      expect(body.contains('if (d.stranded_alerted === true) continue;'), isTrue,
          reason: 'الموضعُ الثاني بلا خروجٍ على العلَم — فطلبٌ أُنذِرَ عنه '
              'مبكّراً يُنبَّهُ عنه ثانيةً');
      // وكلٌّ منهما يَرفعُ العلَم، وإلّا لم يُغلَقْ البابُ أصلاً.
      expect('stranded_alerted: true'.allMatches(body).length, 2,
          reason: 'موضعٌ إداريٌّ لا يَرفعُ العلَم — فالدورةُ القادمةُ تُعيدُه');
      // ودفعةُ العميلةِ واحدةٌ فعلاً، والآن على الدالّةِ كاملةً.
      expect('d.client_id,'.allMatches(body).length, 1,
          reason: 'دفعةُ العميلةِ تكرّرت أو اختفت');
      expect('client_stranded_notified: true'.allMatches(body).length, 1,
          reason: 'علَمُ العميلةِ يُرفَعُ في أكثرَ من موضع');
    });
  });

  group('تحيّةُ العميلةِ في موضعٍ واحد', () {
    // كانت مكتوبةً بيدٍ في **أربعةِ** مواضعَ متطابقةٍ حرفاً، وكِتابةُ دفعةِ
    // العميلةِ هذه كانت ستُصبحُ الخامسة — شكلُ «٢٧ موضعاً للضريبة»: اسمٌ
    // افتراضيٌّ جديدٌ يَعني تعديلَ المواضعِ كلِّها، وموضعٌ منسيٌّ يُنادي
    // العميلةَ «عميلة زيارة، موعدكِ…».
    final String idx = codeOnly('functions/index.js');

    test('القائمةُ الحرفيّةُ في موضعٍ واحدٍ فقط', () {
      expect('"عميل زيارة", "عميلة زيارة"'.allMatches(idx).length, 1,
          reason: 'نسخةٌ ثانيةٌ من قائمةِ الأسماءِ الافتراضيّة');
      expect(idx.contains('function _clientGreeting('), isTrue);
    });

    test('وكلُّ موضعِ تحيّةٍ يُنادي الدالّة', () {
      final n = '_clientGreeting('.allMatches(idx).length;
      expect(n, greaterThanOrEqualTo(6),
          reason: 'التعريفُ + أربعةُ مواضعَ موحَّدةٍ + دفعةُ العميلةِ الجديدة');
      expect(idx.contains('const greet = ["", "عميل"'), isFalse,
          reason: 'عادت نسخةٌ مكتوبةٌ بيد');
    });
  });

  group('مواضعُ النداءِ والقواعد', () {
    test('بطاقةُ الطلبِ تَعرضُ السطرَ، وبـservice_date حصراً', () {
      final sc = codeOnly('lib/screens/orders_list_screen.dart');
      expect(sc.contains('_buildCrewDelayNotice(order)'), isTrue,
          reason: 'قاعدةٌ لا تُنادى قاعدةٌ ميتة');
      expect(sc.contains('crewDelayNotice('), isTrue);
      expect(sc.contains("appointment: (order['service_date'] as Timestamp?)?.toDate()"),
          isTrue,
          reason: 'orderAppointment يَرتدُّ إلى منتصفِ الليلِ فيُظهرُ السطرَ '
              'في الواحدةِ صباحاً عن موعدٍ لم يَحِن');
      // ويَظهرُ تحتَ شارةِ الموعد («انتهى الموعد») لا فوقَها.
      expect(sc.indexOf('_buildAppointmentBanner(order)'),
          lessThan(sc.indexOf('_buildCrewDelayNotice(order)')));
    });

    test('والعلمُ محجوبٌ عن الإنشاءِ العميليّ', () {
      expect(read('firestore.rules').contains("'client_stranded_notified'"),
          isTrue,
          reason: 'عميلةٌ تُنشئُ طلبَها بالعلمِ تُسكِتُ إشعارَ نفسِها');
    });

    test('والنصُّ يُعِدُ بما يَفعلُه الخادمُ فعلاً', () {
      // «أُعيد المبلغ كاملاً تلقائيّاً» ليس وعداً مجّانيّاً:
      // `autoResolveUnfulfilledPaidOrder` يَستردُّ عند نهايةِ النافذة.
      expect(kCrewDelayMessage.contains('أُعيد المبلغ كاملاً تلقائيّاً'), isTrue);
      final eng = codeOnly('functions/refund_engine.js');
      expect(eng.contains('async function autoResolveUnfulfilledPaidOrder'),
          isTrue,
          reason: 'لو زالَ الاستردادُ الآليُّ فالنصُّ صارَ وعداً كاذباً');
    });
  });
}
