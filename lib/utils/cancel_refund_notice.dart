/// «ماذا يَحدثُ لمالي إن ألغيت؟» — سؤالٌ لم يَكن يُجابُ في اللحظةِ التي
/// لا رجعةَ فيها.
///
/// حوارُ تأكيدِ الإلغاءِ في `orders_list_screen` كان يَقولُ شيئاً واحداً:
/// «لا يمكن التراجع عن هذا الإجراء» — ولا كلمةَ عن المبلغ. والواقعُ الخادميُّ
/// **ثلاثُ** نتائجَ مختلفةٍ اختلافاً جوهريّاً، والزرُّ نفسُه يَظهرُ في
/// الثلاثِ (`pending` و`awaiting_payment`، وهما ما تُجيزُه القواعدُ للعميلة):
///
///   * **غيرُ مدفوع** ⇒ لا شيءَ أُخِذ ولا شيءَ يُعاد.
///   * **مدفوعٌ من باقةِ اشتراك** (`payment_method == 'subscription'`) ⇒
///     `onOrderRewards` يَستثنيه من إيداعِ المحفظةِ صراحةً، و
///     `settleVisitAccounting` لا يَردُّ زيارةً **لم تُستهلَك** أصلاً
///     (`visit_counted != true`) — فلا مبلغَ ولا حركةَ عدّاد: الزيارةُ ما
///     زالت في رصيدِ باقتها. فرسالةُ «يُعادُ المبلغُ» كذبٌ هنا.
///   * **مدفوعٌ بغيرِ ذلك** (بطاقة، تمارا، محفظة، STC Pay) ⇒
///     `refund_engine.creditCancelledRefund` يُودِعُ المبلغَ **كاملاً في
///     محفظةِ زيارة**، لا إلى البطاقة. ولا سبيلَ لسحبِ رصيدِ المحفظةِ نقداً —
///     لا مسارَ سحبٍ في التطبيقِ ولا في الخادمِ إطلاقاً — فهو رصيدٌ يُنفَقُ
///     داخلَ التطبيقِ وحدَه. وهذا بعينِه ما تَستحقُّ أن تَعرفَه **قبلَ**
///     الضغط، لا بعدَه من دفعةٍ تَصِلُها.
///
/// وهي العائلةُ نفسُها التي صُحِّحت في `wallet_deletion_notice`: **تحذيرٌ عن
/// مالٍ غائبٌ عن اللحظةِ التي لا رجعةَ فيها**، والقاعدةُ المقرَّرةُ هناك
/// تَسري هنا حرفاً بحرف — **عندَ الجهلِ نُخبِرُ بلا رقم**: مستندٌ قديمٌ بلا
/// `amount` (أو بصفرٍ، وهو ما يَجعلُ الخادمَ يَتخطّى الإيداعَ أصلاً) يُنتجُ
/// جملةً شرطيّةً لا رقماً مُلفَّقاً، كما تَفعلُ شريحةُ قطراتٍ وبطاقةُ
/// «إجمالي الحجوزات».
library;

/// ما يُقالُ لها في حوارِ تأكيدِ الإلغاء.
enum CancelRefundKind {
  /// لم يُدفَع — لا جملةَ مالٍ إطلاقاً.
  nothingPaid,

  /// زيارةُ باقةٍ مدفوعةٍ سلفاً — لا مبلغَ يُعاد، والزيارةُ تَبقى في رصيدِها.
  subscriptionVisit,

  /// مدفوعٌ ⇒ يُودَعُ في محفظةِ زيارة، لا في البطاقة.
  walletCredit,
}

/// القرارُ ومعه المقدارُ إن عُرِف.
class CancelRefundNotice {
  /// نوعُ النتيجة.
  final CancelRefundKind kind;

  /// المبلغُ الذي يُودَع — `null` حين لا يُعرَفُ فلا يُذكَرُ رقم.
  final double? amount;

  /// ثابتٌ كي يُقارَنَ في الاختبارات.
  const CancelRefundNotice(this.kind, [this.amount]);

  @override
  bool operator ==(Object other) =>
      other is CancelRefundNotice &&
      other.kind == kind &&
      other.amount == amount;

  @override
  int get hashCode => Object.hash(kind, amount);

