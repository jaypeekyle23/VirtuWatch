import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// One watch scored against the current user's profile.
class WatchRecommendation {
  final String watchId;
  final Map<String, dynamic> data;

  /// 0.0–1.0, or null if the user hasn't saved a wrist measurement, or the
  /// watch has no lugToLugMm on file, so fit can't be evaluated.
  final double? fitScore;

  /// 0.0–1.0, or null if the user hasn't set any style preferences.
  final double? styleScore;

  /// 0.0–1.0. Combines whichever of [fitScore]/[styleScore] are available,
  /// re-weighted so missing signals don't drag the score down unfairly.
  /// Color matching isn't in this combination yet — see
  /// RecommendationService's class doc for why.
  final double combinedScore;

  final String fitNote;

  const WatchRecommendation({
    required this.watchId,
    required this.data,
    required this.fitScore,
    required this.styleScore,
    required this.combinedScore,
    required this.fitNote,
  });

  int get matchPercent => (combinedScore * 100).round();
}

/// Result of a recommendation request, bundling the ranked watches with
/// the profile data they were scored against — the UI uses the latter to
/// show "based on" chips and to prompt for missing profile info.
class RecommendationResult {
  final List<WatchRecommendation> recommendations;
  final double? wristWidthMm;
  final List<String> stylePreferences;

  /// The user's saved budget range. Not part of the match score — it's a
  /// hard affordability check, not a fit/style preference — but the UI
  /// uses it to label each watch as within/over/under budget.
  final double budgetMin;
  final double budgetMax;

  const RecommendationResult({
    required this.recommendations,
    required this.wristWidthMm,
    required this.stylePreferences,
    required this.budgetMin,
    required this.budgetMax,
  });
}

/// Ranks the watch catalog against a user's profile.
///
/// Per the capstone documentation (FR-09), the combined score should
/// blend fit, color, and style matching. Color matching isn't implemented
/// yet — the watch catalog currently has no color field to compare a
/// user's scanned outfit colors against (only style, material, and
/// dimensions). Until a watch color field exists, this engine combines
/// only fit and style, re-weighted between the two so the ranking still
/// makes sense with the signals actually available. When a color field
/// is added, color matching should slot in at roughly 0.3 of the total
/// weight (fit 0.5, color 0.3, style 0.2), following the same
/// weighted-average pattern used below.
class RecommendationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Base weights, out of 1.0, between the two signals currently
  // available. Fit is weighted highest since it's the one hard physical
  // constraint (an ill-fitting watch is a worse recommendation than an
  // off-style one); style is a softer preference.
  static const double _fitWeight = 0.5;
  static const double _styleWeight = 0.2;

  // How many mm of lug-to-lug vs wrist-width difference is treated as
  // the edge of "still fits reasonably" before the fit score hits zero.
  static const double _fitToleranceMm = 15;

  Future<RecommendationResult> getRecommendations() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const RecommendationResult(
        recommendations: [],
        wristWidthMm: null,
        stylePreferences: [],
        budgetMin: 5000,
        budgetMax: 50000,
      );
    }

    final userDoc = await _firestore.collection('users').doc(uid).get();
    final userData = userDoc.data() ?? {};
    final wristWidthMm = (userData['wristWidthMm'] as num?)?.toDouble();
    final stylePreferences =
        (userData['stylePreferences'] as List?)?.cast<String>() ?? [];
    final budgetMin = (userData['budgetMin'] as num?)?.toDouble() ?? 5000;
    final budgetMax = (userData['budgetMax'] as num?)?.toDouble() ?? 50000;

    final watchesSnapshot = await _firestore
        .collection('watches')
        .where('listedInCatalog', isEqualTo: true)
        .get();

    final scored = watchesSnapshot.docs.map((doc) {
      return _score(
        watchId: doc.id,
        data: doc.data(),
        wristWidthMm: wristWidthMm,
        stylePreferences: stylePreferences,
      );
    }).toList()
      ..sort((a, b) => b.combinedScore.compareTo(a.combinedScore));

    return RecommendationResult(
      recommendations: scored,
      wristWidthMm: wristWidthMm,
      stylePreferences: stylePreferences,
      budgetMin: budgetMin,
      budgetMax: budgetMax,
    );
  }

  WatchRecommendation _score({
    required String watchId,
    required Map<String, dynamic> data,
    required double? wristWidthMm,
    required List<String> stylePreferences,
  }) {
    final lugToLugMm = (data['lugToLugMm'] as num?)?.toDouble();
    final styleCategory = data['styleCategory'] as String?;

    double? fitScore;
    String fitNote;
    if (wristWidthMm == null) {
      fitNote = 'Add your wrist measurement for fit-based ranking';
    } else if (lugToLugMm == null) {
      fitNote = 'Fit info unavailable for this watch';
    } else {
      final diff = lugToLugMm - wristWidthMm;
      fitScore = (1 - (diff.abs() / _fitToleranceMm)).clamp(0.0, 1.0);
      if (diff.abs() <= 3) {
        fitNote = 'Great fit for your ${wristWidthMm.toStringAsFixed(0)}mm wrist';
      } else if (diff > 0) {
        fitNote = 'Runs a bit large for your ${wristWidthMm.toStringAsFixed(0)}mm wrist';
      } else {
        fitNote = 'Runs a bit small for your ${wristWidthMm.toStringAsFixed(0)}mm wrist';
      }
    }

    double? styleScore;
    if (stylePreferences.isNotEmpty && styleCategory != null) {
      styleScore = stylePreferences
              .any((s) => s.toLowerCase() == styleCategory.toLowerCase())
          ? 1.0
          : 0.0;
    }

    // Weighted average over whichever signals are actually available,
    // re-normalized so a missing signal doesn't just get treated as a
    // zero (which would unfairly tank every score while wrist/style data
    // is still incomplete for a user).
    double weightedSum = 0;
    double totalWeight = 0;
    if (fitScore != null) {
      weightedSum += fitScore * _fitWeight;
      totalWeight += _fitWeight;
    }
    if (styleScore != null) {
      weightedSum += styleScore * _styleWeight;
      totalWeight += _styleWeight;
    }
    final combinedScore = totalWeight == 0 ? 0.5 : weightedSum / totalWeight;

    return WatchRecommendation(
      watchId: watchId,
      data: data,
      fitScore: fitScore,
      styleScore: styleScore,
      combinedScore: combinedScore,
      fitNote: fitNote,
    );
  }
}