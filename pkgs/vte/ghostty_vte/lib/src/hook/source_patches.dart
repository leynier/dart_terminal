import 'dart:io';

typedef PatchLogger = void Function(String message);

const List<String> bundledGhosttyPatchPaths = <String>[
  'patches/ghostty-libvt-link-libc.patch',
];

void applyBundledGhosttyPatches({
  required Directory packageRoot,
  required Directory ghosttyRoot,
  PatchLogger? info,
  PatchLogger? warn,
}) {
  for (final relativePath in bundledGhosttyPatchPaths) {
    final patchFile = File.fromUri(packageRoot.uri.resolve(relativePath));
    if (!patchFile.existsSync()) {
      throw StateError('Missing bundled patch: ${patchFile.path}');
    }
    applyPatchFile(
      patchFile: patchFile,
      workingDirectory: ghosttyRoot,
      info: info,
      warn: warn,
    );
  }
}

void applyPatchFile({
  required File patchFile,
  required Directory workingDirectory,
  PatchLogger? info,
  PatchLogger? warn,
}) {
  final normalized = _normalizedPatchFile(patchFile);
  final environment = <String, String>{
    ...Platform.environment,
    // Hook outputs can live below the consuming repository. Prevent git apply
    // from discovering that unrelated index and silently skipping every path.
    'GIT_CEILING_DIRECTORIES': workingDirectory.parent.absolute.path,
  };
  try {
    final alreadyApplied = Process.runSync(
      'git',
      <String>['apply', '--reverse', '--check', normalized.path],
      workingDirectory: workingDirectory.path,
      environment: environment,
      runInShell: true,
    );
    if (alreadyApplied.exitCode == 0) {
      info?.call(
        'Source patch already applied: ${patchFile.uri.pathSegments.last}',
      );
      return;
    }

    final check = Process.runSync(
      'git',
      <String>['apply', '--check', normalized.path],
      workingDirectory: workingDirectory.path,
      environment: environment,
      runInShell: true,
    );
    if (check.exitCode != 0) {
      throw StateError(
        'Failed to validate patch ${patchFile.path}.\n'
        'stdout:\n${check.stdout}\n'
        'stderr:\n${check.stderr}',
      );
    }

    final apply = Process.runSync(
      'git',
      <String>['apply', normalized.path],
      workingDirectory: workingDirectory.path,
      environment: environment,
      runInShell: true,
    );
    if (apply.exitCode != 0) {
      throw StateError(
        'Failed to apply patch ${patchFile.path}.\n'
        'stdout:\n${apply.stdout}\n'
        'stderr:\n${apply.stderr}',
      );
    }

    info?.call('Applied source patch: ${patchFile.uri.pathSegments.last}');
    if (warn != null &&
        (apply.stdout as String).trim().isNotEmpty &&
        (apply.stderr as String).trim().isNotEmpty) {
      warn('Patch emitted output while applying ${patchFile.path}.');
    }
  } finally {
    if (normalized.path != patchFile.path) {
      try {
        normalized.parent.deleteSync(recursive: true);
      } on FileSystemException {
        // A leftover temp directory is not worth failing a build over.
      }
    }
  }
}

/// Returns [patchFile] with CRLF line endings rewritten to LF, copying it to a
/// temp file when a rewrite is needed.
///
/// A Windows checkout resolves `.patch` files through `core.autocrlf` and hands
/// them to git with CRLF endings, while the ghostty sources they apply to are
/// pinned to LF by that repository's own `.gitattributes`. `git apply` compares
/// the bytes and rejects the patch. Normalizing here keeps the outcome the same
/// whatever the consumer's checkout settings are.
File _normalizedPatchFile(File patchFile) {
  final bytes = patchFile.readAsBytesSync();
  final normalizedBytes = stripCarriageReturnsBeforeNewlines(bytes);
  if (normalizedBytes.length == bytes.length) {
    return patchFile;
  }

  final tempDir = Directory.systemTemp.createTempSync('ghostty_vte_patch_');
  final normalized = File(
    '${tempDir.path}${Platform.pathSeparator}'
    '${patchFile.uri.pathSegments.last}',
  );
  normalized.writeAsBytesSync(normalizedBytes);
  return normalized;
}

/// Rewrites CRLF to LF, leaving a lone CR alone so a patch that genuinely adds
/// one keeps working.
List<int> stripCarriageReturnsBeforeNewlines(List<int> bytes) {
  final out = <int>[];
  for (var i = 0; i < bytes.length; i++) {
    if (bytes[i] == 0x0D && i + 1 < bytes.length && bytes[i + 1] == 0x0A) {
      continue;
    }
    out.add(bytes[i]);
  }
  return out;
}
