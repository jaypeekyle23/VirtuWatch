// IT-11: Sales history. A merchant records a sale by hand (VirtuWatch has no
// checkout) -> the sale is stored with a snapshot of the watch AND the stock
// goes down in the same transaction -> voiding puts the stock back. Also
// checks the Firestore rules around the `sales` collection, enforced by the
// emulator using the real firestore.rules. Each denied action is paired with
// an allowed one, so a pass means the rule blocks the right thing and not
// everything.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:virtuwatch/services/sales_service.dart';
import 'package:virtuwatch/services/watch_service.dart';

import 'support/emulator.dart';

final _db = FirebaseFirestore.instance;

Future<Map<String, dynamic>> _sale(String id) async =>
    (await _db.collection('sales').doc(id).get()).data()!;

/// A valid sale document, as the service would write it, for rule tests that
/// write straight to Firestore.
Map<String, dynamic> _rawSale({
  required String merchantId,
  required String watchId,
  Map<String, dynamic> overrides = const {},
}) =>
    {
      'merchantId': merchantId,
      'watchId': watchId,
      'watchName': 'Test watch',
      'quantity': 1,
      'unitPrice': 25000,
      'totalAmount': 25000,
      'soldAt': Timestamp.now(),
      'paymentMethod': 'Cash',
      'status': 'completed',
      'stockAdjusted': true,
      'createdAt': FieldValue.serverTimestamp(),
      ...overrides,
    };

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(TestEnv.ensureReady);

  group('IT-11 Sales history', () {
    late TestUser merchant;
    late String watchId;

    setUp(() async {
      await TestEnv.reset();
      merchant = await TestEnv.createStaff('merchant');
      watchId = await TestEnv.addWatch(sampleWatch(name: 'Sellable')); // stock 5
    });

    test('recording a sale stores a snapshot and lowers stock', () async {
      final receipt = await SalesService().recordSale(
        watchId: watchId,
        quantity: 2,
        unitPrice: 24000,
        soldAt: DateTime.now(),
        paymentMethod: 'GCash',
        buyerName: '  Ana  ',
      );

      expect(receipt.total, 48000);
      expect(receipt.stockLeft, 3);
      expect((await TestEnv.watchDoc(watchId))['stock'], 3);

      final sale = await _sale(receipt.id);
      expect(sale['merchantId'], merchant.uid);
      expect(sale['watchName'], 'Sellable');
      expect(sale['watchBrand'], 'TestBrand');
      expect(sale['quantity'], 2);
      expect(sale['unitPrice'], 24000); // the price it SOLD for, not the listing
      expect(sale['totalAmount'], 48000);
      expect(sale['buyerName'], 'Ana');
      expect(sale['status'], 'completed');
      expect(sale['stockAdjusted'], true);
    });

    test('the history survives the watch being edited or deleted', () async {
      final receipt = await SalesService().recordSale(
        watchId: watchId,
        quantity: 1,
        unitPrice: 25000,
        soldAt: DateTime.now(),
        paymentMethod: 'Cash',
      );
      await WatchService().updateWatch(
        watchId,
        {'name': 'Renamed', 'price': 99999},
      );
      expect((await _sale(receipt.id))['watchName'], 'Sellable');
      expect((await _sale(receipt.id))['unitPrice'], 25000);

      await WatchService().deleteWatch(watchId);
      expect((await _sale(receipt.id))['watchName'], 'Sellable');
    });

    test('cannot sell more than is in stock; nothing is written', () async {
      await expectLater(
        SalesService().recordSale(
          watchId: watchId,
          quantity: 6,
          unitPrice: 25000,
          soldAt: DateTime.now(),
          paymentMethod: 'Cash',
        ),
        throwsA(isA<SaleException>()),
      );
      expect((await TestEnv.watchDoc(watchId))['stock'], 5);
      expect((await _db.collection('sales').get()).docs, isEmpty);

      // Positive control: selling exactly what is left works.
      await SalesService().recordSale(
        watchId: watchId,
        quantity: 5,
        unitPrice: 25000,
        soldAt: DateTime.now(),
        paymentMethod: 'Cash',
      );
      expect((await TestEnv.watchDoc(watchId))['stock'], 0);
    });

    test('a watch with no stock count can be sold and stays untracked', () async {
      final untracked = await TestEnv.addWatch(
        sampleWatch(name: 'No count', extra: {'stock': null}),
      );
      final receipt = await SalesService().recordSale(
        watchId: untracked,
        quantity: 3,
        unitPrice: 25000,
        soldAt: DateTime.now(),
        paymentMethod: 'Cash',
      );
      expect(receipt.stockLeft, isNull);
      expect((await TestEnv.watchDoc(untracked))['stock'], isNull);
      expect((await _sale(receipt.id))['stockAdjusted'], false);

      // Voiding it must not invent stock either.
      final restored = await SalesService().voidSale(receipt.id);
      expect(restored, isFalse);
      expect((await TestEnv.watchDoc(untracked))['stock'], isNull);
    });

    test('voiding keeps the record, restores stock, and cannot repeat', () async {
      final receipt = await SalesService().recordSale(
        watchId: watchId,
        quantity: 2,
        unitPrice: 25000,
        soldAt: DateTime.now(),
        paymentMethod: 'Cash',
      );
      expect((await TestEnv.watchDoc(watchId))['stock'], 3);

      final restored =
          await SalesService().voidSale(receipt.id, reason: 'Entered twice');
      expect(restored, isTrue);
      expect((await TestEnv.watchDoc(watchId))['stock'], 5);

      final sale = await _sale(receipt.id);
      expect(sale['status'], 'voided');
      expect(sale['voidReason'], 'Entered twice');
      expect(sale['voidedAt'], isNotNull);

      await expectLater(
        SalesService().voidSale(receipt.id),
        throwsA(isA<SaleException>()),
      );
      expect((await TestEnv.watchDoc(watchId))['stock'], 5); // not restored twice
    });

    test('the rules accept a valid sale and reject tampered ones', () async {
      final sales = _db.collection('sales');

      // Positive control.
      await sales.add(_rawSale(merchantId: merchant.uid, watchId: watchId));

      // Under someone else's uid.
      await expectPermissionDenied(
        () => sales.add(_rawSale(merchantId: 'someone-else', watchId: watchId)),
      );
      // Wrong total.
      await expectPermissionDenied(
        () => sales.add(_rawSale(
          merchantId: merchant.uid,
          watchId: watchId,
          overrides: {'totalAmount': 1},
        )),
      );
      // Zero or negative quantity.
      await expectPermissionDenied(
        () => sales.add(_rawSale(
          merchantId: merchant.uid,
          watchId: watchId,
          overrides: {'quantity': 0, 'totalAmount': 0},
        )),
      );
      // Born voided.
      await expectPermissionDenied(
        () => sales.add(_rawSale(
          merchantId: merchant.uid,
          watchId: watchId,
          overrides: {'status': 'voided'},
        )),
      );
      // Not a payment method on the list.
      await expectPermissionDenied(
        () => sales.add(_rawSale(
          merchantId: merchant.uid,
          watchId: watchId,
          overrides: {'paymentMethod': 'Crypto'},
        )),
      );
      // A date well in the future.
      await expectPermissionDenied(
        () => sales.add(_rawSale(
          merchantId: merchant.uid,
          watchId: watchId,
          overrides: {
            'soldAt': Timestamp.fromDate(
              DateTime.now().add(const Duration(days: 30)),
            ),
          },
        )),
      );
      // An extra, unknown field.
      await expectPermissionDenied(
        () => sales.add(_rawSale(
          merchantId: merchant.uid,
          watchId: watchId,
          overrides: {'discountCode': 'FREE'},
        )),
      );
    });

    test('a merchant cannot record a sale for another merchant\'s watch', () async {
      final other = await TestEnv.createStaff('merchant');
      await expectPermissionDenied(
        () => _db.collection('sales').add(
              _rawSale(merchantId: other.uid, watchId: watchId),
            ),
      );
    });

    test('a sale can only ever change from completed to voided', () async {
      final receipt = await SalesService().recordSale(
        watchId: watchId,
        quantity: 1,
        unitPrice: 25000,
        soldAt: DateTime.now(),
        paymentMethod: 'Cash',
      );
      final ref = _db.collection('sales').doc(receipt.id);

      await expectPermissionDenied(() => ref.update({'totalAmount': 1}));
      await expectPermissionDenied(() => ref.update({'quantity': 99}));
      await expectPermissionDenied(() => ref.delete());
      // Positive control: voiding is allowed.
      await ref.update({
        'status': 'voided',
        'voidedAt': FieldValue.serverTimestamp(),
      });
      // And a voided sale can't be changed back.
      await expectPermissionDenied(() => ref.update({'status': 'completed'}));
    });

    test('merchants see only their own sales; admins can read all but not write',
        () async {
      final mine = await SalesService().recordSale(
        watchId: watchId,
        quantity: 1,
        unitPrice: 25000,
        soldAt: DateTime.now(),
        paymentMethod: 'Cash',
      );
      await TestEnv.signOut();

      // Another merchant cannot read it.
      final other = await TestEnv.createStaff('merchant');
      await expectPermissionDenied(
        () => _db.collection('sales').doc(mine.id).get(),
      );
      await expectPermissionDenied(
        () => _db
            .collection('sales')
            .where('merchantId', isEqualTo: merchant.uid)
            .get(),
      );
      // Positive control: their own (empty) history is readable.
      final own = await _db
          .collection('sales')
          .where('merchantId', isEqualTo: other.uid)
          .get();
      expect(own.docs, isEmpty);
      await TestEnv.signOut();

      // An admin can read it, but cannot change or create sales.
      await TestEnv.createStaff('admin');
      expect((await _sale(mine.id))['merchantId'], merchant.uid);
      await expectPermissionDenied(
        () => _db.collection('sales').doc(mine.id).update({
          'status': 'voided',
          'voidedAt': FieldValue.serverTimestamp(),
        }),
      );
      await expectPermissionDenied(
        () => _db.collection('sales').add(
              _rawSale(merchantId: merchant.uid, watchId: watchId),
            ),
      );
    });

    test('customers cannot read or record sales', () async {
      final receipt = await SalesService().recordSale(
        watchId: watchId,
        quantity: 1,
        unitPrice: 25000,
        soldAt: DateTime.now(),
        paymentMethod: 'Cash',
      );
      await TestEnv.signOut();
      await TestEnv.registerCustomer();

      await expectPermissionDenied(
        () => _db.collection('sales').doc(receipt.id).get(),
      );
      await expectPermissionDenied(
        () => _db.collection('sales').add(
              _rawSale(merchantId: merchant.uid, watchId: watchId),
            ),
      );
    });
  });
}
