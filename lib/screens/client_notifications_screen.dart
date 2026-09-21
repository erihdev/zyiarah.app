import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:zyiarah/models/notification_item.dart';
import 'package:zyiarah/theme/app_theme.dart';

/// مركز تنبيهات العميل (تصميم Stitch، 2026-09-16).
///
/// ما أُضيف على القائمة القديمة: عدّاد الجديد و«قراءة الكل»، شرائح تصفية
/// بالتصنيف مع أعدادها، مفتاح لعرض المقروء أيضاً (كان المقروء يختفي نهائياً)،
/// والنقر يفتح ما يخصّ الإشعار (تتبّع الطلب / طلباتي / العروض) لا يعلّمه مقروءاً
/// فحسب. الترقيم كما كان: نافذة بثّ 50 وصفحات أقدم بـ«عرض المزيد».
class ClientNotificationsScreen extends StatefulWidget {
  /// للاختبارات: بثّ جاهز بدل Firestore (بلا ترقيم)، وهويّة مفروضة، وتعليم
  /// المقروء وتنقّل قابلان للاعتراض.
  final Stream<List<NotificationItem>>? items;
  final String? uid;
  final Future<void> Function(List<String> ids)? markRead;
  final void Function(BuildContext context, String route)? navigate;

  /// (تفضيلات التنبيهات) قراءة/حفظ مفتاح «العروض والتسويق» — للاختبارات.
  final Future<bool> Function()? loadMarketingPref;
  final Future<void> Function(bool enabled)? saveMarketingPref;

  const ClientNotificationsScreen({
    super.key,
    this.items,
    this.uid,
    this.markRead,
    this.navigate,
    this.loadMarketingPref,
    this.saveMarketingPref,
  });

  @override
  State<ClientNotificationsScreen> createState() =>
      _ClientNotificationsScreenState();
}

class _ClientNotificationsScreenState extends State<ClientNotificationsScreen> {
  // ترقيم السجل: نافذة البث الحيّ تبقى limit(50)، والصفحات الأقدم تُجلب مرة
  // واحدة عبر startAfterDocument وتبقى ثابتة (زر «عرض المزيد»).
  // الاستعلام بلا orderBy (الفرز محلي) فالمؤشر يتبع ترتيب Firestore الضمني
  // بمعرّف المستند — الفرز الزمني المحلي يدمج الصفحات في مكانها الصحيح.
  static const int _pageSize = 50;
  final List<QueryDocumentSnapshot> _olderDocs = [];
  // مستندات get() الثابتة لا يصلها تحديث البث — نعلّم المقروء محلياً ليختفي فوراً.
  final Set<String> _readLocally = {};
  bool _loadingMore = false;
  bool _exhausted = false;

  NotificationCategory? _category;
  bool _unreadOnly = true;

