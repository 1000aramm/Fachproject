class IoHelper {
  static Future<void> deleteFile(String path) async {
    // No-op on web
  }

  static Future<List<int>> readAsBytes(String path) async {
    // This shouldn't be called on web with a file path
    return [];
  }

  static List<int> readFileSync(String path) {
    // This shouldn't be called on web
    return [];
  }
}
