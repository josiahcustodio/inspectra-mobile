import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:clowtec_inspector/core/sanitary_order.dart';
import 'package:clowtec_inspector/data/models/establishment.dart';
import 'package:clowtec_inspector/ui/widgets/establishment_details_card.dart';

Future<void> pumpCard(WidgetTester tester, Establishment e) =>
    tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: EstablishmentDetailsCard(establishment: e),
        ),
      ),
    ));

void main() {
  test('fromJson reads masterlist columns, tolerating a numeric floor area', () {
    final e = Establishment.fromJson({
      'id': 'x',
      'business_name': 'Shop',
      'line_of_business': 'Bakery',
      'business_permit_no': 'BP-1',
      'tel_no': '043-123',
      'floor_area_sqm': 45.5,
    });
    expect(e.lineOfBusiness, 'Bakery');
    expect(e.businessPermitNo, 'BP-1');
    expect(e.telNo, '043-123');
    expect(e.floorAreaSqm, '45.5');
    expect(e.tin, isNull);
  });

  testWidgets('shows recorded values and hides blank, N/A and zero ones',
      (tester) async {
    await pumpCard(
      tester,
      Establishment.fromJson({
        'id': 'x',
        'business_name': 'Shop',
        'line_of_business': 'Bakery',
        'floor_area_sqm': 45.5,
        'tin': 'N/A',
        'tel_no': '  ',
        'personnel_count': 0,
      }),
    );
    expect(find.text('Bakery'), findsOneWidget);
    expect(find.text('45.5 sqm'), findsOneWidget);
    expect(find.text('TIN'), findsNothing);
    expect(find.text('Telephone'), findsNothing);
    expect(find.text('Personnel'), findsNothing);
  });

  testWidgets('renders nothing when the record has no masterlist details',
      (tester) async {
    await pumpCard(tester, Establishment.fromJson({'id': 'x'}));
    expect(find.text('Business information'), findsNothing);
  });

  test('emailBlocker allows blank and valid addresses, refuses malformed', () {
    expect(SanitaryOrder.emailBlocker(null), isNull);
    expect(SanitaryOrder.emailBlocker('   '), isNull);
    expect(SanitaryOrder.emailBlocker(' Juan@Gmail.com '), isNull);
    expect(SanitaryOrder.emailBlocker('juan@gmail'), contains('email address'));
  });
}
