import 'file_store_stub.dart' if (dart.library.io) 'file_store_io.dart';

/// Whether the platform supports real filesystem access.
bool get fileStoreSupported => fileStoreSupportedImpl;

/// Writes [contents] to [path]. Returns the path written, or null on failure.
Future<String?> saveTextFile(String path, String contents) => saveTextFileImpl(path, contents);

/// Reads a text file at [path]. Returns null on failure.
Future<String?> readTextFile(String path) => readTextFileImpl(path);
