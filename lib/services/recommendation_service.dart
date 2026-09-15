import 'dart:math' show sqrt;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../constants/watch_colors.dart';
import '../utils/fit_scoring.dart';

/// One watch scored against the current user's profile.
class WatchRecommendation {
  final String watchId;
  final Map<String, dynamic> data;

  /// 0.0–1.0, or null if the user hasn't saved a wrist measurement, or the
  /// watch has no lugToLugMm on file, so fit can't be evaluated.
  final double? fitScore;

  /// 0.0–1.0, or null if the user hasn't set any style preferences.
  final double? styleScore;

  /// 0.0–1.0, or null if the user hasn't scanned an outfit yet, or the
  /// watch has no colorHex on file, so color can't be evaluated.
  final double? colorScore;

  /// 0.0–1.0. Combines whichever of [fitScore]/[styleScore]/[colorScore]
  /// are available, re-weighted so missing signals don't drag the score
  /// down unfairly.
  final double combinedScore;

  final String fitNote;

  /// Set only when the color match is notably good or notably poor —
  /// left null for middling matches so the UI isn't cluttered with a
  /// note for every watch.
  final String? colorNote;

  const WatchRecommendation({
    required this.watchId,
    required this.data,
    required this.fitScore,
    required this.styleScore,
    required this.colorScore,
    required this.combinedScore,
    required this.fitNote,
    required this.colorNote,
  });

  int get matchPercent => (combinedScore * 100).round();

  /// How many of the three signals (fit, color, style) actually
  /// contributed to [combinedScore]. A high percentage built from only
  /// one signal is real, but it's a much weaker claim than the same
  /// percentage built from all three — this exists so the UI and the
  /// chatbot can say so honestly instead of showing a bare "100%" that
  /// implies more confidence than the data actually supports.
  int get signalCount =>
      [fitScore, colorScore, styleScore].where((s) => s != null).length;

  /// Human-readable caveat for the match score, or null when all three
  /// signals are present (full confidence, no caveat needed).
  String? get confidenceNote {
    final activeSignals = [
      if (fitScore != null) 'fit',
      if (colorScore != null) 'color',
      if (styleScore != null) 'style',
    ];
    if (activeSignals.isEmpty) {
      return 'No match data yet — complete your profile for real scoring';
    }
    if (activeSignals.length == 3) return null;
    return 'Based on ${activeSignals.join(' & ')} only';
  }
}

/// Result of a recommendation request, bundling the ranked watches with
/// the profile data they were scored against — the UI uses the latter to
/// show "based on" chips and to prompt for missing profile info.
class RecommendationResult {
  final List<WatchRecommendation> recommendations;
  final double? wristWidthMm;
  final List<String> stylePreferences;
  final List<Map<String, dynamic>> outfitColors;

  /// The user's saved budget range. Not part of the match score — it's a
  /// hard affordability check, not a fit/style preference — but the UI
  /// uses it to label each watch as within/over/under budget.
  final double budgetMin;
  final double budgetMax;

  const RecommendationResult({
    required this.recommendations,
    required this.wristWidthMm,
    required this.stylePreferences,
    required this.outfitColors,
    required this.budgetMin,
    required this.budgetMax,
  });
}

