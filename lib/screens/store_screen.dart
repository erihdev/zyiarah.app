import 'package:flutter/material.dart';
import 'package:zyiarah/services/store_service.dart';
import 'package:zyiarah/widgets/shimmer_loading.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';

class ZyiarahStoreScreen extends StatefulWidget {
  const ZyiarahStoreScreen({super.key});

  @override
  State<ZyiarahStoreScreen> createState() => _ZyiarahStoreScreenState();
}

class _ZyiarahStoreScreenState extends State<ZyiarahStoreScreen> {
  final ZyiarahStoreService _storeService = ZyiarahStoreService();
  final Map<String, int> _cart = {};

  void _addToCart(StoreProduct product) {
    setState(() {
      _cart[product.id] = (_cart[product.id] ?? 0) + 1;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم إضافة ${product.name} للسلة'), duration: const Duration(seconds: 1)),
    );
  }



  void _showCart() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => _CartSheet(cart: _cart, storeService: _storeService),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          title: Text('متجر الأدوات والتنظيف', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFF5D1B5E),
          foregroundColor: Colors.white,
          actions: [
            Stack(
              children: [
                IconButton(
                  onPressed: _showCart,
                  icon: const Icon(Icons.shopping_cart_outlined),
                ),
                if (_cart.isNotEmpty)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                      child: Text('${_cart.values.reduce((a, b) => a + b)}', style: const TextStyle(fontSize: 10, color: Colors.white)),
                    ),
                  ),
              ],
            ),
          ],
        ),
        body: Column(
          children: [
            Container(
              width: double.infinity,
              height: 180,
              decoration: const BoxDecoration(
                image: DecorationImage(
                  image: AssetImage('assets/images/store.png'),
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                ),
              ),
              child: Container(
                color: Colors.black.withValues(alpha: 0.3),
                child: Center(
                  child: Text(
                    'أدوات النظافة الاحترافية',
                    style: GoogleFonts.tajawal(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      shadows: const [Shadow(color: Colors.black54, blurRadius: 10)],
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: StreamBuilder<List<StoreProduct>>(
                stream: _storeService.streamProducts(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 15,
                        crossAxisSpacing: 15,
                        childAspectRatio: 0.75,
                      ),
                      itemCount: 6,
                      itemBuilder: (context, index) => const ShimmerGridItem(),
                    );
                  }
                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return _buildEmptyState();
                  }

                  final products = snapshot.data!;
                  return GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 0.65,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                    ),
                    itemCount: products.length,
                    itemBuilder: (context, index) => _ProductCard(
                      product: products[index],
                      onAdd: () => _addToCart(products[index]),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.storefront_outlined, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 20),
          Text('المتجر قيد التعبئة، سيتم توفير المنتجات قريباً', style: GoogleFonts.tajawal(fontSize: 18, color: Colors.grey)),
        ],
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  final StoreProduct product;
  final VoidCallback onAdd;

  const _ProductCard({required this.product, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              child: CachedNetworkImage(
                imageUrl: product.imageUrl,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  color: Colors.grey.shade100,
                  child: const Center(child: CircularProgressIndicator()),
                ),
                errorWidget: (context, url, error) => Container(
                  color: Colors.grey[100], 
                  child: const Center(child: Icon(Icons.image_not_supported)),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('${product.price} ر.س', style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF2563EB))),
                    InkWell(
                      onTap: onAdd,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(color: const Color(0xFF5D1B5E), borderRadius: BorderRadius.circular(8)),
                        child: const Icon(Icons.add_shopping_cart, color: Colors.white, size: 18),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CartSheet extends StatefulWidget {
  final Map<String, int> cart;
  final ZyiarahStoreService storeService;
  const _CartSheet({required this.cart, required this.storeService});

  @override
  State<_CartSheet> createState() => _CartSheetState();
}

class _CartSheetState extends State<_CartSheet> {
  bool _isSubmitting = false;
  String _selectedPaymentMethod = 'cash_on_delivery';


  void _checkout(List<StoreProduct> products) async {
    setState(() => _isSubmitting = true);
    
    final items = widget.cart.entries.map((entry) {
      final product = products.firstWhere((p) => p.id == entry.key);
      return {
        'id': entry.key,
        'name': product.name,
        'quantity': entry.value,
        'price': product.price,
      };
    }).toList();

    double total = items.fold(0, (sum, item) => sum + (item['price'] as double) * (item['quantity'] as int));

    await widget.storeService.createStoreOrder(
      items: items, 
      totalAmount: total,
      paymentMethod: _selectedPaymentMethod,
    );
    
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إرسال طلبك للإدارة بنجاح!')));
      widget.cart.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: StreamBuilder<List<StoreProduct>>(
          stream: widget.storeService.streamProducts(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            
            final cartProducts = snapshot.data!.where((p) => widget.cart.containsKey(p.id)).toList();
            if (cartProducts.isEmpty) {
              return const SizedBox(height: 200, child: Center(child: Text('سلة التسوق فارغة')));
            }

            double total = 0;
            for (var p in cartProducts) {
              total += p.price * widget.cart[p.id]!;
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('سلة التسوق', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 20)),
                const SizedBox(height: 20),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: cartProducts.length,
                    itemBuilder: (context, index) {
                      final p = cartProducts[index];
                      return ListTile(
                        title: Text(p.name, style: const TextStyle(fontSize: 14)),
                        subtitle: Text('${p.price} ر.س x ${widget.cart[p.id]}'),
                        trailing: Text('${p.price * widget.cart[p.id]!} ر.س', style: const TextStyle(fontWeight: FontWeight.bold)),
                      );
                    },
                  ),
                ),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('المجموع الإجمالي', style: TextStyle(fontWeight: FontWeight.bold)),
                      Text('$total ر.س', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w900, fontSize: 18)),
                    ],
                  ),
                ),
                const Divider(),
                const Text('طريقة الدفع', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 10),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: _selectedPaymentMethod == 'cash_on_delivery' ? const Color(0xFF2563EB) : Colors.grey.shade200),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: RadioListTile(
                    value: 'cash_on_delivery',
                    // ignore: deprecated_member_use
                    groupValue: _selectedPaymentMethod,
                    // ignore: deprecated_member_use
                    onChanged: (val) => setState(() => _selectedPaymentMethod = val.toString()),
                    title: const Text('الدفع عند الاستلام', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    subtitle: const Text('الدفع كاش أو عبر الشبكة عند استلام المنتجات', style: TextStyle(fontSize: 11, color: Colors.grey)),
                    secondary: const Icon(Icons.money, color: Colors.green),
                    activeColor: const Color(0xFF2563EB),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.grey.shade200),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: RadioListTile(
                    value: 'online',
                    // ignore: deprecated_member_use
                    groupValue: _selectedPaymentMethod,
                    // ignore: deprecated_member_use
                    onChanged: (val) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('الدفع الإلكتروني سيتوفر قريباً')));
                    },
                    title: const Text('الدفع الإلكتروني (مدى / فيزا / تمارا)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey)),
                    secondary: const Icon(Icons.credit_card, color: Colors.grey),
                    activeColor: const Color(0xFF2563EB),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : () => _checkout(snapshot.data!),
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF5D1B5E), foregroundColor: Colors.white),
                    child: _isSubmitting ? const CircularProgressIndicator(color: Colors.white) : const Text('إرسال طلب لبموافقة الإدارة'),
                  ),
                ),
              ],
            );
          },
      ),
    );
  }
}
