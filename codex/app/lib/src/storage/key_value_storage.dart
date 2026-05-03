import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef JsonFactory<T> = T Function(Map<String, dynamic> json);

extension SharedPreferencesAsyncStorageX on SharedPreferencesAsync {
  Future<String?> readNonEmptyString(String key) async {
    final value = await getString(key);
    if (value == null || value.isEmpty) {
      return null;
    }

    return value;
  }

  Future<T?> readObject<T>(String key, JsonFactory<T> fromJson) async {
    final value = await readNonEmptyString(key);
    if (value == null) {
      return null;
    }

    return fromJson(json.decode(value) as Map<String, dynamic>);
  }

  Future<void> writeObject(String key, Object value) {
    return setString(key, json.encode(value));
  }
}

extension FlutterSecureStorageX on FlutterSecureStorage {
  Future<String?> readNonEmptyString(String key) async {
    final value = await read(key: key);
    if (value == null || value.isEmpty) {
      return null;
    }

    return value;
  }

  Future<T?> readObject<T>(String key, JsonFactory<T> fromJson) async {
    final value = await readNonEmptyString(key);
    if (value == null) {
      return null;
    }

    return fromJson(json.decode(value) as Map<String, dynamic>);
  }

  Future<void> writeObject(String key, Object value) {
    return write(key: key, value: json.encode(value));
  }
}
