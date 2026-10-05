import 'package:zyiarah/models/notification_item.dart';

/// **وجهةُ الإشعار: قاعدةٌ واحدةٌ لثلاثةِ قُرّاء.**
///
/// كانت مكتوبةً ثلاثَ مرّاتٍ ولا تَتّفق:
///   • `_routeFor` في `client_notifications_screen` — مسارُ النقرِ داخلَ
///     التطبيق، بالتصنيفِ (`NotificationCategory`)؛
///   • `_actionLabelFor` في الشاشةِ نفسِها — **النصُّ المرئيُّ** على البطاقة،
///     بالتصنيفِ كذلك؛
///   • `handleNotificationTap` في `deep_link_service` — نقرُ إشعارِ FCM،
///     بمفاتيحِ `data` (`orderId`/`ticketId`/`requestId`).
///
/// والنتيجةُ **وجهةٌ خاطئةٌ تحتَ نصٍّ يَعِدُ بغيرِها**، لا مجرّدَ صمت:
/// `categoryOf` تُصنّفُ كلَّ نوعٍ فيه `contract` ضمنَ `payments`، و`relatedId`
/// يَكتبُه الخادمُ `data.orderId || data.code || event.params.id` — فإشعارُ
/// العقدِ لا يَحملُ أيَّهما فيَقعُ على **معرّفِ مستندِ الطابور**: عشرونَ
/// محرفاً، لا يَبدأُ بـ`ZY-` ولا بـ`trig_`، فـ`relatedLooksLikeOrderDoc`
/// تَقولُ «نعم». فبطاقةُ «تم تفعيل باقتك» تَعرضُ زرَّ **«عرض الطلب
/// والفاتورة»** وتَذهبُ إلى `/track/<معرّفِ الطابور>`: شاشةُ تتبّعِ طلبٍ لا
/// وجودَ له. مُثبَتٌ باختبارِ واجهةٍ على الشاشةِ نفسِها، لا بالقراءة.
///
/// و«تم الرد على تذكرتك 💬» في الطرفِ الآخر: `support_ticket` لا يُطابِقُ
/// أيَّ مفردةٍ في `categoryOf` فيَقعُ في `other` ⇒ **لا مسارَ ولا نصَّ زرّ**؛
/// ونقرُ إشعارِ FCM له يُنتجُ `zyiarah://app/ticket/<id>` وفرعُ التذكرةِ في
/// `_handleUri` **محصورٌ بالإدارة** — فالردُّ الذي طلبَته العميلةُ لا يُفتَحُ
/// من أيِّ سطحٍ من الاثنَين.
///
/// فالوجهةُ هنا، والقُرّاءُ الثلاثةُ يَسألونها. والمدخلانِ مختلفانِ عن قصد:
/// سجلُّ `notifications` يَحملُ `type` و`relatedId`، وحِملُ FCM يَحملُ
/// مفاتيحَ `data` **ولا يَحملُ `type`** (المُرسِلُ يَبني `data` وحدَها
/// زائداً `click_action`) — فلكلٍّ بابُه، والقرارُ واحد.
enum NotifDest {
  /// طلبٌ بعينِه — تتبّعُه بمعرّفِه.
  order,

  /// «طلباتي» — طلبٌ بلا معرّفِ مستند (كودٌ فقط، أو لا شيء).
  orders,

  /// العروضُ والكوبونات.
  offers,

  /// «عقودي» للعميلة، وشاشةُ العقودِ للإدارة.
  contracts,

  /// تذكرةُ دعم: شاشةُ الدعمِ للعميلة، وتفاصيلُ التذكرةِ للإدارة.
  support,

  /// أرشيفُ صيانةٍ — للإدارةِ وحدَها (القواعدُ تَمنعُ العميلةَ من قراءتِه).
  maintenance,

  /// لا وجهةَ — يَبقى في مكانِه.
  none,
}

/// وجهةٌ محسوبةٌ: نوعُها، ومعرّفُها إن كان لها، ومسارُها داخلَ التطبيق،
/// ونصُّ زرِّها. النصُّ والمسارُ من مصدرٍ واحدٍ كي لا يَعِدَ أحدُهما بغيرِ ما
/// يَفعلُه الآخر — وهو العطلُ بعينِه الذي وُجدَ هذا الملفُّ له.
class NotifTarget {
  final NotifDest kind;
  final String? id;
  const NotifTarget(this.kind, {this.id});