  Future<void> _loadMore(String uid, DocumentSnapshot cursor) async {
    if (_loadingMore || _exhausted) return;
    setState(() => _loadingMore = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('notifications')
          .where('userId', isEqualTo: uid)
          .startAfterDocument(cursor)
          .limit(_pageSize)
          .get();
      if (!mounted) return;
      setState(() {
        _olderDocs.addAll(snap.docs);
        if (snap.docs.length < _pageSize) _exhausted = true;
      });
    } catch (e) {
      debugPrint("Error loading more notifications: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('تعذّر تحميل المزيد من الإشعارات'),
            backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  /// تعليم كمقروء بالحقلين معاً (توحيد مع عدّاد الجرس)، دفعةً واحدة.
  Future<void> _markRead(List<String> ids) async {
    if (ids.isEmpty) return;
    try {
      if (widget.markRead != null) {
        await widget.markRead!(ids);
      } else {
        final db = FirebaseFirestore.instance;
        // حدّ الدفعة 500 عملية — نافذة البث 50 وصفحاتها نادراً ما تتجاوزه.
        for (var i = 0; i < ids.length; i += 400) {
          final batch = db.batch();
          for (final id in ids.skip(i).take(400)) {
            batch.update(db.collection('notifications').doc(id),
                {'isRead': true, 'is_read': true});
          }
          await batch.commit();
        }
      }
      if (mounted) setState(() => _readLocally.addAll(ids));
    } catch (e) {
      debugPrint("Error marking notifications as read: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('تعذّر تعليم الإشعارات كمقروءة'),
            backgroundColor: Colors.red));
      }
    }
  }

  void _go(String route) {
    if (widget.navigate != null) {
      widget.navigate!(context, route);
    } else {
      context.push(route);
    }
  }

  /// وجهة الإشعار: طلب بمعرّفه → التتبّع؛ طلب بكوده → طلباتي؛ عرض → العروض.
  String? _routeFor(NotificationItem n) {
    switch (n.category) {
      case NotificationCategory.orders:
      case NotificationCategory.payments:
        return n.relatedLooksLikeOrderDoc ? '/track/${n.relatedId}' : '/orders';
      case NotificationCategory.offers:
        return '/offers';
      case NotificationCategory.other:
        return null;
    }
  }

  Future<void> _open(NotificationItem n) async {
    if (!n.isRead && !_readLocally.contains(n.id)) await _markRead([n.id]);
    final route = _routeFor(n);
    if (route != null && mounted) _go(route);
  }

  /// زر «عرض المزيد» — حالة تحميل صغيرة أثناء جلب الصفحة الأقدم.
  Widget _buildLoadMoreFooter(String uid, DocumentSnapshot cursor) {
    return Center(
      child: _loadingMore
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: ZyiarahTheme.brand),
              ),
            )
          : TextButton.icon(
              onPressed: () => _loadMore(uid, cursor),
              icon: const Icon(Icons.expand_more_rounded,
                  color: ZyiarahTheme.brand, size: 20),
              label: Text('عرض المزيد',
                  style: GoogleFonts.tajawal(
                      fontWeight: FontWeight.bold, color: ZyiarahTheme.brand)),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = widget.items != null
        ? widget.uid
        : FirebaseAuth.instance.currentUser?.uid;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          title: Text('الإشعارات',
              style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
          backgroundColor: ZyiarahTheme.brand,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: uid == null
            ? const Center(child: Text('يرجى تسجيل الدخول'))
            : (widget.items != null
                ? _injectedBody(uid)
                : _firestoreBody(uid)),
      ),
    );
  }

  Widget _injectedBody(String uid) {
    return StreamBuilder<List<NotificationItem>>(
      stream: widget.items,
      builder: (context, s) {
        if (s.connectionState == ConnectionState.waiting && !s.hasData) {
          return const Center(
              child: CircularProgressIndicator(color: ZyiarahTheme.brand));
        }
        if (s.hasError) return _errorState();
        return _list(uid, s.data ?? const [], footer: null);
      },
    );
  }

  Widget _firestoreBody(String uid) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('notifications')
          .where('userId', isEqualTo: uid)
          .limit(_pageSize)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: ZyiarahTheme.brand));
        }
        if (snapshot.hasError) return _errorState();

        // المؤشر يُلتقط من ترتيب Firestore الخام قبل الفرز المحلي.
        final streamDocs = snapshot.data?.docs ?? <QueryDocumentSnapshot>[];
        final DocumentSnapshot? cursor = _olderDocs.isNotEmpty
            ? _olderDocs.last
            : (streamDocs.isNotEmpty ? streamDocs.last : null);
        final canLoadMore =
            !_exhausted && streamDocs.length >= _pageSize && cursor != null;

        // دمج نافذة البث مع الصفحات الأقدم مع منع تكرار المستندات.
        final seen = streamDocs.map((d) => d.id).toSet();
        final items = <NotificationItem>[
          for (final d in streamDocs) NotificationItem.fromDoc(d),
          for (final d in _olderDocs.where((d) => seen.add(d.id)))
            NotificationItem.fromDoc(d),
        ];
        return _list(uid, items,
            footer: canLoadMore ? _buildLoadMoreFooter(uid, cursor) : null);
      },
    );
  }

  Widget _errorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.wifi_off_rounded, size: 48, color: Colors.grey),
          const SizedBox(height: 12),
          Text('تعذّر تحميل الإشعارات',
              style: GoogleFonts.tajawal(color: Colors.grey, fontSize: 14)),
        ],
      ),
    );
  }

  bool _effectivelyRead(NotificationItem n) =>
      n.isRead || _readLocally.contains(n.id);

  Widget _list(String uid, List<NotificationItem> all, {required Widget? footer}) {
    final sorted = [...all]..sort(NotificationItem.newestFirst);
    final unread = sorted.where((n) => !_effectivelyRead(n)).toList();
    final base = _unreadOnly ? unread : sorted;
    final visible = _category == null
        ? base
        : base.where((n) => n.category == _category).toList();

    int countOf(NotificationCategory? c) =>
        c == null ? base.length : base.where((n) => n.category == c).length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _header(uid, unread),
        const SizedBox(height: 10),
        _filterChips(countOf),
        const SizedBox(height: 12),
        if (visible.isEmpty)
          _emptyState()
        else
          for (final n in visible) ...[
            _ClientNotifCard(
              item: n,
              isRead: _effectivelyRead(n),
              actionLabel: _actionLabelFor(n),
              onTap: () => _open(n),
            ),
            const SizedBox(height: 8),
          ],
        if (footer != null) footer,
      ],
    );
  }

  String? _actionLabelFor(NotificationItem n) {
    switch (n.category) {
      case NotificationCategory.orders:
        return n.relatedLooksLikeOrderDoc ? 'تتبع الطلب' : 'طلباتي';
      case NotificationCategory.payments:
        return n.relatedLooksLikeOrderDoc ? 'عرض الطلب والفاتورة' : 'طلباتي';
      case NotificationCategory.offers:
        return 'العروض';
      case NotificationCategory.other:
        return null;
    }
  }

  Widget _header(String uid, List<NotificationItem> unread) {
    return Row(children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            unread.isEmpty ? 'لا جديد' : '${unread.length} جديدة',
            style: GoogleFonts.tajawal(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          Text('مزامنة حية مع طلباتك ومدفوعاتك وعروضك',
              style: GoogleFonts.tajawal(fontSize: 11, color: ZyiarahTheme.inkMuted)),
        ]),
      ),
      TextButton.icon(
        onPressed: unread.isEmpty
            ? null
            : () => _markRead(unread.map((n) => n.id).toList()),
        icon: const Icon(Icons.done_all_rounded, size: 18),
        label: Text('قراءة الكل',
            style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 12)),
        style: TextButton.styleFrom(foregroundColor: ZyiarahTheme.brand),
      ),
      IconButton(
        tooltip: _unreadOnly ? 'عرض المقروءة أيضاً' : 'الجديدة فقط',
        onPressed: () => setState(() => _unreadOnly = !_unreadOnly),
        icon: Icon(
          _unreadOnly ? Icons.history_rounded : Icons.mark_email_unread_outlined,
          color: ZyiarahTheme.brand,
        ),
      ),
      IconButton(
        tooltip: 'تفضيلات التنبيهات',
        onPressed: () => _openPrefs(uid),
        icon: const Icon(Icons.tune_rounded, color: ZyiarahTheme.brand),
      ),
    ]);
  }

  // ── تفضيلات التنبيهات (Stitch `_52` «تفضيلات تنبيهات الزيارة») ──
  // مفتاح واحد: «العروض والتسويق». تنبيهات الطلبات والمدفوعات والمواعيد تصل دائماً
  // (تُرسل عبر notification_triggers لا عبر البثّ). يُخزَّن في
  // users/{uid}.notification_prefs.marketing ويقرؤه الخادم عند كل بثّ تسويقي.
  Future<bool> _loadPref(String uid) async {
    if (widget.loadMarketingPref != null) return widget.loadMarketingPref!();
    final d = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final prefs = d.data()?['notification_prefs'];
    return prefs is Map ? prefs['marketing'] != false : true;
  }

  Future<void> _savePref(String uid, bool enabled) async {
    if (widget.saveMarketingPref != null) return widget.saveMarketingPref!(enabled);
    await FirebaseFirestore.instance.collection('users').doc(uid).set(
      {'notification_prefs': {'marketing': enabled}},
      SetOptions(merge: true),
    );
  }

  Future<void> _openPrefs(String uid) async {
    bool current = true;
    bool loadFailed = false;
    try {
      current = await _loadPref(uid);
    } catch (e) {
      debugPrint('[notification_prefs] load failed: $e');
      loadFailed = true;
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (sheetCtx) {
        bool value = current;
        bool saving = false;
        return StatefulBuilder(builder: (sheetCtx, setSheet) {
          return Directionality(
            textDirection: TextDirection.rtl,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('تفضيلات التنبيهات',
                      style: GoogleFonts.tajawal(
                          fontSize: 17, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(
                    'تنبيهات طلباتك ومدفوعاتك ومواعيدك تصلك دائماً — هنا تتحكّم بالعروض فقط.',
                    style: GoogleFonts.tajawal(
                        fontSize: 12, color: ZyiarahTheme.inkMuted),
                  ),
                  if (loadFailed)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('تعذّر قراءة الإعداد الحالي — يُعرض الافتراضي.',
                          style: GoogleFonts.tajawal(
                              fontSize: 12, color: ZyiarahTheme.error)),
                    ),
                  const SizedBox(height: 8),
                  SwitchListTile.adaptive(
                    value: value,
                    contentPadding: EdgeInsets.zero,
                    activeThumbColor: ZyiarahTheme.brand,
                    title: Text('العروض والتسويق',
                        style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
                    subtitle: Text(
                      value
                          ? 'تصلك الخصومات والباقات الجديدة'
                          : 'لن يصلك أي بثّ تسويقي — التنبيهات التشغيلية فقط',
                      style: GoogleFonts.tajawal(
                          fontSize: 12, color: ZyiarahTheme.inkMuted),
                    ),
                    onChanged: saving
                        ? null
                        : (v) async {
                            setSheet(() {
                              value = v;
                              saving = true;
                            });
                            try {
                              await _savePref(uid, v);
                            } catch (e) {
                              debugPrint('[notification_prefs] save failed: $e');
                              if (sheetCtx.mounted) setSheet(() => value = !v);
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('تعذّر حفظ التفضيل — حاول مجدداً'),
                                      backgroundColor: Colors.red),
                                );
                              }
                            } finally {
                              if (sheetCtx.mounted) setSheet(() => saving = false);
                            }
                          },
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  Widget _filterChips(int Function(NotificationCategory?) countOf) {
    Widget chip(NotificationCategory? c, String label) {
      final selected = _category == c;
      return Padding(
        padding: const EdgeInsets.only(left: 8),
        child: ChoiceChip(
          label: Text('$label (${countOf(c)})',
              style: GoogleFonts.tajawal(
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                  color: selected ? Colors.white : ZyiarahTheme.ink)),
          selected: selected,
          selectedColor: ZyiarahTheme.brand,
          showCheckmark: false,
          onSelected: (_) => setState(() => _category = c),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        chip(null, 'الكل'),
        chip(NotificationCategory.orders,
            NotificationItem.labelOf(NotificationCategory.orders)),
        chip(NotificationCategory.payments,
            NotificationItem.labelOf(NotificationCategory.payments)),
        chip(NotificationCategory.offers,
            NotificationItem.labelOf(NotificationCategory.offers)),
      ]),
    );
  }

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(Icons.notifications_none_outlined, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            _category != null
                ? 'لا توجد إشعارات في هذا القسم'
                : (_unreadOnly ? 'لا توجد إشعارات جديدة' : 'لا توجد إشعارات بعد'),
            style: GoogleFonts.tajawal(color: Colors.grey, fontSize: 15),
          ),
          if (_unreadOnly && _category == null)
            Text('اضغط أيقونة السجل أعلاه لعرض المقروءة',
                style: GoogleFonts.tajawal(color: Colors.grey[400], fontSize: 12)),
        ],
      ),
    );
  }
}

class _ClientNotifCard extends StatelessWidget {
  final NotificationItem item;
  final bool isRead;
  final String? actionLabel;
  final VoidCallback onTap;

  const _ClientNotifCard({
    required this.item,
    required this.isRead,
    required this.actionLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final timeAgo = item.createdAt == null ? '' : _formatTimeAgo(item.createdAt!);

    final (IconData icon, Color iconColor) = switch (item.category) {
      NotificationCategory.orders => (Icons.local_shipping_outlined, Colors.blue),
      NotificationCategory.payments => (Icons.receipt_long_outlined, Colors.teal),
      NotificationCategory.offers => (Icons.local_offer_outlined, Colors.orange),
      NotificationCategory.other => (Icons.notifications_outlined, ZyiarahTheme.brand),
    };

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isRead ? Colors.white : const Color(0xFFF3E8FF),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isRead
                ? Colors.grey.shade100
                : ZyiarahTheme.brand.withValues(alpha: 0.2),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title,
                      style: GoogleFonts.tajawal(
                          fontWeight: isRead ? FontWeight.w600 : FontWeight.bold,
                          fontSize: 13,
                          color: ZyiarahTheme.ink)),
                  if (item.body.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(item.body,
                        style: GoogleFonts.tajawal(
                            fontSize: 12, color: Colors.grey[600], height: 1.4)),
                  ],
                  const SizedBox(height: 6),
                  Row(children: [
                    Expanded(
                      child: Text(timeAgo,
                          style: GoogleFonts.tajawal(
                              fontSize: 10, color: Colors.grey[400])),
                    ),
                    if (actionLabel != null)
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(actionLabel!,
                            style: GoogleFonts.tajawal(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: ZyiarahTheme.brand)),
                        const Icon(Icons.chevron_left_rounded,
                            size: 16, color: ZyiarahTheme.brand),
                      ]),
                  ]),
                ],
              ),
            ),
            if (!isRead)
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(top: 4),
                decoration: const BoxDecoration(
                  color: ZyiarahTheme.brand,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatTimeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'الآن';
    if (diff.inMinutes < 60) return 'منذ ${diff.inMinutes} دقيقة';
    if (diff.inHours < 24) return 'منذ ${diff.inHours} ساعة';
    return DateFormat('yyyy/MM/dd').format(dt);
  }
}
