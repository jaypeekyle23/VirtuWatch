// IT-01: Screen Calibration -> Wrist Measurement -> Firestore -> Recommendations

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:virtuwatch/services/auth_service.dart';
import 'package:virtuwatch/services/recommendation_service.dart';
import 'package:virtuwatch/services/screen_calibration_service.dart';
import 'package:virtuwatch/utils/wrist_math.dart';

import 'support/emulator.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(TestEnv.ensureReady);

  group('IT-01 Screen Calibration -> Wrist Measurement', () {
    setUp(() async {
      await TestEnv.reset();
      await ScreenCalibrationService.clear();
    });

    test('calibrating against a card, then measuring, saves wristWidthMm and '
        'wristMeasurementMethod on the user document', () async {
      final customer = await TestEnv.registerCustomer();
      expect(await ScreenCalibrationService.isCalibrated(), isFalse);

      // Calibration: a card (53.98 mm) lined up at 250 px.
      final ratio = mmPerPixelFromReference(
        referenceMm: cardReferenceMm,
        offsetPx: 250,
      );
      await ScreenCalibrationService.saveMmPerPixel(ratio);
      expect(await ScreenCalibrationService.isCalibrated(), isTrue);
      final stored = await ScreenCalibrationService.getMmPerPixel();
      expect(stored, closeTo(0.21592, 0.00001));

      // Measurement: the wrist lines up at 280 px, saved as a screen measurement.
      final wristMm = pxToMm(280, stored!);
      await AuthService().saveWristMeasurement(wristMm, method: 'screen');

      final doc = await TestEnv.userDoc(customer.uid);
      expect(doc['wristWidthMm'], closeTo(60.45, 0.01));
      expect(doc['wristMeasurementMethod'], 'screen');
      expect(doc['lastWristMeasurementAt'], isA<Timestamp>());
    });

    test(
      'the saved wrist width is used by the next recommendation pass',
      () async {
        await TestEnv.seedCatalog([
          sampleWatch(name: 'Fits', lugToLugMm: 48),
          sampleWatch(name: 'Overhangs', lugToLugMm: 70),
        ]);
        await TestEnv.registerCustomer();

        final before = await RecommendationService().getRecommendations();
        expect(before.wristWidthMm, isNull);
        expect(recFor(before, 'Fits').fitScore, isNull);

        await AuthService().saveWristMeasurement(60.45, method: 'screen');

        final after = await RecommendationService().getRecommendations();
        expect(after.wristWidthMm, closeTo(60.45, 0.01));
        final fits = recFor(after, 'Fits').fitScore!;
        final overhangs = recFor(after, 'Overhangs').fitScore!;
        expect(fits, inInclusiveRange(0, 1));
        expect(fits, greaterThan(overhangs));
        expect(rankedNames(after).first, 'Fits');
      },
    );
  });
}
