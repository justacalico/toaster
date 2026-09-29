import 'dart:io';

const bool fileStoreSupportedImpl = true;

// Sync IO: the payloads are small text files, and synchronous calls keep
// working inside Flutter's fake-async widget test zone where dart:io
// Futures never get serviced.
Future<String?> saveTextFileImpl(String path, String contents) async {
  try {
    final f = File(path);
    f.createSync(recursive: true);
    f.writeAsStringSync(contents);
    return path;
  } catch (_) {
    return null;
  }
}

Future<String?> readTextFileImpl(String path) async {
  try {
    return File(path).readAsStringSync();
  } catch (_) {
    return null;
  }
}
