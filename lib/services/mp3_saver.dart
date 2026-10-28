import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The chosen destination folder is not writable (e.g. iOS revoked access
/// after the app restarted) and has to be picked again.
class FolderAccessException implements Exception {
  @override
  String toString() =>
      'Sem acesso à pasta escolhida. Escolha a pasta novamente.';
}

/// Stores finished MP3 files on the device.
///
/// * Android: `Music/<playlist>/` through MediaStore (no permissions needed).
/// * iOS / desktop: inside a folder chosen by the user (defaults to the app's
///   Documents folder on iOS, which is visible in the Files app, and to
///   Downloads on desktop).
class Mp3Saver {
  static const _channel = MethodChannel('mp3_saver');
  static const _prefKey = 'save_dir';
  String? lastSavedPath;

  static const _folderAccess = MethodChannel('folder_access');

  /// Whether the user can pick the destination folder on this platform.
  static bool get canChooseFolder => !Platform.isAndroid;

  /// The folder used when the user has not picked one yet.
  Future<String> defaultDirectory() async {
    final dir = Platform.isIOS
        ? await getApplicationDocumentsDirectory()
        : await getDownloadsDirectory() ??
              await getApplicationDocumentsDirectory();
    return dir.path;
  }

  Future<String?> savedDirectory() async {
    if (Platform.isMacOS) {
      // The sandbox forgets the permission when the app closes; the stored
      // bookmark brings it back without asking the user again.
      try {
        final restored = await _folderAccess.invokeMethod<String>(
          'restoreBookmark',
        );
        if (restored != null) return restored;
      } on PlatformException {
        // fall through to the plain path
      }
    }
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefKey);
  }

  /// Opens the native folder picker and remembers the choice.
  /// Returns `null` when the user cancels.
  Future<String?> pickDirectory({String? initial}) async {
    final path = await FilePicker.getDirectoryPath(
      dialogTitle: 'Escolher a pasta das músicas',
      initialDirectory: initial,
    );
    if (path == null || path.isEmpty) return null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, path);
    if (Platform.isMacOS) {
      try {
        await _folderAccess.invokeMethod<bool>('saveBookmark', path);
      } on PlatformException catch (e) {
        debugPrint('Não foi possível guardar o acesso à pasta: ${e.message}');
      }
    }
    return path;
  }

  /// Throws [FolderAccessException] if [baseDir] cannot be written to.
  Future<void> verifyWritable(String baseDir) async {
    try {
      final dir = Directory(baseDir);
      await dir.create(recursive: true);
      final probe = File('${dir.path}/.write_test');
      await probe.writeAsString('ok');
      await probe.delete();
    } on FileSystemException {
      throw FolderAccessException();
    }
  }

  /// Stores the original thumbnail next to the MP3 for the in-app player.
  /// It is already embedded in the MP3; this sidecar is for fast local artwork
  /// loading in the player and can be removed without affecting the audio.
  Future<String?> saveArtwork({
    required String tempPath,
    required String fileName,
    required String folder,
    String? baseDir,
  }) async {
    if (Platform.isAndroid) return null;
    final root = baseDir ?? await defaultDirectory();
    final dir = Directory('$root${Platform.pathSeparator}$folder');
    try {
      await dir.create(recursive: true);
      final saved = await File(
        tempPath,
      ).copy('${dir.path}${Platform.pathSeparator}$fileName');
      return saved.path;
    } on FileSystemException {
      return null;
    }
  }

  /// Copies [tempPath] into the destination and returns where it was stored.
  Future<String> save({
    required String tempPath,
    required String fileName,
    required String folder,
    String? baseDir,
  }) async {
    if (Platform.isAndroid) {
      final response = await _channel.invokeMethod<dynamic>('saveToMusic', {
        'path': tempPath,
        'name': fileName,
        'folder': folder,
      });
      final location = response is Map
          ? response['location'] as String?
          : response as String?;
      final uri = response is Map ? response['uri'] as String? : location;
      lastSavedPath = uri;
      return location ?? 'Music/$folder';
    }

    final root = baseDir ?? await defaultDirectory();
    final dir = Directory('$root${Platform.pathSeparator}$folder');
    try {
      await dir.create(recursive: true);
      final saved = await File(
        tempPath,
      ).copy('${dir.path}${Platform.pathSeparator}$fileName');
      lastSavedPath = saved.path;
    } on FileSystemException {
      throw FolderAccessException();
    }
    return dir.path;
  }
}
