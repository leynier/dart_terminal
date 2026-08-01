import 'dart:io';

/// Returns the environment used by processes operating on a staged Ghostty
/// source tree.
///
/// The staging tree deliberately has no `.git` directory. Without a ceiling,
/// Git walks through the consuming project and can find an unrelated parent
/// repository, causing Ghostty's version detection to abort on its tag.
Map<String, String> ghosttySourceProcessEnvironment(
  Directory workingDirectory, {
  Map<String, String>? baseEnvironment,
}) {
  return <String, String>{
    ...(baseEnvironment ?? Platform.environment),
    'GIT_CEILING_DIRECTORIES': workingDirectory.parent.absolute.path,
  };
}
