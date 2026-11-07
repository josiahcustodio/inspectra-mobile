import 'package:flutter_test/flutter_test.dart';
import 'package:clowtec_inspector/providers/inspection_history_provider.dart';

void main() {
  test('clear() empties the list and the error so the next user starts blank', () {
    final p = InspectionHistoryProvider();
    var notified = 0;
    p.addListener(() => notified++);
    p.clear();
    expect(p.logs, isEmpty);
    expect(p.establishmentNames, isEmpty);
    expect(p.error, isNull);
    expect(p.isEmpty, isTrue);
    expect(notified, 1);
  });

  test('a fetch that outlives clear() leaves the cleared state alone', () async {
    // No Supabase or Hive here, so the fetch fails on both paths; the point is
    // that neither failure may write into state that belongs to the next user.
    final p = InspectionHistoryProvider();
    var notified = 0;
    p.addListener(() => notified++);
    final inFlight = p.fetchHistory();
    p.clear();
    await inFlight;
    expect(p.error, isNull);
    expect(p.isLoading, isFalse);
    expect(notified, 2, reason: 'fetch start + clear; the stale fetch stays silent');
  });
}