/// Ranks the watch catalog against a user's profile.
///
/// Per the capstone documentation (FR-09), the combined score blends
/// fit, color, and style matching:
///  - Fit compares the user's wrist width against each watch's
///    lug-to-lug measurement.
///  - Color compares the user's scanned outfit colors (from
///    OutfitScanScreen) against each watch's primary color (from
///    watchColorPalette, set by the merchant on the add/edit watch
///    forms) using Euclidean RGB distance.
///  - Style checks whether a watch's styleCategory is among the user's
///    saved style preferences.
/// Any signal the user or watch is missing data for is left out of that
/// watch's score entirely (rather than counted as zero) and the
/// remaining weights are re-normalized, so an incomplete profile doesn't
/// unfairly tank every recommendation.
class RecommendationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Base weights, out of 1.0, when all three signals are available. Fit
  // is weighted highest since it's the one hard physical constraint (an
  // ill-fitting watch is a worse recommendation than an off-style or
  // off-color one); color and style are softer preferences.
  static const double _fitWeight = 0.5;
  static const double _colorWeight = 0.3;
  static const double _styleWeight = 0.2;

  // How many mm of lug-to-lug vs wrist-width difference is treated as
  // the edge of "still fits reasonably" before the fit score hits zero.
  // (Moved to lib/utils/fit_scoring.dart as `fitToleranceMm` so ChatService
  // can share the exact same rule — kept here only as a doc pointer.)

  // Euclidean distance between pure black and pure white in RGB space —
  // the maximum possible distance between two colors, used to normalize
  // color distance into a 0.0–1.0 similarity score.
  static const double _maxRgbDistance = 441.67; // sqrt(255^2 * 3)

  /// Loads the current user's profile fields relevant to scoring. Shared
  /// by [getRecommendations] (scoring the whole catalog) and [scoreWatch]
  /// (scoring a single watch, e.g. for the detail screen) so both stay
  /// consistent with exactly the same profile data.
  Future<
      ({
        double? wristWidthMm,
        List<String> stylePreferences,
        List<Map<String, dynamic>> outfitColors,
        double budgetMin,
        double budgetMax,
      })> _loadProfile(String uid) async {
    final userDoc = await _firestore.collection('users').doc(uid).get();
    final userData = userDoc.data() ?? {};
    return (
      wristWidthMm: (userData['wristWidthMm'] as num?)?.toDouble(),
      stylePreferences:
          (userData['stylePreferences'] as List?)?.cast<String>() ?? [],
      outfitColors: (userData['outfitColors'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [],
      budgetMin: (userData['budgetMin'] as num?)?.toDouble() ?? 5000,
      budgetMax: (userData['budgetMax'] as num?)?.toDouble() ?? 50000,
    );
  }

  /// Scores a single watch against the current user's profile — used by
  /// [WatchDetailScreen] to show a match percentage without pulling the
  /// entire catalog. Returns a zero-signal [WatchRecommendation] (no fit/
  /// color/style data) when no user is signed in, same as
  /// [getRecommendations] would for that watch.
  Future<WatchRecommendation> scoreWatch({
    required String watchId,
    required Map<String, dynamic> data,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return _score(
        watchId: watchId,
        data: data,
        wristWidthMm: null,
        stylePreferences: const [],
        outfitColors: const [],
      );
    }

    final profile = await _loadProfile(uid);
    return _score(
      watchId: watchId,
      data: data,
      wristWidthMm: profile.wristWidthMm,
      stylePreferences: profile.stylePreferences,
      outfitColors: profile.outfitColors,
    );
  }

  Future<RecommendationResult> getRecommendations() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const RecommendationResult(
        recommendations: [],
        wristWidthMm: null,
        stylePreferences: [],
        outfitColors: [],
        budgetMin: 5000,
        budgetMax: 50000,
      );
    }

    final profile = await _loadProfile(uid);
    final wristWidthMm = profile.wristWidthMm;
    final stylePreferences = profile.stylePreferences;
    final outfitColors = profile.outfitColors;
    final budgetMin = profile.budgetMin;
    final budgetMax = profile.budgetMax;

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
        outfitColors: outfitColors,
      );
    }).toList()
      ..sort((a, b) => b.combinedScore.compareTo(a.combinedScore));

    return RecommendationResult(
      recommendations: scored,
      wristWidthMm: wristWidthMm,
      stylePreferences: stylePreferences,
      outfitColors: outfitColors,
      budgetMin: budgetMin,
      budgetMax: budgetMax,
    );
  }

  WatchRecommendation _score({
    required String watchId,
    required Map<String, dynamic> data,
    required double? wristWidthMm,
    required List<String> stylePreferences,
    required List<Map<String, dynamic>> outfitColors,
  }) {
    final lugToLugMm = (data['lugToLugMm'] as num?)?.toDouble();
    final styleCategory = data['styleCategory'] as String?;
    final colorHex = data['colorHex'] as String?;

    double? fitScore;
    String fitNote;
    if (wristWidthMm == null) {
      fitNote = 'Add your wrist measurement for fit-based ranking';
    } else if (lugToLugMm == null) {
      fitNote = 'Fit info unavailable for this watch';
    } else {
      final fit = scoreFit(wristWidthMm: wristWidthMm, lugToLugMm: lugToLugMm);
      fitScore = fit.score;
      fitNote = fit.note;
    }

    double? styleScore;
    if (stylePreferences.isNotEmpty && styleCategory != null) {
      styleScore = stylePreferences
              .any((s) => s.toLowerCase() == styleCategory.toLowerCase())
          ? 1.0
          : 0.0;
    }

    double? colorScore;
    String? colorNote;
    if (outfitColors.isNotEmpty && colorHex != null) {
      final (watchR, watchG, watchB) = hexToRgb(colorHex);
      double weightedSimilarity = 0;
      double weightTotal = 0;
      for (final entry in outfitColors) {
        final hex = entry['hex'] as String?;
        final percentage = (entry['percentage'] as num?)?.toDouble();
        if (hex == null || percentage == null || percentage <= 0) continue;

        final (r, g, b) = hexToRgb(hex);
        final dr = (watchR - r).toDouble();
        final dg = (watchG - g).toDouble();
        final db = (watchB - b).toDouble();
        final distance = sqrt(dr * dr + dg * dg + db * db);
        final similarity = (1 - distance / _maxRgbDistance).clamp(0.0, 1.0);

        weightedSimilarity += similarity * percentage;
        weightTotal += percentage;
      }
      if (weightTotal > 0) {
        colorScore = weightedSimilarity / weightTotal;
        if (colorScore >= 0.65) {
          colorNote = 'Matches your outfit colors';
        } else if (colorScore <= 0.3) {
          colorNote = "Doesn't match your outfit colors";
        }
      }
    }

    // Weighted average over whichever signals are actually available,
    // re-normalized so a missing signal doesn't just get treated as a
    // zero (which would unfairly tank every score while a user's
    // wrist/style/outfit data is still incomplete).
    double weightedSum = 0;
    double totalWeight = 0;
    if (fitScore != null) {
      weightedSum += fitScore * _fitWeight;
      totalWeight += _fitWeight;
    }
    if (colorScore != null) {
      weightedSum += colorScore * _colorWeight;
      totalWeight += _colorWeight;
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
      colorScore: colorScore,
      combinedScore: combinedScore,
      fitNote: fitNote,
      colorNote: colorNote,
    );
  }
}