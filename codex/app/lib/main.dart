import 'package:app/src/app.dart';
import 'package:app/src/di/injector.dart';
import 'package:flutter/material.dart';

void main() {
  Injector.setup();
  runApp(const App());
}
