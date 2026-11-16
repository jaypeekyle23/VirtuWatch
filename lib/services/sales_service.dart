import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../utils/sales.dart';
import '../utils/stock.dart';
import 'activity_log_service.dart';

/// An error whose message is safe to show to the merchant as it is ("Only 2 in
/// stock."). Anything else (a network failure, a denied write) is shown as a
/// generic message by [saleErrorMessage].
class SaleException implements Exception {
  final String message;
  const SaleException(this.message);

  @override
  String toString() => message;
}

/// What to tell the merchant for a failed save or void.
String saleErrorMessage(Object error, String fallback) =>
    error is SaleException ? error.message : fallback;

/// The result of a recorded sale.
class SaleReceipt {
  final String id;
  final double total;

  /// Stock after the sale, or null when the watch has no stock count.
  final int? stockLeft;
  final String label;

  const SaleReceipt({
    required this.id,
    required this.total,
    required this.stockLeft,
    required this.label,
  });
}

/// Reads and writes the `sales` collection: the merchant's history of what
/// they sold. VirtuWatch has no checkout, so every sale is recorded by hand
/// after it happened off the platform. A Dart port of
/// admin-web/src/services/salesService.js; the security rules are in
/// firestore.rules.
class SalesService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final _activityLog = ActivityLogService();

  CollectionReference<Map<String, dynamic>> get _sales =>
      _firestore.collection('sales');

  /// Stream of the signed-in merchant's sales, newest first. Pass [limit] to
  /// read only the latest few.
  Stream<QuerySnapshot<Map<String, dynamic>>> mySales({int? limit}) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Stream.empty();
    var query = _sales
        .where('merchantId', isEqualTo: uid)
        .orderBy('soldAt', descending: true);
    if (limit != null) query = query.limit(limit);
    return query.snapshots();
  }

  /// Records a sale the merchant made OFF the platform, and takes the units
  /// out of stock.
  ///
  /// The sale and the stock change are written in ONE transaction, so they can
  /// never drift apart: either both happen or neither does. The watch is read
  /// again inside the transaction, so the stock check uses the real count, not
  /// what the screen last showed.
  ///
  /// A watch with no stock count can still be sold; its count is simply left
  /// alone, and the sale remembers that (`stockAdjusted: false`) so voiding it
  /// later does not invent stock either.
  Future<SaleReceipt> recordSale({
    required String watchId,
    required int quantity,
    required double unitPrice,
    required DateTime soldAt,
    required String paymentMethod,
    String buyerName = '',
    String notes = '',
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      throw const SaleException('You must be logged in to record a sale.');
    }

    final watchRef = _firestore.collection('watches').doc(watchId);
    final saleRef = _sales.doc(); // the id is known now, so a retry is safe
    final total = saleTotal(unitPrice, quantity);
    var label = '';
    int? stockLeft;

    await _firestore.runTransaction((tx) async {
      // The callback can run more than once if another write gets in first.
      stockLeft = null;
      final snap = await tx.get(watchRef);
      final watch = snap.data();
      if (!snap.exists || watch == null) {
        throw const SaleException('This watch no longer exists.');
      }
      if (watch['merchantId'] != uid) {
        throw const SaleException(
            'You can only record sales for your own watches.');
      }

      final stock = stockOf(watch);
      if (stock != null && quantity > stock) {
        throw SaleException(
            stock == 0 ? 'This watch is out of stock.' : 'Only $stock in stock.');
      }

      final name = (watch['name'] as String?)?.trim() ?? '';
      final brand = (watch['brand'] as String?)?.trim() ?? '';
      final images = (watch['imageUrls'] as List?)?.whereType<String>().toList();
      final image = (images != null && images.isNotEmpty)
          ? images.first
          : (watch['imageUrl'] as String? ?? '');
      final displayName = name.isEmpty ? 'Unnamed watch' : name;
      label = brand.isEmpty ? displayName : '$brand $displayName';

      tx.set(saleRef, {
        'merchantId': uid,
        'watchId': watchId,
        // A snapshot, so the history survives the watch being edited or
        // deleted.
        'watchName': displayName,
        if (brand.isNotEmpty) 'watchBrand': brand,
        if (image.isNotEmpty) 'watchImageUrl': image,
        'quantity': quantity,
        'unitPrice': unitPrice,
        'totalAmount': total,
        'soldAt': Timestamp.fromDate(soldAt),
        'paymentMethod': paymentMethod,
        if (buyerName.trim().isNotEmpty) 'buyerName': buyerName.trim(),
        if (notes.trim().isNotEmpty) 'notes': notes.trim(),
        'status': saleCompleted,
        'stockAdjusted': stock != null,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (stock != null) {
        stockLeft = stock - quantity;
        tx.update(watchRef, {
          'stock': stockLeft,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    });

    await _activityLog.log(
      'sale_recorded',
      'Sale recorded: $quantity × $label (${formatSaleMoney(total)})',
    );
    return SaleReceipt(
      id: saleRef.id,
      total: total,
      stockLeft: stockLeft,
      label: label,
    );
  }

  /// Voids a sale recorded by mistake. The record stays in the history, marked
  /// as voided and left out of every total, and the units go back into stock
  /// (only if this sale took them out in the first place, and only if the
  /// watch still exists). Returns whether stock was put back.
  Future<bool> voidSale(String saleId, {String reason = ''}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      throw const SaleException('You must be logged in to void a sale.');
    }

    final saleRef = _sales.doc(saleId);
    var restored = false;
    var summary = '';

    await _firestore.runTransaction((tx) async {
      restored = false; // the callback can run more than once
      final saleSnap = await tx.get(saleRef);
      final sale = saleSnap.data();
      if (!saleSnap.exists || sale == null) {
        throw const SaleException('This sale could not be found.');
      }
      if (sale['merchantId'] != uid) {
        throw const SaleException('You can only void your own sales.');
      }
      if (sale['status'] != saleCompleted) {
        throw const SaleException('This sale is already voided.');
      }

      // All reads before any write.
      final watchRef =
          _firestore.collection('watches').doc(sale['watchId'] as String);
      final watchSnap = await tx.get(watchRef);

      final trimmedReason = reason.trim();
      tx.update(saleRef, {
        'status': saleVoided,
        'voidedAt': FieldValue.serverTimestamp(),
        if (trimmedReason.isNotEmpty) 'voidReason': trimmedReason,
      });

      final quantity = (sale['quantity'] as num).toInt();
      final watchData = watchSnap.data();
      if (sale['stockAdjusted'] == true && watchSnap.exists && watchData != null) {
        final stock = stockOf(watchData);
        if (stock != null) {
          final restoredStock = stock + quantity;
          tx.update(watchRef, {
            'stock': restoredStock > maxSaleQuantity
                ? maxSaleQuantity
                : restoredStock,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          restored = true;
        }
      }

      final brand = sale['watchBrand'] as String?;
      summary = '$quantity × ${brand != null ? '$brand ' : ''}${sale['watchName']}';
    });

    await _activityLog.log('sale_voided', 'Sale voided: $summary');
    return restored;
  }
}
