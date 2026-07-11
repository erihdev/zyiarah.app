import 'package:zyiarah/services/zyiarah_messaging_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zyiarah/services/store_service.dart';
import 'package:zyiarah/widgets/shimmer_loading.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:lottie/lottie.dart';
import 'package:zyiarah/screens/order_success_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:zyiarah/utils/global_error_handler.dart';


class ZyiarahStoreScreen extends StatefulWidget {
  const ZyiarahStoreScreen({super.key});

  @override
  State<ZyiarahStoreScreen> createState() => _ZyiarahStoreScreenState();
}

class _ZyiarahStoreScreenState extends State<ZyiarahStoreScreen> {
  final ZyiarahStoreService _storeService = ZyiarahStoreService();
  final Map<String, int> _cart = {};
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _addToCart(StoreProduct product) {
    setState(() {
      _cart[product.id] = (_cart[product.id] ?? 0) + 1;
    });
  }



  void _showCart() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (ctx) => _CartSheet(
        cart: _cart,
        storeService: _storeService,
        onSubmitted: (orderCode) {
          setState(() => _cart.clear());
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => ZyiarahOrderSuccessScreen(
                orderCode: orderCode,
                title: 'تم إرسال طلبك للإدارة!',
                subtitle:
                    'طلبك الآن بانتظار موافقة الإدارة. سنُشعرك فور اعتماده لإتمام الدفع وتجهيز منتجاتك.',
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Directionality(
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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: TextField(
                controller: _searchController,
                onChanged: (v) => setState(() => _searchQuery = v.trim()),
                decoration: InputDecoration(
                  hintText: 'ابحث عن منتج...',
                  hintStyle: GoogleFonts.tajawal(color: Colors.grey[400]),
                  prefixIcon: const Icon(Icons.search, color: Colors.grey),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFF5D1B5E)),
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
                  if (snapshot.hasError) {
                    return Center(
                      child: Text('تعذّر تحميل المتجر، تحقّق من الاتصال',
                          style: GoogleFonts.tajawal(color: Colors.grey)),
                    );
                  }
                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return _buildEmptyState();
                  }

                  final allProducts = snapshot.data!;
                  final products = _searchQuery.isEmpty
                      ? allProducts
                      : allProducts
                          .where((p) =>
                              p.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                              p.description.toLowerCase().contains(_searchQuery.toLowerCase()))
                          .toList();

                  if (products.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.search_off_rounded, size: 56, color: Colors.grey[300]),
                          const SizedBox(height: 12),
                          Text('لا توجد نتائج لـ "$_searchQuery"',
                              style: GoogleFonts.tajawal(color: Colors.grey, fontSize: 14)),
                        ],
                      ),
                    );
                  }

                  return GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 0.65,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                    ),
                    itemCount: products.length,
                    itemBuilder: (context, index) {
                      return TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: 1),
                        duration: const Duration(milliseconds: 600),
                        curve: Curves.easeOut,
                        builder: (context, value, child) {
                          return Opacity(
                            opacity: value,
                            child: Transform.translate(
                              offset: Offset(0, 20 * (1 - value)),
                              child: child,
                            ),
                          );
                        },
                        child: _ProductCard(
                          product: products[index],
                          onAdd: () => _addToCart(products[index]),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Lottie.network(
            'https://lottie.host/9972352b-4780-4545-8f65-021199346747/XJzQitkR2f.json', // Search/Empty anim
            height: 200,
          ),
          const SizedBox(height: 10),
          Text('المتجر قيد التعبئة، سيتم توفير المنتجات قريباً', style: GoogleFonts.tajawal(fontSize: 16, color: Colors.grey, fontWeight: FontWeight.bold)),
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
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF5D1B5E).withValues(alpha: 0.08), 
            blurRadius: 20, 
            offset: const Offset(0, 8)
          )
        ],
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
                  child: Center(child: Icon(Icons.shopping_bag_outlined, color: Colors.grey.shade300)),
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
                    Text('${product.price} ر.س', style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF5D1B5E))),
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
  final void Function(String orderCode) onSubmitted;

  const _CartSheet({
    required this.cart,
    required this.storeService,
    required this.onSubmitted,
  });

  @override
  State<_CartSheet> createState() => _CartSheetState();
}

