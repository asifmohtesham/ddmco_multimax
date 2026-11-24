import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:multimax/app/data/services/native_intake.dart';

/// Cleans up copies from the cache or native intake folders. Paths outside
/// these folders, including the gallery originals, are left alone.
Future<void> deleteIntakePhotoCopies(
  List<String> paths, {
  Future<Directory> Function() tempDir = getTemporaryDirectory,
  Future<List<String>> Function()? extraCleanupRoots,
  required void Function(String, Object, StackTrace) log,
}) async {
  if (paths.isEmpty) return;
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
  for (final path in paths) {
    final full = p.normalize(p.absolute(path));
    if (!roots.any((root) => p.isWithin(root, full))) continue;
    try {
      final file = File(full);
      if (await file.exists()) await file.delete();
    } catch (e, st) {
      log('could not delete $full', e, st);
    }
  }
}
