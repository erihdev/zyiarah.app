import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:zyiarah/utils/net_timeout.dart';
import 'package:zyiarah/utils/driver_rating.dart';

class AdminStaffPerformanceScreen extends StatefulWidget {
  const AdminStaffPerformanceScreen({super.key});

  @override
  State<AdminStaffPerformanceScreen> createState() => _AdminStaffPerformanceScreenState();
}

class _AdminStaffPerformanceScreenState extends State<AdminStaffPerformanceScreen> {
  bool _isLoading = true;
  // فشل الجلب كان يعرض قائمة فارغة مطابقة تماماً لحالة «لا يوجد سائقون» بلا أي
  // وسيلة إعادة محاولة — نميّز الفشل لعرض رسالة خطأ + زر إعادة.
  bool _loadFailed = false;
  List<Map<String, dynamic>> _staffStats = [];

  @override
  void initState() {
    super.initState();
    _calculatePerformance();
  }

  Future<void> _calculatePerformance() async {
    try {
      // بلا orderBy على rating_avg: الاستعلام المرتّب يستبعد أي سائق لا يملك الحقل
      // (يُنشأ عند أول تقييم فقط) فلا يظهر السائقون الجدد إطلاقاً. نجلب الكل ونرتّب محلياً.
      final driversSnap = await FirebaseFirestore.instance
          .collection('drivers')
          .get().timeout(kNetCallTimeout);

      List<Map<String, dynamic>> stats = [];

      for (var driverDoc in driversSnap.docs) {
        final driverData = driverDoc.data();
        final driverId = driverDoc.id;
        final driverName = driverData['name'] ?? 'بدون اسم';
        // تحويل آمن: قد تُخزَّن هذه الحقول كنص → الضرب المباشر في الفرز ينهار.
        final int totalCompleted =
            int.tryParse('${driverData['completed_orders_count'] ?? 0}') ?? 0;
        // **بلا تقييمٍ ليس تقييماً ٥٫٠.** `aggregateDriverRating` يَكتبُ
        // `rating_count` مع كلِّ تقييمٍ حقيقيّ، والبذرُ عند التوفير (`rating:
        // 5.0`) يُكتب **بلا عدّاد** — وهو ما تَستثنيه الدالّةُ من المتوسّطِ
        // صراحةً. فافتراضُ ٥٫٠ هنا كان يَفعلُ ما استثنته: يَعرضُ «٥٫٠ ★» لسائقٍ
        // لم يُقيّمه أحد، **ويَضربُه في عددِ المُنجَز في الفرز** — فسائقٌ أتمّ
        // ١٧ طلباً بلا تقييمٍ (٨٥) يَسبقُ من أتمّ ٢٠ بمتوسّطٍ حقيقيٍّ ٤٫٢ (٨٤)،
        // وقد تُسمّي بطاقةُ «الأفضل» من لم يُقيّمه أحد. (نفسُ عطلِ «تقييمك
        // ٤٫٩ ★» في ملفِّ العميلة.)
        // القاعدةُ صارت في موضعٍ واحد (`driver_rating.dart`) لأنّ سطحاً
        // ثالثاً — `admin_drivers_screen` — كان ما زال يَعرضُ ٥٫٠ لمن لم
        // يُقيّمه أحد، فوقَ «(٠ تقييم)» مباشرةً.
        final int ratingCount =
            int.tryParse('${driverData['rating_count'] ?? 0}') ?? 0;
        final double? avgRating =
            driverRatingOf(driverData['rating_avg'], ratingCount);

        stats.add({
          'id': driverId,
          'name': driverName,
          'completed': totalCompleted,
          'rating': avgRating,
          'rating_count': ratingCount,
          'phone': driverData['phone'] ?? '-',
          // **لا `status`.** كان هنا `driverData['status'] ?? 'offline'` —
          // المِفتاحُ الوحيدُ في المستودعِ الذي يَقرأُ حالةَ مستندِ السائق،
          // ولم يُعرَض ولا يُفرَزُ به ولا يُرشَّح: مِفتاحُ خريطةٍ ميّت،
          // وافتراضُه `offline` مفردةٌ **لا يَكتبُها كاتبٌ** — فكان القارئُ
          // الظاهريُّ يُوهِمُ أنّ للحقلِ معنًى متّفَقاً عليه.
        });
      }

      // الفرز: المُقيَّمون أوّلاً بـ(المتوسّط × المُنجَز)، ثمّ غيرُ المُقيَّمين
      // بعددِ المُنجَزِ وحدَه — فلا رقمٌ مُختلَقٌ يَرفعُ أحداً فوق مَن قُيِّم.
      stats.sort((a, b) {
        final ar = a['rating'] as double?;
        final br = b['rating'] as double?;
        if (ar == null && br == null) {
          return (b['completed'] as int).compareTo(a['completed'] as int);
        }
        if (ar == null) return 1;
        if (br == null) return -1;
        return (br * (b['completed'] as int))
            .compareTo(ar * (a['completed'] as int));
      });

      if (mounted) {
        setState(() {
          _staffStats = stats;
          _isLoading = false;
          _loadFailed = false;
        });
      }
    } catch (e) {
      // لا تُبقِ الشاشة على سبينر لانهائي عند أي خطأ (فهرس مفقود/اتصال) —
      // ونعلن الفشل بدل قائمة فارغة تُوهم أن لا سائقين.
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadFailed = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('فشل تحميل بيانات الأداء: $e'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF1F5F9),
        appBar: AppBar(
          title: Text("كفاءة وأداء الكوادر", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 18)),
          backgroundColor: const Color(0xFF660033),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF1E293B)))
          : _loadFailed
            ? _buildErrorState()
            : RefreshIndicator(
                // سحب للتحديث — لم يكن للشاشة أي وسيلة تحديث سوى إعادة فتحها.
                onRefresh: _calculatePerformance,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(20),
                  children: [
                    _buildEliteHeroSection(),
                    const SizedBox(height: 25),
                    Text("ترتيب الكفاءة", style: GoogleFonts.tajawal(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 15),
                    if (_staffStats.isEmpty)
                      // حالة فارغة صريحة — كي لا تُقرأ القائمة الخالية كعطل.
                      Padding(
                        padding: const EdgeInsets.only(top: 40),
                        child: Center(
                          child: Text("لا يوجد سائقون مسجّلون بعد",
                              style: GoogleFonts.tajawal(color: Colors.grey)),
                        ),
                      )
                    else
                      ..._staffStats.asMap().entries.map((entry) => _buildStaffCard(entry.value, entry.key + 1)),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_off_rounded, size: 60, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text("تعذّر تحميل بيانات الأداء",
              style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () {
              setState(() => _isLoading = true);
              _calculatePerformance();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF660033),
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.refresh_rounded),
            label: Text("إعادة المحاولة", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildEliteHeroSection() {
    if (_staffStats.isEmpty) return const SizedBox.shrink();
    final top = _staffStats.first;

    return Container(
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF660033), Color(0xFF8E2B5C)]),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: const Color(0xFF660033).withValues(alpha: 0.3), blurRadius: 15, offset: const Offset(0, 8))],
      ),
      child: Column(
        children: [
          const Icon(Icons.workspace_premium, color: Colors.amber, size: 50),
          const SizedBox(height: 15),
          Text("نجم الشهر الحالي", style: GoogleFonts.tajawal(color: Colors.white70, fontSize: 14)),
          Text(top['name'], style: GoogleFonts.tajawal(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildModernMiniStat("مهام", "${top['completed']}"),
              const SizedBox(width: 20),
              _buildModernMiniStat(
                  "التقييم",
                  top['rating'] == null
                      ? "—"
                      : "${(top['rating'] as double).toStringAsFixed(1)} ★"),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModernMiniStat(String label, String value) {
    return Column(
      children: [
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
        Text(label, style: const TextStyle(color: Colors.white60, fontSize: 10)),
      ],
    );
  }

  Widget _buildStaffCard(Map<String, dynamic> staff, int rank) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10)],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: rank <= 3 ? Colors.amber.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Text("$rank", style: TextStyle(fontWeight: FontWeight.bold, color: rank <= 3 ? Colors.orange : Colors.grey)),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(staff['name'], style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
                Text(staff['phone'], style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                children: [
                  const Icon(Icons.star, color: Colors.amber, size: 14),
                  const SizedBox(width: 4),
                  Text(
                      staff['rating'] == null
                          ? "—"
                          : (staff['rating'] as double).toStringAsFixed(1),
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              Text("${staff['completed']} مهمة", style: const TextStyle(fontSize: 10, color: Colors.blueGrey)),
            ],
          ),
        ],
      ),
    );
  }
}