  /// مسارُ `go_router` أو `null` حين لا وجهة.
  String? get route => switch (kind) {
        NotifDest.order => '/track/$id',
        NotifDest.orders => '/orders',
        NotifDest.offers => '/offers',
        NotifDest.contracts => '/contracts',
        NotifDest.support => '/support',
        // الصيانةُ أرشيفٌ إداريٌّ وحدَه (القواعدُ تَمنعُ العميلةَ من قراءةِ
        // `maintenance_requests`)، فلا مسارَ عميليَّ له — تُفتَحُ من خدمةِ
        // الروابطِ العميقةِ بدفعٍ مشروطٍ بالدور.
        NotifDest.maintenance => null,
        NotifDest.none => null,
      };

  @override
  bool operator ==(Object other) =>
      other is NotifTarget && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);

  @override
  String toString() => 'NotifTarget($kind${id == null ? '' : ', $id'})';
}

/// الأنواعُ التي تَقصدُ العقدَ لا الطلب. `contract_visits_scheduled` يَحملُ
/// `visit` كذلك، و`categoryOf` تَقرؤها `orders` — فالعقدُ يَسبقُ عمداً.
bool _isContractType(String t) =>
    t.contains('contract') || t.contains('subscription');

bool _isTicketType(String t) => t.contains('ticket') || t.contains('support');

/// من سجلِّ `notifications/*` (نقرُ البطاقةِ داخلَ التطبيق).
NotifTarget notifTargetFromRecord({required String type, String? relatedId}) {
  final t = type.toLowerCase();
  if (_isContractType(t)) return const NotifTarget(NotifDest.contracts);
  if (_isTicketType(t)) return const NotifTarget(NotifDest.support);

  final item = NotificationItem(
    id: '',
    title: '',
    body: '',
    type: type,
    createdAt: null,
    isRead: false,
    relatedId: relatedId,
  );
  switch (item.category) {
    case NotificationCategory.orders:
    case NotificationCategory.payments:
      return item.relatedLooksLikeOrderDoc
          ? NotifTarget(NotifDest.order, id: relatedId)
          : const NotifTarget(NotifDest.orders);
    case NotificationCategory.offers:
      return const NotifTarget(NotifDest.offers);
    case NotificationCategory.other:
      return const NotifTarget(NotifDest.none);
  }
}

/// من حِملِ إشعارِ FCM أو الإشعارِ المحلّيّ. **لا `type` فيه** — المُرسِلُ
/// يَبني `data` وحدَها — فالقرارُ بمفاتيحِها، وترتيبُها هو ترتيبُ التحديد:
/// طلبٌ بعينِه أوّلاً، ثمّ تذكرةٌ، ثمّ صيانةٌ، ثمّ عقد.
NotifTarget notifTargetFromData(Map<String, dynamic> data) {
  String? s(String k) {
    final v = data[k];
    if (v == null) return null;
    final str = v.toString().trim();
    return str.isEmpty ? null : str;
  }

  final order = s('orderId');
  if (order != null) return NotifTarget(NotifDest.order, id: order);
  final ticket = s('ticketId');
  if (ticket != null) return NotifTarget(NotifDest.support, id: ticket);
  final request = s('requestId');
  if (request != null) return NotifTarget(NotifDest.maintenance, id: request);
  final contract = s('contractId');
  if (contract != null) return NotifTarget(NotifDest.contracts, id: contract);
  return const NotifTarget(NotifDest.none);
}

/// نصُّ الزرِّ على البطاقة. يَأخذُ التصنيفَ لأنّ الوجهةَ الواحدةَ تُسمّى
/// بوجهَين قائمَين: إشعارُ طلبٍ يَقولُ «تتبع الطلب» وإشعارُ دفعٍ عن الطلبِ
/// نفسِه يَقولُ «عرض الطلب والفاتورة» — صياغةٌ قائمةٌ لا عطل، فتُحفَظ.
String? notifActionLabel(NotifTarget target, NotificationCategory category) =>
    switch (target.kind) {
      NotifDest.order => category == NotificationCategory.payments
          ? 'عرض الطلب والفاتورة'
          : 'تتبع الطلب',
      NotifDest.orders => 'طلباتي',
      NotifDest.offers => 'العروض',
      NotifDest.contracts => 'عقودي',
      NotifDest.support => 'الدعم والمساعدة',
      NotifDest.maintenance => null,
      NotifDest.none => null,
    };
