import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class ZyiarahShimmer extends StatelessWidget {
  final double width;
  final double height;
  final ShapeBorder shapeBorder;

  const ZyiarahShimmer.rectangular({
    super.key,
    this.width = double.infinity,
    required this.height,
  }) : shapeBorder = const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12)));

  const ZyiarahShimmer.circular({
    super.key,
    required this.width,
    required this.height,
    this.shapeBorder = const CircleBorder(),
  });

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey[200]!,
      highlightColor: Colors.grey[100]!,
      child: Container(
        width: width,
        height: height,
        decoration: ShapeDecoration(
          color: Colors.grey[300]!,
          shape: shapeBorder,
        ),
      ),
    );
  }

  /// يولد قائمة من الهياكل (Skeletons) لمحاكاة التحميل في القوائم
  static Widget buildListSkeleton({int count = 5}) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: count,
      itemBuilder: (context, index) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 10, horizontal: 20),
        child: Row(
          children: [
            ZyiarahShimmer.circular(width: 50, height: 50),
            SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ZyiarahShimmer.rectangular(height: 15, width: 150),
                  SizedBox(height: 10),
                  ZyiarahShimmer.rectangular(height: 10),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
