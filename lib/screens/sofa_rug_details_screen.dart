import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:zyiarah/screens/location_picker_screen.dart';
import 'package:zyiarah/screens/payment_summary_screen.dart';

class SofaRugCleaningDetailsScreen extends StatefulWidget {
  final String serviceName;
  const SofaRugCleaningDetailsScreen({super.key, required this.serviceName});

  @override
  State<SofaRugCleaningDetailsScreen> createState() => _SofaRugCleaningDetailsScreenState();
}

class _SofaRugCleaningDetailsScreenState extends State<SofaRugCleaningDetailsScreen> {
  double _sofaMeters = 0;
  double _rugMeters = 0;
  bool _isOutsideRing = false;
  bool _isLoading = true;

  // أسعار افتراضية (سيتم تحديثها من Firestore)
  double _sofaPriceInside = 35.0;
  double _sofaPriceOutside = 39.0;
  double _rugPriceInside = 15.0;
  double _rugPriceOutside = 17.0;
  double _outsideDeposit = 50.0;

  @override
  void initState() {
    super.initState();
    _fetchPricing();
  }

  Future<void> _fetchPricing() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('system_configs').doc('main_settings').get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        setState(() {
          _sofaPriceInside = (data['sofa_price_inside'] ?? 35.0).toDouble();
          _sofaPriceOutside = (data['sofa_price_outside'] ?? 39.0).toDouble();
          _rugPriceInside = (data['rug_price_inside'] ?? 15.0).toDouble();
          _rugPriceOutside = (data['rug_price_outside'] ?? 17.0).toDouble();
          _outsideDeposit = (data['outside_deposit'] ?? 50.0).toDouble();
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  double get subTotal {
    double sofaPrice = _isOutsideRing ? _sofaPriceOutside : _sofaPriceInside;
    double rugPrice = _isOutsideRing ? _rugPriceOutside : _rugPriceInside;
    return (_sofaMeters * sofaPrice) + (_rugMeters * rugPrice);
  }

  double get vat => subTotal * 0.15;
  double get totalAmount => subTotal + vat;

  void _handleNext() async {
    if (subTotal <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("يرجى إدخال الأمتار أولاً")));
      return;
    }

    final dynamic result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LocationPickerScreen(
          serviceName: widget.serviceName,
          amount: totalAmount,
          zoneName: _isOutsideRing ? "خارج الداير" : "داخل الداير",
        ),
      ),
    );

    if (result == null || result is! Map<String, dynamic>) return;

    final GeoPoint selectedLocation = result['location'];

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PaymentSummaryScreen(
            serviceName: "${widget.serviceName} (${_isOutsideRing ? 'خارج' : 'داخل'} الداير)",
            amount: totalAmount,
            location: selectedLocation,
          ),
        ),
      ).then((success) {
        if (success == true && mounted) Navigator.pop(context, true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.serviceName),
        backgroundColor: const Color(0xFF5D1B5E),
        foregroundColor: Colors.white,
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: _isLoading 
          ? const Center(child: CircularProgressIndicator()) 
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildZoneToggle(),
                  const SizedBox(height: 30),
                  _buildInputRow("أمتار الكنب", _sofaMeters, (val) => setState(() => _sofaMeters = val), _isOutsideRing ? _sofaPriceOutside : _sofaPriceInside),
                  const SizedBox(height: 20),
                  _buildInputRow("أمتار الزل (السجاد)", _rugMeters, (val) => setState(() => _rugMeters = val), _isOutsideRing ? _rugPriceOutside : _rugPriceInside),
                  const SizedBox(height: 40),
                  if (_isOutsideRing) _buildDepositNotice(),
                  const SizedBox(height: 20),
                  _buildSummaryCard(),
                  const SizedBox(height: 30),
                  _buildNextButton(),
                ],
              ),
            ),
      ),
    );
  }

  Widget _buildZoneToggle() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          _buildToggleItem("داخل الداير", !_isOutsideRing, () => setState(() => _isOutsideRing = false)),
          _buildToggleItem("خارج الداير", _isOutsideRing, () => setState(() => _isOutsideRing = true)),
        ],
      ),
    );
  }

  Widget _buildToggleItem(String title, bool isSelected, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF5D1B5E) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              title, 
              style: TextStyle(color: isSelected ? Colors.white : Colors.grey[600], fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInputRow(String label, double value, Function(double) onChanged, double pricePerMeter) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text("$pricePerMeter ر.س / للمتر", style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _buildCounterBtn(Icons.remove, () => value > 0 ? onChanged(value - 1) : null),
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 10),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(12)),
                child: Center(child: Text("${value.toInt()}", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
              ),
            ),
            _buildCounterBtn(Icons.add, () => onChanged(value + 1)),
          ],
        ),
      ],
    );
  }

  Widget _buildCounterBtn(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: const Color(0xFF5D1B5E).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, color: const Color(0xFF5D1B5E)),
      ),
    );
  }

  Widget _buildDepositNotice() {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: Colors.orange[50], borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.orange[200]!)),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Colors.orange),
          const SizedBox(width: 10),
          Expanded(child: Text("المناطق خارج الداير تتطلب عربوناً وقدره ${_outsideDeposit.toInt()} ر.س", style: const TextStyle(fontSize: 13, color: Colors.orange, fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }

  Widget _buildSummaryCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.grey[200]!)),
      child: Column(
        children: [
          _summaryRow("إجمالي الأمتار", "${(_sofaMeters + _rugMeters).toInt()} م"),
          const Divider(),
          _summaryRow("المبلغ الأساسي", "${subTotal.toStringAsFixed(2)} ر.س"),
          _summaryRow("ضريبة القيمة المضافة (15%)", "${vat.toStringAsFixed(2)} ر.س"),
          const Divider(),
          _summaryRow("الإجمالي النهائي", "${totalAmount.toStringAsFixed(2)} ر.س", isBold: true),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: isBold ? 16 : 14, fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
          Text(value, style: TextStyle(fontSize: isBold ? 18 : 14, fontWeight: isBold ? FontWeight.bold : FontWeight.bold, color: isBold ? const Color(0xFF5D1B5E) : Colors.black)),
        ],
      ),
    );
  }

  Widget _buildNextButton() {
    return SizedBox(
      width: double.infinity,
      height: 55,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF5D1B5E), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
        onPressed: _handleNext,
        child: const Text("متابعة لاختيار الموقع", style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white)),
      ),
    );
  }
}
