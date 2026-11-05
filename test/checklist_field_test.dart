import 'package:flutter_test/flutter_test.dart';

import 'package:clowtec_inspector/data/models/checklist_template.dart';

/// `checklist_templates.fields` round-trips through the Hive-friendly JSON
/// string, and a row without (or with broken) fields is a plain item.
void main() {
  test('fields parse from the server row', () {
    final t = ChecklistTemplate.fromJson({
      'id': '221',
      'item_name': 'Location of Water Source',
      'fields': [
        {'label': 'Location', 'type': 'choice', 'options': ['Uphill', 'Downhill']},
        {'label': 'Type of water source'},
      ],
    });
    expect(t.fields.length, 2);
    expect(t.fields[0].type, 'choice');
    expect(t.fields[0].options, ['Uphill', 'Downhill']);
    expect(t.fields[1].type, 'text');
  });

  test('missing or malformed fields degrade to none', () {
    expect(ChecklistTemplate.fromJson({'id': '1'}).fields, isEmpty);
    expect(
        ChecklistTemplate(
                id: '1', category: '', subCategory: '', item: '', weight: 5, fieldsJson: '{not json')
            .fields,
        isEmpty);
  });
}
