import 'dart:async';

/// **دمجُ قائمتَين من بثَّين: «آخرُ ما وصلَ من كلٍّ» لا تَتابعاً.**
///
/// وُجد الحاجةُ إليه عند تضييقِ قراءةِ `promo_codes`: قاعدةُ Firestore
/// تُجيزُ استعلامَ قائمةٍ متى **أثبتَ** مُرشِّحُه شرطَ الأمان، فاستعلامٌ
/// واحدٌ يَقرأُ الكلَّ صار اثنَين (المُعلَنُ، والموجَّهُ إلى هذه العميلة)،
/// ولا بدَّ من عرضِهما قائمةً واحدة.
///
/// و**الدمجُ البسيطُ خطأٌ هنا**: مناوبةُ البثَّين (merge) تَجعلُ كلَّ حدثٍ
/// يَستبدلُ القائمةَ كلَّها بما جاء من مصدرٍ واحد، فتَختفي كوبوناتُ الآخرِ
/// ثمّ تَعودُ — وميضٌ في الواجهةِ وقائمةٌ ناقصةٌ بين الحدثَين.
///
/// والتكرارُ يُزال بالمعرّف: كوبونٌ مُعلَنٌ **و**موجَّهٌ إليها يُطابقُ
/// الاستعلامَين، فلا يُعرَضُ مرّتَين.
///
/// الإلغاءُ يَنزلُ إلى المصدرَين: `StreamBuilder` يُلغي اشتراكَه عند
/// `dispose`، فـ`onCancel` يُغلِقُ استماعَي Firestore — بلا هذا يَبقى
/// مُستمِعانِ مفتوحَين لكلِّ فتحةِ شاشة.
///
/// والخطأُ يُمرَّرُ كما هو ولا يُغلِقُ البثّ: شاشةُ العروضِ تَملكُ فرعَ خطأٍ
/// يَعرضُه، وإغلاقُ البثِّ يَمنعُ وصولَ البياناتِ المتأخّرةِ بعد عودةِ
/// الشبكة (نفسُ قاعدةِ `firstEventTimeout`).
Stream<List<T>> combineLatestById<T>(
  Stream<List<T>> a,
  Stream<List<T>> b,
  String Function(T) idOf,
) {
  late StreamController<List<T>> ctrl;
  StreamSubscription<List<T>>? subA;
  StreamSubscription<List<T>>? subB;
  List<T>? latestA;
  List<T>? latestB;

  void emit() {
    final byId = <String, T>{};
    for (final list in <List<T>?>[latestA, latestB]) {
      if (list == null) continue;
      for (final item in list) {
        byId[idOf(item)] = item;
      }
    }
    if (!ctrl.isClosed) ctrl.add(byId.values.toList());
  }

  ctrl = StreamController<List<T>>(
    onListen: () {
      subA = a.listen((v) {
        latestA = v;
        emit();
      }, onError: ctrl.addError);
      subB = b.listen((v) {
        latestB = v;
        emit();
      }, onError: ctrl.addError);
    },
    onCancel: () async {
      await subA?.cancel();
      await subB?.cancel();
    },
  );
  return ctrl.stream;
}
