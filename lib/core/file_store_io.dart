import 'dart:io';

const bool fileStoreSupportedImpl = true;

Future<String?> saveTextFileImpl(String path, String contents) async {
  try {
    final f = File(path);
    await f.create(recursive: true);
    await f.writeAsString(contents);
    return path;
  } catch (_) {
    return null;
  }
}

Future<String?> readTextFileImpl(String path) async {
  try {
    return await File(path).readAsString();
  } catch (_) {
    return null;
  }
}
