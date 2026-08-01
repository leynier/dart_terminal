import 'dart:io';

import 'package:ghostty_vte/src/hook/ghostty_source_environment.dart';
import 'package:test/test.dart';

void main() {
  test('caps Git discovery at the staged source parent', () {
    final sourceRoot = Directory('/tmp/ghostty-hook/build/ghostty-source');

    final environment = ghosttySourceProcessEnvironment(
      sourceRoot,
      baseEnvironment: <String, String>{
        'PATH': '/usr/bin',
        'GIT_CEILING_DIRECTORIES': '/unrelated/parent',
      },
    );

    expect(environment['PATH'], '/usr/bin');
    expect(
      environment['GIT_CEILING_DIRECTORIES'],
      sourceRoot.parent.absolute.path,
    );
  });
}
