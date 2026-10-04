// حارس: **دوّارٌ إلى الأبد ليس حالةً مقبولة.**
//
// وُجد بتشغيل التطبيق (2026-10-04): قسمُ «كوبونات الخصم المعتمدة» في شاشة
// العروض يعرض دوّاراً لا ينتهي — العنوانُ حاضرٌ و«انقر لنسخ الكوبون ثم أدخله
// عند الدفع» تحته، ولا كوبونَ ولا رسالة. والشيفرةُ تحمل الفروعَ الأربعة
// كاملةً (خطأ، انتظار، فارغ، قائمة)؛ الفرعُ الذي لا يُغادَر هو «انتظار».
//
// السببُ امتدادُ سبب `kNetCallTimeout` إلى البثوث: مع `persistenceEnabled`
// وذاكرةٍ باردة، `snapshots()` لا يُصدر من المخزَّن (فارغ) ولا يرمي حين يتعذّر
// بلوغُ الخادم — **ينتظر**.
//
// ودقّةُ القاعدة هي كلُّ شيء: مهلةٌ على **كلّ فجوة** تكسر ما يعمل، لأنّ
// مستمِعَ Firestore السليمَ يسكت ساعاتٍ حين لا يتغيّر شيء. المهلةُ لأوّل حدثٍ
// وحدَه.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/utils/net_timeout.dart';

const _t = Duration(milliseconds: 120);

void main() {
  test('حدثٌ سريع ⇒ لا خطأ', () async {
    final s = Stream<int>.value(7).firstEventTimeout(_t);
    expect(await s.first, 7);
  });

  test('بثٌّ لا يُصدر شيئاً ⇒ خطأُ مهلة', () async {
    final c = StreamController<int>();
    addTearDown(c.close);
    final got = <Object>[];
    c.stream.firstEventTimeout(_t).listen((_) {}, onError: got.add);
    await Future<void>.delayed(_t * 3);
    expect(got.length, 1);
    expect(got.single, isA<TimeoutException>());
  });

  test('**بعد أوّل حدثٍ لا مهلةَ على الفجوات** — وهذا بيتُ القصيد', () async {
    // مستمِعٌ سليمٌ يسكت طويلاً؛ لو وقّتنا كلَّ فجوةٍ لكسرنا ما يعمل.
    final c = StreamController<int>();
    addTearDown(c.close);
    final errs = <Object>[];
    final data = <int>[];
    c.stream.firstEventTimeout(_t).listen(data.add, onError: errs.add);
    c.add(1);
    await Future<void>.delayed(_t * 4); // فجوةٌ أطولُ من المهلة بكثير
    expect(errs, isEmpty);
    c.add(2);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(data, [1, 2]);
  });

  test('خطأٌ من المصدر يمرّ ويُلغي المؤقّتة (لا خطأٌ ثانٍ)', () async {
    final c = StreamController<int>();
    addTearDown(c.close);
    final errs = <Object>[];
    c.stream.firstEventTimeout(_t).listen((_) {}, onError: errs.add);
    c.addError(StateError('من الخادم'));
    await Future<void>.delayed(_t * 3);
    expect(errs.length, 1, reason: 'المهلةُ أضافت خطأً ثانياً فوق الخطأ الحقيقيّ');
    expect(errs.single, isA<StateError>());
  });

  test('البثُّ لا يُغلَق بالمهلة — البياناتُ المتأخّرة تُعرض فتُشفى الشاشة',
      () async {
    final c = StreamController<int>();
    addTearDown(c.close);
    final errs = <Object>[];
    final data = <int>[];
    c.stream.firstEventTimeout(_t).listen(data.add, onError: errs.add);
    await Future<void>.delayed(_t * 2);
    expect(errs.length, 1);
    c.add(42); // وصلت الشبكةُ متأخّرة
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(data, [42]);
  });

  test('onDone يمرّ ويُغلق', () async {
    final c = StreamController<int>();
    var done = false;
    c.stream.firstEventTimeout(_t).listen((_) {}, onDone: () => done = true);
    c.add(1);
    await c.close();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(done, isTrue);
  });

  test('الإلغاءُ يُسكت المهلة (لا خطأَ بعد مغادرة الشاشة)', () async {
    final c = StreamController<int>();
    addTearDown(c.close);
    final errs = <Object>[];
    final sub =
        c.stream.firstEventTimeout(_t).listen((_) {}, onError: errs.add);
    await sub.cancel();
    await Future<void>.delayed(_t * 3);
    expect(errs, isEmpty);
  });

  test('كونُ البثِّ عامّاً يُحفظ — وإلّا انكسر موضعُ استماعٍ ثانٍ', () async {
    final b = StreamController<int>.broadcast();
    addTearDown(b.close);
    final w = b.stream.firstEventTimeout(_t);
    expect(w.isBroadcast, isTrue);
    final a = <int>[], z = <int>[];
    w.listen(a.add);
    w.listen(z.add);
    b.add(5);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(a, [5]);
    expect(z, [5]);

    // بثٌّ أحاديُّ الاشتراك يبقى أحاديّاً. (لا نُغلقه في التفكيك: إغلاقُ
    // متحكّمٍ أحاديٍّ بلا مستمِعٍ لا يكتمل مستقبلُه فيعلّق الاختبار نفسَه.)
    final single = StreamController<int>();
    expect(single.stream.firstEventTimeout(_t).isBroadcast, isFalse);
  });

  test('المهلةُ الافتراضيّة ثلاثون ثانية — أسخى من مهلة القراءة الواحدة', () {
    expect(kStreamFirstEventTimeout, const Duration(seconds: 30));
    expect(kStreamFirstEventTimeout, greaterThan(kNetCallTimeout));
  });
}
