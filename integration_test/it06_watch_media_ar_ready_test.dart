// IT-06: Merchant listing media -> Firestore -> AR readiness.
//
// The upload to Cloudinary itself needs the network and a real account, so
// it is shown manually (Cloudinary Media Library screenshot). What IS checked
// here is everything after the upload: the resulting URLs are saved on the
// watch document, and AR readiness follows the admin-measured fit.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:virtuwatch/services/watch_service.dart';
import 'package:virtuwatch/utils/ar_readiness.dart';

import 'support/emulator.dart';

const _imageUrl =
    'https://res.cloudinary.com/demo/image/upload/v1/virtuwatch/test_front.jpg';
const _imageUrl2 =
    'https://res.cloudinary.com/demo/image/upload/v1/virtuwatch/test_side.jpg';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(TestEnv.ensureReady);

  group('IT-06 Merchant Upload -> Watch Document -> AR Readiness', () {
    late TestUser merchant;
    late TestUser admin;
    late String watchId;

    setUp(() async {
      await TestEnv.reset();
      admin = await TestEnv.createStaff('admin');
      merchant = await TestEnv.createStaff('merchant');
      watchId = await TestEnv.addWatch(
        sampleWatch(
          name: 'Media Watch',
          extra: {
            'imageUrl': _imageUrl,
            'imageUrls': [_imageUrl, _imageUrl2],
            'modelUrl': sampleModelUrl,
            'has3DModel': true,
          },
        ),
      );
    });

    test('image and model URLs are stored on the watch document', () async {
      final data = await TestEnv.watchDoc(watchId);
      expect(data['imageUrl'], _imageUrl);
      expect(data['imageUrls'], [_imageUrl, _imageUrl2]);
      expect(data['modelUrl'], sampleModelUrl);
      expect(data['has3DModel'], isTrue);
      expect(data['merchantId'], merchant.uid);
    });

    test(
      'a watch with a model but no admin-set arFit is not AR-ready',
      () async {
        expect(isArReady(await TestEnv.watchDoc(watchId)), isFalse);
      },
    );

    test(
      'once an admin sets arFit for that model, the watch is AR-ready',
      () async {
        await TestEnv.signIn(admin.email);
        await WatchService().updateWatch(watchId, {'arFit': sampleArFit()});

        final data = await TestEnv.watchDoc(watchId);
        expect(isArReady(data), isTrue);
        final fit = ArFit.tryParse(data)!;
        expect(fit.modelUrl, sampleModelUrl);
        expect(
          fit.toChannelMap().keys,
          containsAll(['holeCx', 'holeHalfX', 'holeHalfY', 'scale']),
        );
      },
    );

    test('replacing the 3D model invalidates the old fit', () async {
      await TestEnv.signIn(admin.email);
      await WatchService().updateWatch(watchId, {'arFit': sampleArFit()});
      expect(isArReady(await TestEnv.watchDoc(watchId)), isTrue);

      await TestEnv.signIn(merchant.email);
      await WatchService().updateWatch(watchId, {
        'modelUrl': 'https://res.cloudinary.com/demo/raw/upload/v2/virtuwatch/new_model.glb',
      });

      expect(isArReady(await TestEnv.watchDoc(watchId)), isFalse);
    });

    test('removing the 3D model flag takes the watch out of AR', () async {
      await TestEnv.signIn(admin.email);
      await WatchService().updateWatch(watchId, {'arFit': sampleArFit()});

      await TestEnv.signIn(merchant.email);
      await WatchService().updateWatch(watchId, {'has3DModel': false});

      expect(isArReady(await TestEnv.watchDoc(watchId)), isFalse);
    });
  });
}
