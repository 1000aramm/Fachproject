import 'dart:io' as io;

class IoHelper {
  static Future<void> deleteFile(String path) async {
    final file = io.File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  static Future<List<int>> readAsBytes(String path) async {
    return await io.File(path).readAsBytes();
  }

  static List<int> readFileSync(String path) {
    return io.File(path).readAsBytesSync();
  }
}