  @override
  String toString() => 'CancelRefundNotice($kind, $amount)';
}

/// القرارُ نقيٌّ كي يُختبَرَ بلا Firebase.
///
/// `isPaid` و`paymentMethod` و`amount` تُقرأُ من مستندِ الطلبِ نفسِه الذي
/// تُرسَمُ منه البطاقةُ، فلا حالةَ «جارٍ التحميل» هنا — خلافاً لحوارِ حذفِ
/// الحساب، حيث الرصيدُ قراءةٌ مستقلّة.
CancelRefundNotice cancelRefundNotice({
  required bool isPaid,
  required String? paymentMethod,
  required double? amount,
}) {
  if (!isPaid) return const CancelRefundNotice(CancelRefundKind.nothingPaid);
  if (paymentMethod == 'subscription') {
    return const CancelRefundNotice(CancelRefundKind.subscriptionVisit);
  }
  // الخادمُ يَشترطُ `amount > 0` لِيُودِع، فصفرٌ أو غيابٌ يَعني أنّ الإيداعَ
  // لا يَجري — فلا نَعِدُ برقمٍ، ونَقولُ الجملةَ شرطيّةً.
  final ok = amount != null && amount > 0;
  return CancelRefundNotice(CancelRefundKind.walletCredit, ok ? amount : null);
}

/// نصُّ السطرِ الذي يُلحَقُ بسؤالِ التأكيد — فارغٌ حين لا شيءَ يُقال.
String cancelRefundNoticeText(CancelRefundNotice notice) {
  switch (notice.kind) {
    case CancelRefundKind.nothingPaid:
      return '';
    case CancelRefundKind.subscriptionVisit:
      return 'هذه زيارةٌ من باقتكِ المدفوعةِ مسبقاً: لا يُخصَمُ منكِ شيءٌ '
          'ولا يُعادُ مبلغٌ، وتبقى الزيارةُ في رصيدِ باقتكِ.';
    case CancelRefundKind.walletCredit:
      final a = notice.amount;
      if (a == null) {
        return 'إن كان على الطلبِ مبلغٌ مدفوعٌ فسيُعادُ إلى محفظةِ زيارة '
            '— لا إلى بطاقتكِ — ويُستخدَمُ في حجوزاتكِ القادمة.';
      }
      return 'المبلغُ المدفوعُ (${a.toStringAsFixed(2)} ر.س) يُعادُ إلى '
          'محفظةِ زيارة — لا إلى بطاقتكِ — ويُستخدَمُ في حجوزاتكِ القادمة.';
  }
}

/// النصُّ نفسُه بلسانِ الإدارة — **القاعدةُ واحدةٌ والصياغةُ تَتبعُ الجمهور**،
/// كما في بقيّةِ المشروع: العميلةُ تُخاطَبُ مؤنّثاً، والمالكُ يُخاطَبُ بوصفِ
/// ما يَجري للعميلة. وفي شاشةِ الإدارةِ معلومةٌ زائدةٌ تَلزمُه: استردادُ
/// البوّابةِ (إلغاءُ التفويضِ أو الاسترداد) خيارٌ آخرُ في بطاقةِ عمليّاتِ
/// ميسر في الشاشةِ نفسِها، وحفظُ «ملغي» يَختارُ المحفظةَ عنه بلا أن يُقال.
String cancelRefundAdminText(CancelRefundNotice notice) {
  switch (notice.kind) {
    case CancelRefundKind.nothingPaid:
      return '';
    case CancelRefundKind.subscriptionVisit:
      return 'زيارةُ باقةٍ مدفوعةٍ مسبقاً: لا مبلغَ يُعاد، والزيارةُ تبقى في '
          'رصيد الباقة.';
    case CancelRefundKind.walletCredit:
      final a = notice.amount;
      final sum = a == null ? 'المبلغُ المدفوع' : '${a.toStringAsFixed(2)} ر.س';
      return 'الطلب مدفوع: سيُودَع $sum في محفظة العميلة تلقائياً — لا '
          'استرداد إلى البطاقة. لاسترداد البوّابة استخدم بطاقة عمليات ميسر '
          'أدناه قبل الإلغاء.';
  }
}
