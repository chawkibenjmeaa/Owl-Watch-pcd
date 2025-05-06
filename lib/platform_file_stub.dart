// lib/platform_file_stub.dart
// Dummy implementations for web (since dart:io is not available).

class File {
  File(String path);
  Future<void> writeAsBytes(List<int> bytes) async {}
  dynamic openRead() => null;
  // Changed lengthSync to be a method, matching dart:io's API.
  int lengthSync() => 0;
  String get path => "";
  Future<void> delete() async {}
}

class Platform {
  static bool get isAndroid => false;
}
