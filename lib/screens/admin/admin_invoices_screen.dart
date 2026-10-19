import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:zyiarah/models/invoice_log_entry.dart';
import 'package:zyiarah/services/zyiarah_pdf_service.dart';
import 'package:zyiarah/theme/app_theme.dart';
import 'package:zyiarah/utils/invoice_stamp.dart';
import '../../utils/net_timeout.dart';
import 'package:zyiarah/utils/vat.dart';

/// سجل الفواتير الإلكترونية (ZATCA) للإدارة والمحاسب — تصميم Stitch `_61`.
///
/// كل طلب مدفوع (خدمات ومتجر) في الشهر المختار: كوده وعميله وخدمته ووسيلة
/// سداده ومرجعها، الإجمالي والضريبة، حالة ملف PDF (جاهز / قيد الإنشاء / فشل)
/// مع فتحه ومشاركته وإعادة إنشائه، وملخص الشهر (العدد، الإجمالي، الضريبة،
/// الصافي، وتوزيع وسائل الدفع). الاستعلام بمدى `created_at` وحده (كلوحة
/// الإحصائيات) فلا فهرس مركّب جديد، والتصفية بالمدفوع محلية.
class AdminInvoicesScreen extends StatefulWidget {
  /// للاختبارات: محمّل شهر بدل Firestore، ووقت ثابت.
  final Future<List<InvoiceLogEntry>> Function(DateTime monthStart)? loader;
  final DateTime? now;

  const AdminInvoicesScreen({super.key, this.loader, this.now});

  @override
  State<AdminInvoicesScreen> createState() => _AdminInvoicesScreenState();
}

class _AdminInvoicesScreenState extends State<AdminInvoicesScreen> {
  static const List<String> _monthNames = [
    'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
    'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
  ];

  late DateTime _month;
  late Future<List<InvoiceLogEntry>> _future;
  final TextEditingController _searchCtrl = TextEditingController();
  final Set<String> _busy = {};

  /// سقفُ كلِّ استعلامٍ شهريّ — **مرّةً واحدةً**، فملاحظةُ القصِّ تُشتَقُّ منه.
  static const int _queryLimit = 1000;

  /// المصادرُ التي بلغ استعلامُها السقفَ في الشهرِ المعروض.
  ///
  /// كان القصُّ **صامتاً**: شهرٌ فيه أكثرُ من ألفِ طلبٍ يُعرَضُ ملخّصُه
  /// (العددُ والإجماليُّ والضريبةُ والصافي) ناقصاً بلا كلمة، والأقدمُ من
  /// الألفِ غائبٌ عن القائمةِ وعن البحثِ — والمحاسبُ يَقرأُ الملخّصَ رقماً نهائيّاً.
  Set<String> _cappedSources = const {};

  @override
  void initState() {
    super.initState();
    final now = widget.now ?? DateTime.now();
    _month = DateTime(now.year, now.month, 1);
    _future = _load(_month);
    _searchCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<List<InvoiceLogEntry>> _load(DateTime monthStart) {
    if (widget.loader != null) return widget.loader!(monthStart);
    return _loadFromFirestore(monthStart);
  }

  Future<List<InvoiceLogEntry>> _loadFromFirestore(DateTime monthStart) async {
    final nextMonth = DateTime(monthStart.year, monthStart.month + 1, 1);
    final db = FirebaseFirestore.instance;
    final capped = <String>{};
    Future<List<InvoiceLogEntry>> fetch(String source) async {
      final snap = await db
          .collection(source)
          .where('created_at',
              isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart))
          .where('created_at', isLessThan: Timestamp.fromDate(nextMonth))
          .orderBy('created_at', descending: true)
          .limit(_queryLimit)
          .get().timeout(kNetCallTimeout);
      if (snap.docs.length >= _queryLimit) capped.add(source);
      return [
        for (final d in snap.docs) InvoiceLogEntry.fromMap(source, d.id, d.data()),
      ];
    }

    final results = await Future.wait([fetch('orders'), fetch('store_orders')]);
    // يُنسَبُ القصُّ إلى شهرِه وحدَه: تنقّلٌ سريعٌ بين الأشهرِ لا يُلصِقُ
    // ملاحظةَ شهرٍ بآخر.
    if (monthStart == _month) _cappedSources = capped;
    return InvoiceLogEntry.paidNewestFirst([...results[0], ...results[1]]);
  }

