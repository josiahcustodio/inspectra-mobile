import 'dart:io';
import 'package:hive/hive.dart';

void main() async {
  Hive.init('${Directory.current.path}\\.dart_tool\\chrome-device'); // Or wherever path the edge device stores it
  // Actually, since it's a browser (edge) it uses indexed db, dart run won't be able to access the same hive boxes
}
