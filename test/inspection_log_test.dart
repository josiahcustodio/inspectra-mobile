import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:clowtec_inspector/data/models/inspection_log.dart';

/// Pins the `InspectionLog` serialization contract: what reaches the
/// database, what is omitted rather than nulled, and what survives the
/// offline queue's JSON-string round-trip.
void main() {
  group('an unscored inspection is not a zero', () {
    test('a missing percentage_rating stays null through fromJson', () {
      // It used to be coerced to 0.0 — the bottom of the lowest band, so an
      // ungraded record rendered as a red failing grade nobody recorded.
      final revived = InspectionLog.fromJson({
        'id': 'log-unscored',
        'establishment_id': 'est-0001',
        'inspector_name': 'Inspector Test',
        'total_demerits': 0,
        'results': <dynamic>[],
      });

      expect(revived.percentageRating, isNull);
      // ...and is distinguishable from an inspection that really scored zero.
      final zero = InspectionLog.fromJson({
        'id': 'log-zero',
        'establishment_id': 'est-0001',
        'inspector_name': 'Inspector Test',
        'total_demerits': 100,
        'percentage_rating': 0,
        'results': <dynamic>[],
      });
      expect(zero.percentageRating, 0.0);
    });

    test('a real score survives the queue round-trip unchanged', () {
      final original = InspectionLog(
        id: 'log-scored',
        establishmentId: 'est-0001',
        inspectorName: 'Inspector Test',
        totalDemerits: 15,
        percentageRating: 85.0,
      );
      final revived = InspectionLog.fromJson(
          jsonDecode(jsonEncode(original.toJson()))
              as Map<String, dynamic>);
      expect(revived.percentageRating, 85.0);
    });
  });

  // [REF: PROPOSED_CONTACT]
  group('the point person proposal rides the log', () {
    InspectionLog proposing() => InspectionLog(
          id: 'log-0020',
          establishmentId: 'est-0001',
          inspectorName: 'Inspector Test',
          totalDemerits: 15,
          percentageRating: 85.0,
          soIssuedAt: '2026-10-23T02:00:00.000Z',
          proposedPointPersonName: 'Juan Dela Cruz',
          proposedPointPersonEmail: 'juan@example.com',
        );

    test('it reaches both the database and the offline queue', () {
      expect(proposing().toJson()['proposed_point_person_email'],
          'juan@example.com');
    });

    test('it survives the queue round-trip', () {
      final revived = InspectionLog.fromJson(
          jsonDecode(jsonEncode(proposing().toJson()))
              as Map<String, dynamic>);
      expect(revived.proposedPointPersonEmail, 'juan@example.com');
      expect(revived.proposedPointPersonName, 'Juan Dela Cruz');
    });

    test('an inspection that proposed nothing writes neither key', () {
      // upsert overwrites every key it is handed, so nulling these on a retry
      // would erase a proposal an admin may already be looking at.
      final json = InspectionLog(
        id: 'log-0021',
        establishmentId: 'est-0001',
        inspectorName: 'Inspector Test',
        totalDemerits: 0,
        percentageRating: 100.0,
      ).toJson();
      expect(json, isNot(contains('proposed_point_person_name')));
      expect(json, isNot(contains('proposed_point_person_email')));
    });
  });

  // [REF: SANITARY_ORDER_WRITE]
  group('order fields are omitted, never nulled', () {
    test('an inspection that issued no order writes no order keys at all', () {
      // upsert() overwrites every key it is handed, so writing nulls here
      // would erase an order a previous drain had already landed — and a
      // reader could not tell "no order" from "an order with nothing filled".
      final json = InspectionLog(
        id: 'log-clean',
        establishmentId: 'est-0001',
        inspectorName: 'Inspector Test',
        totalDemerits: 0,
        percentageRating: 100.0,
      ).toJson();

      for (final key in [
        'so_no',
        'so_issued_at',
        'time_given',
        'deadline',
        'received_by_name',
      ]) {
        expect(json, isNot(contains(key)), reason: '$key must be omitted');
      }
    });

    test('email_sent_at is never written by the client', () {
      // It is stamped server-side by the delivery function. A client that
      // carried it would null out the server's stamp on the next retry of a
      // queued log.
      final order = InspectionLog(
        id: 'log-0012',
        establishmentId: 'est-0001',
        inspectorName: 'Inspector Test',
        totalDemerits: 15,
        percentageRating: 85.0,
        soIssuedAt: '2026-10-23T02:00:00.000Z',
      );
      expect(order.toJson(), isNot(contains('email_sent_at')));
    });

    test('an order may legitimately carry no number', () {
      // so_no stays blank until CHO's booklet pattern is known; so_issued_at
      // is what marks the order as existing.
      final json = InspectionLog(
        id: 'log-0013',
        establishmentId: 'est-0001',
        inspectorName: 'Inspector Test',
        totalDemerits: 15,
        percentageRating: 85.0,
        soIssuedAt: '2026-10-23T02:00:00.000Z',
        timeGiven: '7 days',
        deadline: '2026-10-30',
      ).toJson();

      expect(json, contains('so_issued_at'));
      expect(json, isNot(contains('so_no')));
      expect(json['deadline'], '2026-10-30');
    });

    test('so_issued_at is normalized like every other timestamp', () {
      // An offset-less string came from a device local clock; read as UTC it
      // would land a Manila order 8 hours early.
      final json = InspectionLog(
        id: 'log-0014',
        establishmentId: 'est-0001',
        inspectorName: 'Inspector Test',
        totalDemerits: 15,
        percentageRating: 85.0,
        soIssuedAt: '2026-10-23T10:00:00.000',
      ).toJson();

      expect(json['so_issued_at'], endsWith('Z'));
    });
  });
}
