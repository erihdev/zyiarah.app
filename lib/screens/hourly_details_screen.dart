import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:zyiarah/screens/location_picker_screen.dart';
import 'package:zyiarah/screens/payment_summary_screen.dart';

class CleaningZone {
  final String name;
  final List<String> subAreas;
  final Map<int, double> prices;

  CleaningZone({required this.name, required this.subAreas, required this.prices});
}

class HourlyCleaningDetailsScreen extends StatefulWidget {
  final String serviceName;
  const HourlyCleaningDetailsScreen({super.key, required this.serviceName});

  @override
  State<HourlyCleaningDetailsScreen> createState() => _HourlyCleaningDetailsScreenState();
}

class _HourlyCleaningDetailsScreenState extends State<HourlyCleaningDetailsScreen> {
  int _selectedHours = 4;
  int? _selectedZoneIndex;
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));
  int _workerCount = 1;
  bool _isLoading = true;
  List<CleaningZone> _zones = [];

  @override
  void initState() {
    super.initState();
    _fetchZones();
  }

  Future<void> _fetchZones() async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection('hourly_zones').orderBy('rank').get();
      if (mounted) {
        setState(() {
          _zones = snapshot.docs.map((doc) {
            final data = doc.data();
            Map<int, double> prices = {};
            final pricesMap = data['prices'] as Map<String, dynamic>? ?? {};
            pricesMap.forEach((key, value) {
              int? h = int.tryParse(key);
              if (h != null) {
                prices[h] = (value as num).toDouble();
              }
            });
            return CleaningZone(
              name: data['name'] ?? '',
              subAreas: (data['subAreas'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
              prices: prices,
            );
          }).toList();
          
          // إضافة خيار خارج التغطية دائماً في النهاية
          _zones.add(CleaningZone(
            name: "غير مدرج / خارج التغطية",
            subAreas: [],
            prices: {},
          ));

          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  double get totalAmount {
    if (_selectedZoneIndex == null || _selectedZoneIndex! >= _zones.length - 1) return 0.0;
    double basePrice = _zones[_selectedZoneIndex!].prices[_selectedHours] ?? 0.0;
    return basePrice * _workerCount;
  }

  bool get isOutOfService => _selectedZoneIndex == _zones.length - 1;

  void _handleInitiateFlow() async {
    if (_selectedZoneIndex == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("يرجى اختيار المنطقة أولاً")),
      );
      return;
    }

    if (isOutOfService) return;

    final dynamic result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LocationPickerScreen(
          serviceName: widget.serviceName,
          hours: _selectedHours,
          serviceDate: _selectedDate,
          amount: totalAmount,
          zoneName: _zones[_selectedZoneIndex!].name,
          workerCount: _workerCount,
        ),
      ),
    );

    if (result == null || result is! Map<String, dynamic>) {
      return;
    }

    final GeoPoint selectedLocation = result['location'];

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PaymentSummaryScreen(
            serviceName: widget.serviceName,
            amount: totalAmount,
            location: selectedLocation,
            hours: _selectedHours,
            serviceDate: _selectedDate,
            workerCount: _workerCount,
          ),
        ),
      ).then((success) {
        if (success == true && mounted) {
          Navigator.pop(context, true);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("تفاصيل ${widget.serviceName}"),
        backgroundColor: const Color(0xFF5D1B5E),
        foregroundColor: Colors.white,
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: _isLoading 
            ? const Center(child: CircularProgressIndicator()) 
            : Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("اختر منطقتك", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  _buildZoneSelector(),
                  const SizedBox(height: 25),
                  if (!isOutOfService) ...[
                    const Text("حدد عدد الساعات", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 15),
                    _buildHourSelector(),
                    const SizedBox(height: 25),
                    const Text("عدد العاملات", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 15),
                    _buildWorkerSelector(),
                    const SizedBox(height: 25),
                    const Text("اختر التاريخ", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 15),
                    _buildDatePicker(),
                    const SizedBox(height: 30),
                    _buildSummaryCard(),
                    const SizedBox(height: 20),
                    _buildNextButton(),
                  ] else ...[
                    const SizedBox(height: 50),
                    _buildOutOfServiceMessage(),
                  ],
                ],
              ),
            ),
            if (_isLoading)
              Container(
                color: Colors.black.withValues(alpha: 0.3),
                child: const Center(
                  child: CircularProgressIndicator(color: Color(0xFF5D1B5E)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildZoneSelector() {
    return Column(
      children: List.generate(_zones.length, (index) {
        bool isSelected = _selectedZoneIndex == index;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: InkWell(
            onTap: () => setState(() => _selectedZoneIndex = index),
            child: Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF5D1B5E).withValues(alpha: 0.1) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? const Color(0xFF5D1B5E) : Colors.grey[300]!,
                  width: isSelected ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                    color: isSelected ? const Color(0xFF5D1B5E) : Colors.grey,
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _zones[index].name,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected ? const Color(0xFF5D1B5E) : Colors.black,
                          ),
                        ),
                        if (_zones[index].subAreas.isNotEmpty)
                          Text(
                            _zones[index].subAreas.join(" - "),
                            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildHourSelector() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [4, 5, 6, 8].map((h) {
        bool isSelected = _selectedHours == h;
        return InkWell(
          onTap: () => setState(() => _selectedHours = h),
          child: Container(
            width: 55,
            height: 55,
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFF5D1B5E) : Colors.grey[200],
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                "$h",
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.black,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
  
  Widget _buildWorkerSelector() {
    return Row(
      children: [1, 2].map((count) {
        bool isSelected = _workerCount == count;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(left: count == 1 ? 10 : 0, right: count == 2 ? 10 : 0),
            child: InkWell(
              onTap: () => setState(() => _workerCount = count),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF5D1B5E) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? const Color(0xFF5D1B5E) : Colors.grey[300]!,
                    width: 2,
                  ),
                ),
                child: Center(
                  child: Text(
                    count == 1 ? "عاملة واحدة" : "عاملتين", 
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.black,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildDatePicker() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(20),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: CalendarDatePicker(
          initialDate: _selectedDate,
          firstDate: DateTime.now(),
          lastDate: DateTime.now().add(const Duration(days: 30)),
          onDateChanged: (date) {
            setState(() => _selectedDate = date);
          },
        ),
      ),
    );
  }

  Widget _buildSummaryCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF5D1B5E).withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF5D1B5E).withValues(alpha: 0.1)),
      ),
      child: Column(
        children: [
          _buildSummaryRow("المنطقة", _selectedZoneIndex != null ? _zones[_selectedZoneIndex!].name : "لم يتم الاختيار"),
          const Divider(),
          _buildSummaryRow("عدد الساعات", "$_selectedHours ساعة"),
          const Divider(),
          _buildSummaryRow("عدد العاملات", _workerCount == 1 ? "عاملة واحدة" : "عاملتين"),
          const Divider(),
          _buildSummaryRow("التاريخ", "${_selectedDate.year}-${_selectedDate.month}-${_selectedDate.day}"),
          const Divider(),
          _buildSummaryRow("الإجمالي", "$totalAmount ر.س", isTotal: true),
          const SizedBox(height: 15),
          const Divider(),
          _buildNoticeRow(_workerCount == 1 ? "السعر للعاملة الواحدة يشمل التوصيل" : "السعر للعاملتين يشمل التوصيل"),
          _buildNoticeRow("لا يشمل مواد وأدوات التنظيف"),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: isTotal ? 17 : 15, fontWeight: isTotal ? FontWeight.bold : FontWeight.normal)),
          Text(value, style: TextStyle(fontSize: isTotal ? 19 : 15, fontWeight: FontWeight.bold, color: isTotal ? Colors.green[700] : Colors.black)),
        ],
      ),
    );
  }

  Widget _buildNoticeRow(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 16, color: Colors.blueGrey),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12, color: Colors.blueGrey))),
        ],
      ),
    );
  }

  Widget _buildOutOfServiceMessage() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.red[100]!),
      ),
      child: Column(
        children: [
          Icon(Icons.location_off, size: 60, color: Colors.red[300]),
          const SizedBox(height: 20),
          const Text(
            "نأسف، التطبيق لا يخدم مكانك حتى هذه اللحظة",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red),
          ),
          const SizedBox(height: 10),
          const Text(
            "نحن نعمل باستمرار على توسيع مناطق التغطية لدينا. شكراً لتفهمكم.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.black54),
          ),
        ],
      ),
    );
  }

  Widget _buildNextButton() {
    return SizedBox(
      width: double.infinity,
      height: 55,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF5D1B5E),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          elevation: 2,
        ),
        onPressed: _handleInitiateFlow,
        child: const Text("متابعة لاختيار الموقع", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      ),
    );
  }
}
