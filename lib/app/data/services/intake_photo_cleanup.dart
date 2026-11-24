import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:multimax/app/data/services/native_intake.dart';

typedef IntakePhotoLog = void Function(String, Object, StackTrace);

const _intakeFolder = 'share-intake-photos';
const _copyPrefix = 'photo-';

Directory _intakeDirectory(Directory supportDir) =>
    Directory(p.join(supportDir.path, _intakeFolder));

/// Clears the previous process's staged copies before accepting new shares.
Future<Directory?> prepareIntakePhotoDirectory(
  Future<Directory> Function() supportDir, {
  required IntakePhotoLog log,
}) async {
  try {
    final directory = _intakeDirectory(await supportDir());
    try {
      if (await directory.exists()) await directory.delete(recursive: true);
    } catch (e, st) {
      log('clearing old shared photos failed', e, st);
    }
    return directory;
  } catch (e, st) {
    log('shared photo directory lookup failed', e, st);
    return null;
  }
}

/// Copies a share into app support storage, keeping each filename and giving
/// each incoming photo its own directory. A photo that cannot be copied has a
/// missing file at its private path so the review can still use the others.
Future<List<String>> copyIntakePhotos(
  List<String> paths,
  Directory intakeDirectory, {
  required IntakePhotoLog log,
}) async {
  final copies = <String>[];
  try {
    await intakeDirectory.create(recursive: true);
    for (final path in paths) {
      final folder = await intakeDirectory.createTemp(_copyPrefix);
      final destination = p.join(folder.path, p.basename(path));
      copies.add(destination);
      try {
        await File(path).copy(destination);
      } catch (e, st) {
        log('copying shared photo failed', e, st);
        await _deletePhoto(destination, log);
      }
    }
    return copies;
  } catch (e, st) {
    log('copying shared photos failed', e, st);
    for (final path in copies) {
      await _deleteStagedPhoto(path, log);
    }
    return const [];
  }
}

/// Cleans up owned copies from app support, the cache or native intake folders.
Future<void> deleteIntakePhotoCopies(
  List<String> paths, {
  Future<Directory> Function() tempDir = getTemporaryDirectory,
  Future<Directory> Function()? supportDir,
  Future<List<String>> Function()? extraCleanupRoots,
  required IntakePhotoLog log,
}) async {
  if (paths.isEmpty) return;
  final supportDirectory =
      supportDir ??
      (!kIsWeb && (Platform.isAndroid || Platform.isIOS)
          ? getApplicationSupportDirectory
          : null);
  String? stagedRoot;
  if (supportDirectory != null) {
    try {
      stagedRoot = p.normalize(
        p.absolute(_intakeDirectory(await supportDirectory()).path),
      );
    } catch (e, st) {
      log('shared photo directory lookup failed', e, st);
    }
  }
  final unstaged = <String>[];
  for (final path in paths) {
    final full = p.normalize(p.absolute(path));
    final parent = p.dirname(full);
    if (stagedRoot != null &&
        p.equals(stagedRoot, p.dirname(parent)) &&
        p.basename(parent).startsWith(_copyPrefix)) {
      await _deleteStagedPhoto(full, log);
    } else {
      unstaged.add(full);
    }
  }
  if (unstaged.isEmpty) return;

  final roots = <String>[];
  try {
    roots.add(p.normalize(p.absolute((await tempDir()).path)));
  } catch (e, st) {
    log('temporary folder lookup failed', e, st);
  }
  try {
    final folders =
        await (extraCleanupRoots ?? NativeIntake.instance.sharedFolders)();
    for (final folder in folders) {
      if (folder.isEmpty || !p.isAbsolute(folder)) continue;
      final root = p.normalize(p.absolute(folder));
      // A filesystem root would make every given path deletable.
      if (root != p.rootPrefix(root)) roots.add(root);
    }
  } catch (e, st) {
    log('intake folder lookup failed', e, st);
  }
  for (final full in unstaged) {
    if (roots.any((root) => p.isWithin(root, full))) {
      await _deletePhoto(full, log);
    }
  }
}

Future<void> _deleteStagedPhoto(String path, IntakePhotoLog log) async {
  final folder = Directory(p.dirname(path));
  try {
    if (await FileSystemEntity.type(folder.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      return;
    }
    await _deletePhoto(path, log);
    await folder.delete();
  } catch (e, st) {
    log('could not remove shared photo folder ${folder.path}', e, st);
  }
}

Future<void> _deletePhoto(String path, IntakePhotoLog log) async {
  try {
    final file = File(path);
    if (await file.exists()) await file.delete();
  } catch (e, st) {
    log('could not delete $path', e, st);
  }
}
