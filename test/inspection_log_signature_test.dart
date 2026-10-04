import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:clowtec_inspector/data/models/inspection_log.dart';

/// Pins the signature serialization contract on `InspectionLog` (Chunk 7).
///
/// These exist because the contract has a deliberately asymmetric shape that
/// a well-meaning refactor could easily "simplify" into a bug:
///
///  * `signature_url` and `signature_sha256` travel to Firestore strictly as
///    a pair — a hash of an image Firestore cannot see verifies nothing, and
///    a consumer that only checks for the key would read it as a signed
///    record.
///  * `local_signature_path` is a path on one inspector's phone; it may only
///    ever reach the Hive queue (`toQueueJson`), never Firestore (`toJson`).
///  * The queue round-trip runs through a JSON *string* (the queue box stores
///    strings), and getting it wrong fails only on the offline path — the one
///    least likely to be exercised by hand.
void main() {
  InspectionLog stagedLog() => InspectionLog(
        id: 'log-0001',
        establishmentId: 'est-0001',
        establishmentName: 'Test Carinderia',
        inspectorName: 'Inspector Test',
        totalDemerits: 10,
        percentageRating: 90.0,
        signatureSha256: 'a3f5…deadbeef',
        localSignaturePath: '/data/user/0/app/signatures/log-0001.png',
      );

  InspectionLog uploadedLog() => InspectionLog(
        id: 'log-0002',
        establishmentId: 'est-0001',
        inspectorName: 'Inspector Test',
        totalDemerits: 0,
        percentageRating: 100.0,
        signatureUrl: 'https://storage.example/signatures/est-0001/log-0002.png',
        signatureSha256: 'b4e6…cafef00d',
      );

  group('offline queue round-trip', () {
    test('a staged signature survives toQueueJson → jsonEncode → fromJson', () {
      final original = stagedLog();

      // The exact pipeline the form and SyncService use: the queue box holds
      // a string, not a map.
      final wire = jsonEncode(original.toQueueJson());
      final revived =
          InspectionLog.fromJson(jsonDecode(wire) as Map<String, dynamic>);

      expect(revived.id, original.id);
      expect(revived.localSignaturePath, original.localSignaturePath);
      expect(revived.signatureSha256, original.signatureSha256);
      expect(revived.signatureUrl, isNull);
    });

    test('an already-uploaded signature survives the queue round-trip too', () {
      // Reachable when Storage succeeded but the Firestore write failed: the
      // log is queued with a URL and no staged path, and the retry must not
      // lose either half of the pair.
      final original = uploadedLog();

      final wire = jsonEncode(original.toQueueJson());
      final revived =
          InspectionLog.fromJson(jsonDecode(wire) as Map<String, dynamic>);

      expect(revived.signatureUrl, original.signatureUrl);
      expect(revived.signatureSha256, original.signatureSha256);
      expect(revived.localSignaturePath, isNull);
    });
  });

  group('toJson never leaks the device-local path', () {
    test('staged log', () {
      expect(stagedLog().toJson(), isNot(contains('local_signature_path')));
    });

    test('uploaded log', () {
      expect(uploadedLog().toJson(), isNot(contains('local_signature_path')));
    });

    test('queue representation does carry it — the asymmetry is the point', () {
      expect(stagedLog().toQueueJson(), contains('local_signature_path'));
    });
  });

  group('url + hash pairing rule', () {
    test('no URL means toJson writes neither key, even with a hash set', () {
      final json = stagedLog().toJson();
      expect(json, isNot(contains('signature_url')));
      expect(json, isNot(contains('signature_sha256')));
    });

    test('with a URL, toJson writes both', () {
      final json = uploadedLog().toJson();
      expect(json['signature_url'], uploadedLog().signatureUrl);
      expect(json['signature_sha256'], uploadedLog().signatureSha256);
    });

    test('the staged hash still reaches the queue so the retry can re-pair it',
        () {
      final queued = stagedLog().toQueueJson();
      expect(queued['signature_sha256'], stagedLog().signatureSha256);
      expect(queued, isNot(contains('signature_url')));
    });

    test('a URL with no hash writes neither key — the pair is two-way', () {
      // Unreachable through current code paths (every URL acquisition
      // computes the hash first), pinned so the rule stays structural
      // rather than circumstantial.
      final json = InspectionLog(
        id: 'log-0003',
        establishmentId: 'est-0001',
        inspectorName: 'Inspector Test',
        totalDemerits: 0,
        percentageRating: 100.0,
        signatureUrl: 'https://storage.example/signatures/est-0001/log-0003.png',
      ).toJson();
      expect(json, isNot(contains('signature_url')));
      expect(json, isNot(contains('signature_sha256')));
    });

    test('a legacy log with no signature at all writes no signature keys', () {
      final json = InspectionLog(
        id: 'log-legacy',
        establishmentId: 'est-0001',
        inspectorName: 'Inspector Test',
        totalDemerits: 5,
        percentageRating: 95.0,
      ).toJson();
      expect(json, isNot(contains('signature_url')));
      expect(json, isNot(contains('signature_sha256')));
      expect(json, isNot(contains('local_signature_path')));
    });
  });
}