class _CartSheetState extends State<_CartSheet> {
  bool _isSubmitting = false;
  bool _agreeToTerms = false;


  void _checkout(List<StoreProduct> products) async {
    if (!_agreeToTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى الموافقة على شروط المتجر')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final items = widget.cart.entries
          .map((entry) {
            // (A3) تجنّب StateError: تخطّى أي منتج في السلة لم يعد موجوداً/مخفياً بدل الانهيار
            final matches = products.where((p) => p.id == entry.key);
            if (matches.isEmpty) return null;
            final product = matches.first;
            return {
              'id': entry.key,
              'name': product.name,
              'quantity': entry.value,
              'price': product.price,
            };
          })
          .whereType<Map<String, dynamic>>()
          .toList();

      if (items.isEmpty) {
        if (mounted) {
          setState(() => _isSubmitting = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('بعض المنتجات لم تعد متاحة، يرجى تحديث السلة')),
          );
        }
        return;
      }
      final double total = items.fold(
        0.0, (acc, item) => acc + (item['price'] as double) * (item['quantity'] as int));

      // ─────────────────────────────────────────────────────────
      // المتجر: إرسال الطلب لموافقة الإدارة أولاً (بدون دفع).
      // بعد الاعتماد، يُتمّ العميل الدفع عبر StorePaymentScreen.
      // ─────────────────────────────────────────────────────────
      final orderCode = await widget.storeService.createStoreOrder(
        items: items,
        totalAmount: total,
      );

      if (!mounted) return;
      if (orderCode == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('يجب تسجيل الدخول لإتمام الطلب')),
        );
        setState(() => _isSubmitting = false);
        return;
      }

      final user = FirebaseAuth.instance.currentUser;
      // إشعار الإدارة بطلب جديد بانتظار الموافقة — non-fatal
      ZyiarahMessagingService().notifyNewOrder({
        'code': orderCode,
        'client_name': user?.displayName ?? 'عميل زيارة',
        'client_phone': user?.phoneNumber ?? 'غير متوفر',
        'service_type': 'طلب متجر (بانتظار الموافقة)',
        'amount': total,
        'zone': 'طلب عبر المتجر',
        'date_time': DateTime.now().toString().split('.')[0],
        'worker_count': 0,
        'coupon': 'لا يوجد',
      }, customerEmail: user?.email).catchError((_) {});

      if (!mounted) return;
      // أغلق الـ Sheet ثم نقّل عبر callback الـ parent
      Navigator.pop(context);
      widget.onSubmitted(orderCode);

    } catch (e) {
      GlobalErrorHandler.handleError(e);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
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
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3E8F4),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF5D1B5E).withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: Color(0xFF5D1B5E), size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'سيُراجع طلبك من قِبل الإدارة، وفور الموافقة سنُشعرك لإتمام الدفع بالطريقة التي تناسبك (تمارا / بطاقة / عند الاستلام).',
                          style: GoogleFonts.tajawal(fontSize: 12, height: 1.5, color: const Color(0xFF5D1B5E), fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 15),
                _buildTermsAndConditions(),
                const SizedBox(height: 20),
                SizedBox(
                  height: 55,
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: (_isSubmitting || !_agreeToTerms) ? null : () => _checkout(snapshot.data!),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _agreeToTerms ? const Color(0xFF5D1B5E) : Colors.grey.shade300,
                      foregroundColor: Colors.white,
                    ),
                    child: _isSubmitting ? const CircularProgressIndicator(color: Colors.white) : const Text('إرسال طلب للموافقة الإدارة'),
                  ),
                ),
              ],
            );
          },
      ),
    );
  }

  Widget _buildTermsAndConditions() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _agreeToTerms ? const Color(0xFF5D1B5E) : Colors.grey.shade200),
      ),
      child: CheckboxListTile(
        value: _agreeToTerms,
        onChanged: (val) => setState(() => _agreeToTerms = val ?? false),
        activeColor: const Color(0xFF5D1B5E),
        title: Text(
          "أوافق على شروط المتجر وسياسة الخصوصية",
          style: GoogleFonts.tajawal(fontSize: 12, fontWeight: FontWeight.bold),
        ),
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
      ),
    );
  }
}
