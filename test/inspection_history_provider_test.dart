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
}
