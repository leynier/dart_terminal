import 'dart:io';

import 'package:path/path.dart' as p;

import 'source_patches.dart';

const Set<String> _excludedRootEntries = <String>{
  '.git',
  '.zig-cache',
  'build-cmake',
  'zig-cache',
  'zig-out',
  'zig-pkg',
};

Directory prepareGhosttySourceBuildTree({
  required Directory packageRoot,
  required Directory sourceRoot,
  required Directory outputDirectory,
  PatchLogger? info,
  PatchLogger? warn,
}) {
  outputDirectory.createSync(recursive: true);
  final stagingRoot = outputDirectory.createTempSync('ghostty-source-staging-');
  final buildRoot = Directory(p.join(outputDirectory.path, 'ghostty-source'));

  try {
    _copySourceTree(sourceRoot, stagingRoot, isRoot: true);
    applyBundledGhosttyPatches(
      packageRoot: packageRoot,
      ghosttyRoot: stagingRoot,
      info: info,
      warn: warn,
    );

    _deleteIfPresent(buildRoot);
    stagingRoot.renameSync(buildRoot.path);
    return buildRoot;
  } catch (_) {
    _deleteIfPresent(stagingRoot);
    rethrow;
  }
}

void _copySourceTree(
  Directory source,
  Directory destination, {
  required bool isRoot,
}) {
  for (final entity in source.listSync(followLinks: false)) {
    final name = p.basename(entity.path);
    if (isRoot && _excludedRootEntries.contains(name)) {
      continue;
    }

    final destinationPath = p.join(destination.path, name);
    switch (FileSystemEntity.typeSync(entity.path, followLinks: false)) {
      case FileSystemEntityType.directory:
        final childDestination = Directory(destinationPath)
          ..createSync(recursive: true);
        _copySourceTree(
          Directory(entity.path),
          childDestination,
          isRoot: false,
        );
        break;
      case FileSystemEntityType.file:
        File(entity.path).copySync(destinationPath);
        break;
      case FileSystemEntityType.link:
        Link(destinationPath).createSync(Link(entity.path).targetSync());
        break;
      case FileSystemEntityType.notFound:
      case FileSystemEntityType.pipe:
      case FileSystemEntityType.unixDomainSock:
        throw FileSystemException(
          'Unsupported entry in Ghostty source tree',
          entity.path,
        );
    }
  }
}

void _deleteIfPresent(FileSystemEntity entity) {
  if (FileSystemEntity.typeSync(entity.path, followLinks: false) !=
      FileSystemEntityType.notFound) {
    entity.deleteSync(recursive: true);
  }
}
