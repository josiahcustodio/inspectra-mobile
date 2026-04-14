// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'establishment.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class EstablishmentAdapter extends TypeAdapter<Establishment> {
  @override
  final int typeId = 0;

  @override
  Establishment read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Establishment(
      id: fields[0] as String,
      name: fields[1] as String,
      category: fields[2] as String,
      address: fields[3] as String,
      ownerName: fields[4] as String,
      personnelCount: fields[5] as int,
      personnelWithHc: fields[6] as int,
      sanitaryPermitNo: fields[7] as String,
      controlNo: fields[8] as String,
    );
  }

  @override
  void write(BinaryWriter writer, Establishment obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.category)
      ..writeByte(3)
      ..write(obj.address)
      ..writeByte(4)
      ..write(obj.ownerName)
      ..writeByte(5)
      ..write(obj.personnelCount)
      ..writeByte(6)
      ..write(obj.personnelWithHc)
      ..writeByte(7)
      ..write(obj.sanitaryPermitNo)
      ..writeByte(8)
      ..write(obj.controlNo);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EstablishmentAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
