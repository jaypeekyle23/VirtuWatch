import 'package:flutter_test/flutter_test.dart';
import 'package:virtuwatch/services/watch_service.dart';

void main() {
  test('AR try-on totals add up across watches', () {
    const stats = EngagementStats(
      savedCounts: {},
      viewedCounts: {},
      uniqueSaverCount: 0,
      tryOnerCounts: {'a': 2, 'b': 1},
      tryOnCounts: {'a': 5, 'b': 1},
      photoCounts: {'a': 3},
      shareCounts: {'a': 1, 'b': 1},
      uniqueTryOnerCount: 2,
    );
    expect(stats.totalTryOns, 6);
    expect(stats.totalPhotos, 3);
    expect(stats.totalShares, 2);
  });

  test('AR fields default to zero for stats built without them', () {
    const stats = EngagementStats(
      savedCounts: {'a': 1},
      viewedCounts: {'a': 1},
      uniqueSaverCount: 1,
    );
    expect(stats.totalTryOns, 0);
    expect(stats.uniqueTryOnerCount, 0);
  });
}