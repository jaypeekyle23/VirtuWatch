import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'skeleton_box.dart';

/// Which profile layout [ProfileSkeleton] should imitate.
enum ProfileSkeletonKind {
  /// Customer profile: style chips, wrist-measurement card, saved-watches card.
  customer,

  /// Merchant / admin profile: role badge and an account-info card.
  account,
}

/// Loading placeholder shared by the customer, merchant and admin profile
/// tabs. They all share the same header (avatar, name, email, Edit Profile
/// button) and the same menu tiles + Log Out button, and differ only in the
/// middle section, so one widget covers all three.
class ProfileSkeleton extends StatelessWidget {
  final ProfileSkeletonKind kind;

  /// How many menu rows the real screen has (customer 7, merchant 5, admin 4).
  final int menuItems;

  const ProfileSkeleton({
    super.key,
    required this.kind,
    required this.menuItems,
  });

  static const _round = BorderRadius.all(Radius.circular(40));

  static Widget _card({required Widget child, double padding = 16}) =>
      Container(
        width: double.infinity,
        padding: EdgeInsets.all(padding),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: child,
      );

  Widget _middle() {
    if (kind == ProfileSkeletonKind.account) {
      // Four label / value rows: name, email, role, created date.
      return _card(
        child: Column(
          children: List.generate(
            4,
            (i) => Padding(
              padding: EdgeInsets.only(bottom: i == 3 ? 0 : 12),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  SkeletonBox(width: 80, height: 13),
                  SkeletonBox(width: 120, height: 13),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        const Align(
          alignment: Alignment.centerLeft,
          child: SkeletonBox(width: 130, height: 11),
        ),
        const SizedBox(height: 8),
        const Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SkeletonBox(width: 76, height: 30, borderRadius: _round),
              SkeletonBox(width: 64, height: 30, borderRadius: _round),
              SkeletonBox(width: 88, height: 30, borderRadius: _round),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _card(
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 140, height: 11),
              SizedBox(height: 10),
              SkeletonBox(width: 90, height: 24),
              SizedBox(height: 12),
              SkeletonBox(
                width: double.infinity,
                height: 40,
                borderRadius: _round,
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _card(
          child: const Row(
            children: [
              SkeletonBox(width: 56, height: 56),
              SizedBox(width: 8),
              SkeletonBox(width: 56, height: 56),
              SizedBox(width: 8),
              SkeletonBox(width: 56, height: 56),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAccount = kind == ProfileSkeletonKind.account;

    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const SkeletonBox(width: 72, height: 72, borderRadius: _round),
          const SizedBox(height: 12),
          const SkeletonBox(width: 140, height: 18),
          const SizedBox(height: 8),
          const SkeletonBox(width: 180, height: 13),
          if (isAccount) ...[
            const SizedBox(height: 10),
            const SkeletonBox(width: 80, height: 22, borderRadius: _round),
          ],
          const SizedBox(height: 12),
          const SkeletonBox(width: 110, height: 40, borderRadius: _round),
          SizedBox(height: isAccount ? 24 : 20),
          _middle(),
          const SizedBox(height: 20),
          for (var i = 0; i < menuItems; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _card(
                padding: 14,
                child: const Row(
                  children: [
                    SkeletonBox(width: 20, height: 20, borderRadius: _round),
                    SizedBox(width: 12),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: SkeletonBox(width: 150, height: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 10),
          const SkeletonBox(
            width: double.infinity,
            height: 52,
            borderRadius: _round,
          ),
        ],
      ),
    );
  }
}