  void _shift(int months) {
    setState(() {
      _cappedSources = const {};
      _month = DateTime(_month.year, _month.month + months, 1);
      _future = _load(_month);
    });
  }

  void _reload() => setState(() => _future = _load(_month));

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.tajawal()),
      backgroundColor: error ? Colors.redAccent : ZyiarahTheme.success,
    ));
  }

  Future<void> _open(InvoiceLogEntry e) async {
    final url = e.view.pdfUrl;
    // الأزرارُ تظهر على `status == 'ready'`، وقد تكون الوثيقةُ «جاهزة» بلا
    // رابطٍ (كتابةٌ ناقصة). `return;` صامتاً = زرٌّ يُضغط فلا يحدث شيء.
    if (url == null) {
      _snack('الفاتورة مُعلَّمة جاهزةً بلا رابط ملف — أعِد توليدها', error: true);
      return;
    }
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok) _snack('تعذّر فتح ملف الفاتورة', error: true);
  }

  Future<void> _share(InvoiceLogEntry e) async {
    final url = e.view.pdfUrl;
    if (_busy.contains(e.docId)) return; // مشاركةٌ جاريةٌ أصلاً — لا كلامَ لازم
    if (url == null) {
      _snack('الفاتورة مُعلَّمة جاهزةً بلا رابط ملف — أعِد توليدها', error: true);
      return;
    }
    setState(() => _busy.add(e.docId));
    try {
      await ZyiarahPdfService.shareUploadedInvoice(
          url: url, orderCode: e.view.orderCode);
    } catch (err) {
      _snack('تعذّرت مشاركة الفاتورة: $err', error: true);
    } finally {
      if (mounted) setState(() => _busy.remove(e.docId));
    }
  }

  /// إعادة إنشاء الفاتورة ورفعها — الحساب نفسه في شاشة نجاح الطلب.
  Future<void> _regenerate(InvoiceLogEntry e) async {
    if (_busy.contains(e.docId)) return;
    setState(() => _busy.add(e.docId));
    try {
      final v = e.view;
      // `v.issuedAt` كان بين اليدَين و`DateTime.now()` يُمرَّر بجوارِه:
      // إعادةُ توليدِ فاتورةٍ فشلت قبل أيّام كانت تَطبعُ تاريخَ اليوم.
      final qr = invoiceQrFor(issuedAt: v.issuedAt, total: v.total);
      await FirebaseFirestore.instance
          .collection(e.source)
          .doc(e.docId)
          .update({'invoice_pdf_status': 'retrying'});
      final url = await ZyiarahPdfService.generateAndUploadInvoice(
        orderId: e.docId,
        orderCode: v.orderCode,
        amount: v.total,
        qrData: qr,
        issuedAt: v.issuedAt,
        serviceName: v.serviceName,
        discountAmount: v.discount,
        couponCode: v.couponCode,
        collectionPath: e.source,
      );
      if (url == null) throw Exception('لم يُرفع الملف');
      _snack('أُنشئت فاتورة ${v.orderCode}');
      _reload();
    } catch (err) {
      _snack('فشل إنشاء الفاتورة: $err', error: true);
    } finally {
      if (mounted) setState(() => _busy.remove(e.docId));
    }
  }

  static String _money(double v) => '${v.toStringAsFixed(2)} ر.س';


  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          title: Text('سجل الفواتير الإلكترونية',
              style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
          backgroundColor: ZyiarahTheme.brand,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
                tooltip: 'تحديث',
                onPressed: _reload,
                icon: const Icon(Icons.refresh_rounded)),
          ],
        ),
        body: Column(children: [
          _monthNav(),
          Expanded(
            child: FutureBuilder<List<InvoiceLogEntry>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child: CircularProgressIndicator(color: ZyiarahTheme.brand));
                }
                if (snap.hasError) return _error();
                final all = snap.data ?? const <InvoiceLogEntry>[];
                final shown =
                    all.where((e) => e.matches(_searchCtrl.text)).toList();
                final summary = InvoiceLogEntry.summarize(all);
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: [
                    if (_cappedSources.isNotEmpty) ...[
                      _cappedNotice(),
                      const SizedBox(height: 12),
                    ],
                    _summaryCard(summary),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _searchCtrl,
                      decoration: InputDecoration(
                        hintText: 'بحث برقم الطلب أو اسم العميل أو المرجع',
                        hintStyle: GoogleFonts.tajawal(fontSize: 13),
                        prefixIcon: const Icon(Icons.search_rounded),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: Colors.grey.shade200)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (all.isEmpty)
                      _empty('لا فواتير في هذا الشهر')
                    else if (shown.isEmpty)
                      _empty('لا نتائج تطابق البحث')
                    else
                      for (final e in shown) _entryCard(e),
                  ],
                );
              },
            ),
          ),
        ]),
      ),
    );
  }

  Widget _monthNav() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(children: [
        IconButton(
            tooltip: 'الشهر السابق',
            onPressed: () => _shift(-1),
            icon: const Icon(Icons.chevron_right_rounded, color: ZyiarahTheme.brand)),
        Expanded(
          child: Text('${_monthNames[_month.month - 1]} ${_month.year}',
              textAlign: TextAlign.center,
              style: GoogleFonts.tajawal(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
        IconButton(
            tooltip: 'الشهر التالي',
            onPressed: () => _shift(1),
            icon: const Icon(Icons.chevron_left_rounded, color: ZyiarahTheme.brand)),
      ]),
    );
  }

  Widget _error() {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.cloud_off_rounded, size: 48, color: Colors.redAccent),
        const SizedBox(height: 10),
        Text('تعذّر تحميل الفواتير',
            style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, color: Colors.red)),
        TextButton(onPressed: _reload, child: const Text('إعادة المحاولة')),
      ]),
    );
  }

  /// ملاحظةُ القصِّ **قبلَ** الملخّص: رقمٌ يُقرأُ أوّلاً، فتقييدُه بعدَه لا
  /// يَمنعُ قراءتَه دعوى.
  Widget _cappedNotice() {
    final which = [
      if (_cappedSources.contains('orders')) 'الخدمات',
      if (_cappedSources.contains('store_orders')) 'المتجر',
    ].join(' و');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Row(children: [
        Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'بلغت طلبات $which في هذا الشهر سقف العرض ($_queryLimit طلب) — '
            'الملخّص والقائمة يشملان الأحدث فقط، والأقدم غير محسوب هنا',
            style: GoogleFonts.tajawal(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.orange.shade900),
          ),
        ),
      ]),
    );
  }

  Widget _empty(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(children: [
        Icon(Icons.receipt_long_outlined, size: 56, color: Colors.grey.shade300),
        const SizedBox(height: 10),
        Text(text, style: GoogleFonts.tajawal(color: Colors.grey, fontSize: 15)),
      ]),
    );
  }

  Widget _summaryCard(InvoiceSummary s) {
    Widget tile(String label, String value, Color color) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(children: [
            Text(label,
                style: GoogleFonts.tajawal(fontSize: 10.5, color: ZyiarahTheme.inkMuted)),
            const SizedBox(height: 2),
            Text(value,
                textAlign: TextAlign.center,
                style: GoogleFonts.tajawal(
                    fontSize: 13, fontWeight: FontWeight.w900, color: color)),
          ]),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.verified_user_rounded, color: ZyiarahTheme.brand, size: 18),
          const SizedBox(width: 6),
          Expanded(
            child: Text('${s.count} فاتورة مدفوعة هذا الشهر',
                style: GoogleFonts.tajawal(fontSize: 14, fontWeight: FontWeight.bold)),
          ),
          if (s.pending > 0 || s.failed > 0)
            Text(
              [
                if (s.pending > 0) '${s.pending} قيد الإنشاء',
                if (s.failed > 0) '${s.failed} فشلت',
              ].join(' • '),
              style: GoogleFonts.tajawal(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: s.failed > 0 ? ZyiarahTheme.error : ZyiarahTheme.warning),
            ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          tile('الإجمالي شامل الضريبة', _money(s.gross), ZyiarahTheme.brand),
          const SizedBox(width: 6),
          tile('ضريبة القيمة المضافة $kVatRateLabel', _money(s.vat), const Color(0xFFB45309)),
          const SizedBox(width: 6),
          tile('الصافي قبل الضريبة', _money(s.net), const Color(0xFF0F766E)),
        ]),
        if (s.byMethod.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final m in s.byMethod.entries)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('${m.key}: ${_money(m.value)}',
                    style: GoogleFonts.tajawal(
                        fontSize: 10.5, fontWeight: FontWeight.bold, color: ZyiarahTheme.ink)),
              ),
          ]),
        ],
      ]),
    );
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text,
          style: GoogleFonts.tajawal(
              fontSize: 10.5, fontWeight: FontWeight.bold, color: color)),
    );
  }

  Widget _entryCard(InvoiceLogEntry e) {
    final v = e.view;
    final statusColor = switch (e.status) {
      'ready' => ZyiarahTheme.success,
      'failed' => ZyiarahTheme.error,
      _ => ZyiarahTheme.warning,
    };
    final busy = _busy.contains(e.docId);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(v.orderCode,
              textDirection: TextDirection.ltr,
              style: GoogleFonts.tajawal(
                  fontSize: 14, fontWeight: FontWeight.w900, color: ZyiarahTheme.brand)),
          const SizedBox(width: 8),
          _chip(e.sourceLabel, e.isStore ? const Color(0xFF7C3AED) : const Color(0xFF0F766E)),
          const Spacer(),
          _chip(e.statusLabel, statusColor),
        ]),
        const SizedBox(height: 6),
        Text('${e.clientName} — ${v.serviceName}',
            style: GoogleFonts.tajawal(fontSize: 13, fontWeight: FontWeight.bold)),
        Text(invoiceIssuedAtText(v.issuedAt),
            style: GoogleFonts.tajawal(fontSize: 11, color: ZyiarahTheme.inkMuted)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: Text('${v.paymentLabel}${v.paymentRef != null ? ' • ${v.paymentRef}' : ''}',
                style: GoogleFonts.tajawal(fontSize: 11.5, color: ZyiarahTheme.inkMuted)),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(_money(v.total),
                style: GoogleFonts.tajawal(
                    fontSize: 15, fontWeight: FontWeight.w900, color: ZyiarahTheme.ink)),
            Text('منها ضريبة ${_money(v.vat)}',
                style: GoogleFonts.tajawal(fontSize: 10.5, color: ZyiarahTheme.inkMuted)),
          ]),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          if (e.status == 'ready') ...[
            TextButton.icon(
              onPressed: busy ? null : () => _open(e),
              icon: const Icon(Icons.picture_as_pdf_rounded, size: 16),
              label: const Text('فتح PDF'),
            ),
            TextButton.icon(
              onPressed: busy ? null : () => _share(e),
              icon: busy
                  ? const SizedBox(
                      width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.ios_share_rounded, size: 16),
              label: const Text('مشاركة'),
            ),
          ] else
            TextButton.icon(
              onPressed: busy ? null : () => _regenerate(e),
              icon: busy
                  ? const SizedBox(
                      width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.autorenew_rounded, size: 16),
              label: Text(e.status == 'failed' ? 'إعادة إنشاء الفاتورة' : 'إنشاء الفاتورة الآن'),
              style: TextButton.styleFrom(foregroundColor: statusColor),
            ),
        ]),
      ]),
    );
  }
}
