import 'package:flutter_test/flutter_test.dart';
import 'package:clowtec_inspector/data/models/establishment.dart';

void main() {
  test('withLocation changes only the coordinates', () {
    final a = Establishment.fromJson({
      'id': 'e1', 'business_name': 'Cafe', 'category': 'Food', 'address': 'Main St',
      'owner_name': 'O', 'personnel_count': 3, 'personnel_with_hc': 2,
      'sanitary_permit_no': 'SP1', 'control_no': 'C1', 'barangay': 'Poblacion',
      'category_id': '1', 'business_permit_no': 'BP1', 'applic_type': 'New',
      'permit_date_issued': '2026-01-01', 'line_of_business': 'Coffee',
      'floor_area_sqm': 20, 'tel_no': '123', 'tin': 'T1',
      'latitude': 13.7, 'longitude': 121.0,
    });
    final b = a.withLocation(13.76, 121.05);
    expect(b.latitude, 13.76);
    expect(b.longitude, 121.05);
    expect(b.id, a.id);
    expect(b.name, a.name);
    expect(b.ownerName, a.ownerName);
    expect(b.barangay, a.barangay);
    expect(b.categoryId, a.categoryId);
    expect(b.sanitaryPermitNo, a.sanitaryPermitNo);
    expect(b.controlNo, a.controlNo);
    expect(b.personnelCount, a.personnelCount);
    expect(b.personnelWithHc, a.personnelWithHc);
    expect(b.businessPermitNo, a.businessPermitNo);
    expect(b.lineOfBusiness, a.lineOfBusiness);
    expect(b.floorAreaSqm, a.floorAreaSqm);
    expect(b.telNo, a.telNo);
    expect(b.tin, a.tin);
    expect(b.isSynced, a.isSynced);
  });
}
