import 'package:flutter/material.dart';
import 'luxe.dart';
import 'skeleton_box.dart';

/// Loading placeholder shaped like the merchant and admin profiles: the
/// header, one section, then [menuItems] menu rows. (The customer profile
/// has its own, since its middle sections differ.)
class ProfileSkeleton extends StatelessWidget {
  final int menuItems;

  const ProfileSkeleton({super.key, required this.menuItems});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Column(
        children: [
          const Row(
            children: [
              SkeletonBox(
                  width: 68,
                  height: 68,
                  borderRadius: BorderRadius.all(Radius.circular(34))),
              SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 140, height: 22),
                  SizedBox(height: 8),
                  SkeletonBox(width: 180, height: 12),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 20),
            decoration: kTopRule,
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 80, height: 10),
                SizedBox(height: 12),
                SkeletonBox(width: 200, height: 16),
              ],
            ),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < menuItems; i++)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: kTopRule,
              child: const Align(
                alignment: Alignment.centerLeft,
                child: SkeletonBox(width: 150, height: 14),
              ),
            ),
        ],
      ),
    );
  }
}