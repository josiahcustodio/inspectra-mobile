// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'checklist_template.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ChecklistTemplateAdapter extends TypeAdapter<ChecklistTemplate> {
  @override
  final int typeId = 1;

  @override
  ChecklistTemplate read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ChecklistTemplate(
      id: fields[0] as String,
      category: fields[1] as String,
      subCategory: fields[2] as String,
      item: fields[3] as String,
      weight: fields[4] as int,
    );
  }

  @override
  void write(BinaryWriter writer, ChecklistTemplate obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.category)
      ..writeByte(2)
      ..write(obj.subCategory)
      ..writeByte(3)
      ..write(obj.item)
      ..writeByte(4)
      ..write(obj.weight);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChecklistTemplateAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
