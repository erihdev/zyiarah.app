// مهلةُ النداءات الشبكيّة في الشاشات — **تحويلُ التعليق إلى خطأ**.
//
// المشكلة التي وُجدت بتشغيل التطبيق فعلياً (2026-10-04): شاشاتُ الحجز الثلاث
// تحمل واجهةَ خطأٍ كاملةً مع زرِّ «إعادة المحاولة»، و`catch` يضبط `_hasError`
// — ثمّ لا تُعرض أبداً في العطل الذي كُتبت له. السبب أنّ Firestore يعمل عندنا
// بـ`persistenceEnabled` وذاكرةٍ بلا حدّ، فـ`get()` حين يتعذّر بلوغُ الخادم
// ولا نسخةَ مخزَّنة **لا يرمي: ينتظر**. فلا `catch` يعمل، و`_isLoading` يبقى
// `true`، والعميلةُ ترى هياكلَ تحميلٍ (shimmer) إلى الأبد وزرُّ إعادة المحاولة
// مكتوبٌ في الشيفرة لا يُرسم. وكذلك `httpsCallable` و`signIn`: زرُّ الدخول
// يبقى دوّاراً بلا رسالة.
//
// ولا يحدث هذا بانقطاعٍ كامل — عندها يرمي Firebase `network-request-failed`
// والرسائلُ مكتوبةٌ له سلفاً. يحدث حين **يبدو** الاتصال قائماً والحزمُ لا تصل:
// شبكةُ فندقٍ أو مركزٍ تجاريٍّ خلف بوّابةِ تسجيل، أو وكيلٌ شفّاف، أو واي-فاي
// مرتبطٌ بلا منفذ. الجهاز «متّصل»، فلا خطأ، ولا جواب.
//
// المهلةُ تجعل التعليقَ خطأً، فتُعرض الواجهةُ القائمة أصلاً. وليست فكرةً
// جديدة هنا: `.timeout()` مستعملةٌ في عشرة مواضع (PDF، ميسر، GPS، App Check،
// نداءات HTTP) — الناقصُ كان نداءاتِ Firestore والدوالّ والمصادقة.
library;

import 'dart:async';

/// مهلةُ قراءةٍ من Firestore أو نداءِ دالّةٍ سحابيّة داخل شاشة.
///
/// عشرون ثانية: أطولُ من أيّ نداءٍ سليمٍ على شبكةِ جوّالٍ بطيئة بفارقٍ مريح،
/// وأقصرُ من صبرِ العميلة على شاشةٍ لا تتحرّك.
const Duration kNetCallTimeout = Duration(seconds: 20);

/// مهلةُ المصادقة — أسخى قليلاً: تسجيلُ الدخول قد يشمل تحدّياتٍ إضافية.
const Duration kAuthTimeout = Duration(seconds: 30);

/// مهلةُ **أوّلِ حدث** من بثّ Firestore.
///
/// أسخى من مهلة القراءة الواحدة: المستمِعُ يفتح قناةً ويتفاوض عليها، فثلاثون
/// ثانيةً تترك متّسعاً لشبكةٍ بطيئةٍ قبل أن نُعلن العطل.
const Duration kStreamFirstEventTimeout = Duration(seconds: 30);

/// **مهلةٌ لأوّل حدثٍ وحده، لا لكلِّ فجوةٍ بين الأحداث.**
///
/// وُجد بتشغيل التطبيق (2026-10-04): قسمُ «كوبونات الخصم المعتمدة» في شاشة
/// العروض يعرض دوّاراً **إلى الأبد** — العنوانُ حاضرٌ و«انقر لنسخ الكوبون ثم
/// أدخله عند الدفع» تحته، ولا كوبونَ ولا رسالة. والشيفرةُ تحمل الفروعَ الأربعة
/// كاملةً (خطأ، انتظار، فارغ، قائمة): الفرعُ الذي لا يُغادَر هو «انتظار».
///
/// السببُ نفسُ سببِ `kNetCallTimeout` ممتدّاً إلى البثوث: مع
/// `persistenceEnabled` و**ذاكرةٍ باردة**، `snapshots()` لا يُصدر حدثاً من
/// المخزَّن لأنّه فارغ، ولا يرمي حين يتعذّر بلوغُ الخادم — **ينتظر**. فلا
/// `hasError` ولا `hasData`، و`ConnectionState.waiting` إلى الأبد.
///
/// **ولماذا أوّلُ حدثٍ وحده:** `Stream.timeout` العاديّة تُوقِّت كلَّ فجوة،
/// ومستمِعُ Firestore السليمُ يسكت ساعاتٍ حين لا يتغيّر شيء — فتحويلُها إلى
/// خطأٍ يكسر ما يعمل. بعد أوّلِ حدثٍ تُلغى المؤقّتة ولا تعود.
///
/// والخطأُ **لا يُغلق** البثّ: الاشتراكُ قائم، فإن وصلت البياناتُ متأخّرةً
/// عُرضت وشُفيت الشاشةُ من تلقائها. ويُحفظ كونُه بثّاً عامّاً (broadcast) كما
/// هو، كيلا ينكسر موضعُ استماعٍ ثانٍ.
extension ZyiarahStreamFirstEventTimeout<T> on Stream<T> {
  Stream<T> firstEventTimeout(
      [Duration timeout = kStreamFirstEventTimeout]) {
    final source = this;
    var arrived = false;
    Timer? timer;
    StreamSubscription<T>? sub;
    late final StreamController<T> ctrl;

    void start() {
      timer = Timer(timeout, () {
        if (arrived || ctrl.isClosed) return;
        ctrl.addError(TimeoutException(
            'لم يصل أوّلُ حدثٍ من البثّ خلال ${timeout.inSeconds} ثانية',
            timeout));
      });
      sub = source.listen(
        (e) {
          arrived = true;
          timer?.cancel();
          ctrl.add(e);
        },
        onError: (Object e, StackTrace s) {
          arrived = true;
          timer?.cancel();
          ctrl.addError(e, s);
        },
        onDone: () {
          timer?.cancel();
          ctrl.close();
        },
      );
    }

    Future<void> stop() async {
      timer?.cancel();
      await sub?.cancel();
      sub = null;
    }

    ctrl = source.isBroadcast
        ? StreamController<T>.broadcast(onListen: start, onCancel: stop)
        : StreamController<T>(onListen: start, onCancel: stop);
    return ctrl.stream;
  }
}
