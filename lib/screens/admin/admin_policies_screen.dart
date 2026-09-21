import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:zyiarah/models/service_policy.dart';
import 'package:zyiarah/services/audit_service.dart';
import 'package:zyiarah/theme/app_theme.dart';

/// (تصميم Stitch «إدارة شروط وضوابط الخدمة والتعاقد»، 2026-09-16)
///
/// بنود مصنَّفة، لكلٍّ مفتاح تفعيل وشارة «إلزامي قبل تأكيد الحجز»، تُنشر للعميل
/// فور الحفظ في شاشة الشروط والأحكام (ZyiarahTermsScreen). الكتابة للسوبر وحده
/// في firestore.rules، لذا القائمة في admin_more_screen تقصر الشاشة على super_admin.
/// النمط نفسه في admin_banners_screen: بثّ حيّ، حوار StatefulBuilder، تدقيق، وأخطاء
/// ظاهرة لا صامتة.
class AdminPoliciesScreen extends StatefulWidget {
  const AdminPoliciesScreen({super.key});

  @override
  State<AdminPoliciesScreen> createState() => _AdminPoliciesScreenState();
}

class _AdminPoliciesScreenState extends State<AdminPoliciesScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection(ServicePolicy.collectionPath);

  /// null = «الكل».
  String? _filter;

  /// شرائح «إضافة سريعة» في التصميم: تفتح الحوار بتصنيف وعنوان جاهزين.
  static const List<Map<String, String>> _quickAdd = [
    {
      'label': 'خصوصية وسيدات',
      'category': 'privacy_safety',
      'title': 'اشتراطات السلامة والخصوصية العائلية',
    },
    {
      'label': 'اشتراكات السكن',
      'category': 'contracts',
      'title': 'صلاحية العقد واستحقاق الزيارات',
    },
    {
      'label': 'الإلغاء والاسترداد',
      'category': 'cancellation_scheduling',
      'title': 'سياسة مرونة الجدولة وإعادة التعيين',
    },
    {
      'label': 'المواقع الجبلية',
      'category': 'mountain_routes',
      'title': 'ضوابط الطرق والمسارات الجبلية والوعورة',
    },
  ];

  static IconData iconOf(String category) => switch (category) {
        'privacy_safety' => Icons.shield_rounded,
        'cancellation_scheduling' => Icons.update_rounded,
        'mountain_routes' => Icons.terrain_rounded,
        _ => Icons.calendar_month_rounded,
      };

  static Color colorOf(String category) => switch (category) {
        'privacy_safety' => const Color(0xFFB91C1C),
        'cancellation_scheduling' => const Color(0xFFB45309),
        'mountain_routes' => const Color(0xFF0F766E),
        _ => ZyiarahTheme.brand,
      };

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
  }

  Future<void> _toggle(ServicePolicy p, bool value) async {
    try {
      await _col.doc(p.id).update({
        'enabled': value,
        'updated_at': FieldValue.serverTimestamp(),
      });
      ZyiarahAuditService().logAction(
        action: value ? 'ENABLE_POLICY' : 'DISABLE_POLICY',
        details: {'policy_id': p.id, 'title': p.title},
        targetId: p.id,
      );
    } catch (e) {
      _showError('فشل تحديث البند: $e');
    }
  }

  Future<void> _delete(ServicePolicy p) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text('تأكيد الحذف',
              style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
          content: Text('هل تريد حذف البند «${p.title}» نهائياً؟\n'
              'يختفي من شاشة الشروط لدى العميل فوراً.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('حذف الآن',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
    if (confirm != true) return;
    try {
      await _col.doc(p.id).delete();
      ZyiarahAuditService().logAction(
        action: 'DELETE_POLICY',
        details: {'policy_id': p.id, 'title': p.title},
        targetId: p.id,
      );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('تم حذف البند')));
      }
    } catch (e) {
      _showError('خطأ أثناء الحذف: $e');
    }
  }

  /// إضافة (policy == null) أو تعديل. `nextOrder` يضع البند الجديد آخر القائمة.
  void _showPolicyDialog({
    ServicePolicy? policy,
    required int nextOrder,
    String? presetCategory,
    String? presetTitle,
  }) {
    final titleCtrl = TextEditingController(text: policy?.title ?? presetTitle ?? '');
    final bodyCtrl = TextEditingController(text: policy?.body ?? '');
    String category =
        policy?.category ?? presetCategory ?? ServicePolicy.defaultCategory;
    bool mandatory = policy?.mandatoryBeforeBooking ?? false;
    bool enabled = policy?.enabled ?? true;
    bool isSaving = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              title: Text(
                policy == null ? 'إضافة بند أو سياسة جديدة' : 'تعديل البند',
                style: GoogleFonts.tajawal(fontWeight: FontWeight.bold),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (isSaving)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 15),
                        child: LinearProgressIndicator(color: ZyiarahTheme.brand),
                      ),
                    TextField(
                      controller: titleCtrl,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'عنوان البند أو الشرط المختصر',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 15),
                    DropdownButtonFormField<String>(
                      initialValue: category,
                      decoration: const InputDecoration(
                        labelText: 'موضع ونطاق الظهور في التطبيق',
                        border: OutlineInputBorder(),
                      ),
                      items: ServicePolicy.categoryLabels.entries
                          .map((e) => DropdownMenuItem(
                              value: e.key, child: Text(e.value)))
                          .toList(),
                      onChanged: (val) => setDialogState(
                          () => category = val ?? ServicePolicy.defaultCategory),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 6, right: 4),
                      child: Text(
                        ServicePolicy.categoryScopes[category] ?? '',
                        style: GoogleFonts.tajawal(
                            fontSize: 11, color: ZyiarahTheme.inkMuted),
                      ),
                    ),
                    const SizedBox(height: 15),
                    Text('هل البند إلزامي قبل الحجز؟',
                        style: GoogleFonts.tajawal(
                            fontWeight: FontWeight.bold, fontSize: 13)),
                    Text('يتطلب مربع اختيار صريح بالموافقة من العميل',
                        style: GoogleFonts.tajawal(
                            fontSize: 11, color: ZyiarahTheme.inkMuted)),
                    const SizedBox(height: 8),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: true, label: Text('نعم')),
                        ButtonSegment(value: false, label: Text('لا')),
                      ],
                      selected: {mandatory},
                      onSelectionChanged: (s) =>
                          setDialogState(() => mandatory = s.first),
                    ),
                    const SizedBox(height: 15),
                    TextField(
                      controller: bodyCtrl,
                      minLines: 4,
                      maxLines: 10,
                      decoration: const InputDecoration(
                        labelText: 'نص البند والشرط القانوني بالتفصيل',
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 6),
                    SwitchListTile(
                      title: const Text('مفعّل (يظهر للعملاء)'),
                      value: enabled,
                      onChanged: (val) => setDialogState(() => enabled = val),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                    onPressed: isSaving ? null : () => Navigator.pop(ctx),
                    child: const Text('إلغاء')),
                ElevatedButton.icon(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final title = titleCtrl.text.trim();
                          final body = bodyCtrl.text.trim();
                          if (title.isEmpty || body.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        'يرجى كتابة عنوان البند ونصّه أولاً')));
                            return;
                          }
                          setDialogState(() => isSaving = true);
                          try {
                            final data = ServicePolicy(
                              id: policy?.id ?? '',
                              title: title,
                              body: body,
                              category: category,
                              enabled: enabled,
                              mandatoryBeforeBooking: mandatory,
                              order: policy?.order ?? nextOrder,
                            ).toMap()
                              ..['updated_at'] = FieldValue.serverTimestamp();
                            String id;
                            if (policy == null) {
                              id = (await _col.add(data)).id;
                            } else {
                              id = policy.id;
                              await _col.doc(id).update(data);
                            }
                            ZyiarahAuditService().logAction(
                              action: policy == null
                                  ? 'CREATE_POLICY'
                                  : 'UPDATE_POLICY',
                              details: {
                                'policy_id': id,
                                'title': title,
                                'category': category,
                                'mandatory_before_booking': mandatory,
                              },
                              targetId: id,
                            );
                            if (ctx.mounted) Navigator.pop(ctx);
                          } catch (e) {
                            setDialogState(() => isSaving = false);
                            // كما في البانرات: الفشل الصامت يوهم الأدمن أن البند نُشر.
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text('فشل الحفظ: $e'),
                                      backgroundColor: Colors.redAccent));
                            }
                          }
                        },
                  icon: const Icon(Icons.save_outlined, size: 18),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: ZyiarahTheme.brand,
                      foregroundColor: Colors.white),
                  label: Text(isSaving ? 'جاري الحفظ...' : 'اعتماد ونشر فوري'),
                ),
              ],
            ),
          );
        },
      ),
    ).whenComplete(() {
      titleCtrl.dispose();
      bodyCtrl.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          title: Text('شروط وضوابط الخدمة والتعاقد',
              style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
          backgroundColor: ZyiarahTheme.brand,
          foregroundColor: Colors.white,
        ),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _col.orderBy('order').snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.cloud_off_rounded,
                      size: 48, color: Colors.redAccent),
                  const SizedBox(height: 10),
                  Text('تعذّر تحميل البنود',
                      style: GoogleFonts.tajawal(
                          fontWeight: FontWeight.bold, color: Colors.red)),
                  TextButton(
                      onPressed: () => setState(() {}),
                      child: const Text('إعادة المحاولة')),
                ]),
              );
            }
            final all = snapshot.data == null
                ? const <ServicePolicy>[]
                : ServicePolicy.fromQuery(snapshot.data!);
            final activeCount = all.where((p) => p.enabled).length;
            final shown = _filter == null
                ? all
                : all.where((p) => p.category == _filter).toList();
            final nextOrder = all.isEmpty
                ? 0
                : all.map((p) => p.order).reduce((a, b) => a > b ? a : b) + 1;

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                _header(nextOrder),
                const SizedBox(height: 12),
                _quickAddRow(nextOrder),
                const SizedBox(height: 12),
                _filterChips(activeCount),
                const SizedBox(height: 12),
                if (shown.isEmpty) _emptyState(),
                for (final p in shown) _policyCard(p, nextOrder),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _header(int nextOrder) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 0,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: ZyiarahTheme.brand.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.verified_user_rounded,
                    color: ZyiarahTheme.brand),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('إدارة شروط وضوابط الخدمة والتعاقد',
                        style: GoogleFonts.tajawal(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    Row(children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                            color: ZyiarahTheme.success,
                            shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 6),
                      Text('نشر فوري للتطبيق',
                          style: GoogleFonts.tajawal(
                              fontSize: 12, color: ZyiarahTheme.success,
                              fontWeight: FontWeight.bold)),
                    ]),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 10),
            Text(
              'البنود المعتمدة هنا تُعرض للعميل فور حفظها في شاشة الشروط والأحكام، '
              'بنداً بنداً وبحسب تصنيفها. أوقف أي بند بمفتاحه دون حذفه.',
              style: GoogleFonts.tajawal(
                  fontSize: 12, color: ZyiarahTheme.inkMuted, height: 1.6),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () => _showPolicyDialog(nextOrder: nextOrder),
              icon: const Icon(Icons.add_circle_outline_rounded),
              label: const Text('إضافة بند أو شرط خدمة جديد'),
              style: FilledButton.styleFrom(
                backgroundColor: ZyiarahTheme.brand,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(52),
                textStyle: GoogleFonts.tajawal(
                    fontWeight: FontWeight.bold, fontSize: 15),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickAddRow(int nextOrder) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text('إضافة سريعة:',
              style: GoogleFonts.tajawal(
                  fontSize: 12, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final q in _quickAdd)
                ActionChip(
                  label: Text(q['label']!,
                      style: GoogleFonts.tajawal(fontSize: 11)),
                  onPressed: () => _showPolicyDialog(
                    nextOrder: nextOrder,
                    presetCategory: q['category'],
                    presetTitle: q['title'],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _filterChips(int activeCount) {
    Widget chip(String? key, String label) {
      final selected = _filter == key;
      return Padding(
        padding: const EdgeInsets.only(left: 8),
        child: ChoiceChip(
          label: Text(label,
              style: GoogleFonts.tajawal(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: selected ? Colors.white : ZyiarahTheme.ink)),
          selected: selected,
          selectedColor: ZyiarahTheme.brand,
          showCheckmark: false,
          onSelected: (_) => setState(() => _filter = key),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        chip(null, 'الكل ($activeCount بنود نشطة)'),
        for (final e in ServicePolicy.categoryLabels.entries)
          chip(e.key, e.value),
      ]),
    );
  }

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(children: [
        const Icon(Icons.rule_folder_outlined,
            size: 48, color: ZyiarahTheme.inkFaint),
        const SizedBox(height: 10),
        Text('لا توجد بنود في هذا التصنيف بعد',
            style: GoogleFonts.tajawal(
                fontWeight: FontWeight.bold, color: ZyiarahTheme.inkMuted)),
        Text('يظهر للعميل النصّ الافتراضي حتى يُضاف أول بند مفعّل.',
            style: GoogleFonts.tajawal(
                fontSize: 12, color: ZyiarahTheme.inkMuted)),
      ]),
    );
  }

  static String _fmt(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}/${two(d.month)}/${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  Widget _badge(String text, Color color, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
        ],
        Text(text,
            style: GoogleFonts.tajawal(
                fontSize: 10.5, fontWeight: FontWeight.bold, color: color)),
      ]),
    );
  }

  Widget _policyCard(ServicePolicy p, int nextOrder) {
    final color = colorOf(p.category);
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
            color: p.enabled ? Colors.grey.shade200 : Colors.grey.shade300),
      ),
      child: Opacity(
        opacity: p.enabled ? 1 : 0.6,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Switch(
                  value: p.enabled,
                  activeTrackColor: ZyiarahTheme.success,
                  onChanged: (v) => _toggle(p, v),
                ),
                const Spacer(),
                Expanded(
                  flex: 4,
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (p.mandatoryBeforeBooking)
                        _badge('إلزامي قبل تأكيد الحجز', const Color(0xFFB91C1C),
                            icon: Icons.gavel_rounded),
                      _badge(ServicePolicy.labelOf(p.category), color),
                    ],
                  ),
                ),
              ]),
              const SizedBox(height: 6),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(iconOf(p.category), size: 20, color: color),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(p.title,
                      style: GoogleFonts.tajawal(
                          fontSize: 15, fontWeight: FontWeight.bold)),
                ),
              ]),
              const SizedBox(height: 8),
              Text(p.body,
                  style: GoogleFonts.tajawal(
                      fontSize: 13, color: ZyiarahTheme.inkMuted, height: 1.7)),
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 4),
              Row(children: [
                Icon(
                  p.enabled ? Icons.check_circle_rounded : Icons.pause_circle_outline,
                  size: 16,
                  color: p.enabled ? ZyiarahTheme.success : ZyiarahTheme.inkMuted,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    p.enabled ? 'مفعّل ويُعرض للعميل' : 'موقوف — لا يظهر للعميل',
                    style: GoogleFonts.tajawal(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: p.enabled
                            ? ZyiarahTheme.success
                            : ZyiarahTheme.inkMuted),
                  ),
                ),
                IconButton(
                  tooltip: 'تعديل',
                  icon: const Icon(Icons.edit_outlined,
                      color: Colors.blue, size: 20),
                  onPressed: () =>
                      _showPolicyDialog(policy: p, nextOrder: nextOrder),
                ),
                IconButton(
                  tooltip: 'حذف',
                  icon: const Icon(Icons.delete_outline_rounded,
                      color: Colors.red, size: 20),
                  onPressed: () => _delete(p),
                ),
              ]),
              if (p.updatedAt != null)
                Text('آخر تحديث: ${_fmt(p.updatedAt!)}',
                    style: GoogleFonts.tajawal(
                        fontSize: 10, color: ZyiarahTheme.inkMuted)),
            ],
          ),
        ),
      ),
    );
  }
}
