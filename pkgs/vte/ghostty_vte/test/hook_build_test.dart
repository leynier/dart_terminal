import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:test/test.dart';

import '../hook/build.dart' as build_hook;
import 'package:ghostty_vte/src/hook/source_patches.dart' as source_patches;

void main() {
  group('isPubCachePackagePath', () {
    test('recognizes Unix pub cache paths', () {
      expect(
        build_hook.isPubCachePackagePath(
          '/home/me/.pub-cache/hosted/pub.dev/ghostty_vte-0.1.2',
        ),
        isTrue,
      );
    });

    test('recognizes Windows Pub Cache paths', () {
      expect(
        build_hook.isPubCachePackagePath(
          r'C:\Users\me\AppData\Local\Pub\Cache\hosted\pub.dev\ghostty_vte-0.1.2',
        ),
        isTrue,
      );
    });

    test('recognizes Puro pub_cache paths', () {
      expect(
        build_hook.isPubCachePackagePath(
          '/Users/me/.puro/shared/pub_cache/hosted/pub.dev/ghostty_vte-0.1.3',
        ),
        isTrue,
      );
    });

    test('does not classify local checkouts as pub cache paths', () {
      expect(
        build_hook.isPubCachePackagePath('/work/dart_terminal/pkgs/vte'),
        isFalse,
      );
    });

    test('does not treat hosted pub.dev segments as a cache by itself', () {
      expect(
        build_hook.isPubCachePackagePath(
          '/work/fixtures/hosted/pub.dev/ghostty_vte',
        ),
        isFalse,
      );
    });
  });

  group('shouldPreferSourceBuildForPackagePath', () {
    test('does not prefer source builds for pub cache packages', () {
      expect(
        build_hook.shouldPreferSourceBuildForPackagePath(
          '/Users/me/.pub-cache/hosted/pub.dev/ghostty_vte-0.1.3',
          hasGhosttySourceRoot: true,
        ),
        isFalse,
      );
    });

    test(
      'does not prefer source builds for local packages without Ghostty',
      () {
        expect(
          build_hook.shouldPreferSourceBuildForPackagePath(
            '/work/alera/third_party/dart_terminal/pkgs/vte/ghostty_vte',
            hasGhosttySourceRoot: false,
          ),
          isFalse,
        );
      },
    );

    test('prefers source builds for local packages with Ghostty source', () {
      expect(
        build_hook.shouldPreferSourceBuildForPackagePath(
          '/work/dart_terminal/pkgs/vte/ghostty_vte',
          hasGhosttySourceRoot: true,
        ),
        isTrue,
      );
    });
  });

  group('platformLabelForBuildHook', () {
    test('labels iOS device and simulator targets distinctly', () {
      expect(
        build_hook.platformLabelForBuildHook(
          OS.iOS,
          Architecture.arm64,
          iOSSdk: IOSSdk.iPhoneOS,
        ),
        'ios-arm64',
      );
      expect(
        build_hook.platformLabelForBuildHook(OS.iOS, Architecture.arm64),
        'ios-arm64',
      );
      expect(
        build_hook.platformLabelForBuildHook(
          OS.iOS,
          Architecture.arm64,
          iOSSdk: IOSSdk.iPhoneSimulator,
        ),
        'ios-sim-arm64',
      );
      expect(
        build_hook.platformLabelForBuildHook(OS.iOS, Architecture.x64),
        'ios-sim-x64',
      );
    });
  });

  group('zigTargetForBuildHook', () {
    test('maps iOS device and simulator targets to Zig triples', () {
      expect(
        build_hook.zigTargetForBuildHook(
          OS.iOS,
          Architecture.arm64,
          iOSSdk: IOSSdk.iPhoneOS,
        ),
        'aarch64-ios',
      );
      expect(
        build_hook.zigTargetForBuildHook(
          OS.iOS,
          Architecture.arm64,
          iOSSdk: IOSSdk.iPhoneSimulator,
        ),
        'aarch64-ios-simulator',
      );
      expect(
        build_hook.zigTargetForBuildHook(OS.iOS, Architecture.x64),
        'x86_64-ios-simulator',
      );
    });
  });

  // A Windows checkout resolves .patch files through core.autocrlf while the
  // ghostty sources they apply to are pinned to LF, so `git apply` rejects
  // them. This is the guard for that, and it cannot be reproduced on a Linux
  // runner.
  group('stripCarriageReturnsBeforeNewlines', () {
    List<int> bytesOf(String text) => text.codeUnits;

    test('rewrites CRLF to LF', () {
      expect(
        source_patches.stripCarriageReturnsBeforeNewlines(
          bytesOf('--- a/x\r\n+++ b/x\r\n'),
        ),
        bytesOf('--- a/x\n+++ b/x\n'),
      );
    });

    test('leaves LF-only content untouched', () {
      final bytes = bytesOf('--- a/x\n+++ b/x\n');

      expect(source_patches.stripCarriageReturnsBeforeNewlines(bytes), bytes);
    });

    test('keeps a carriage return that is not part of a line ending', () {
      final bytes = bytesOf('+literal \r inside\n');

      expect(source_patches.stripCarriageReturnsBeforeNewlines(bytes), bytes);
    });

    test('keeps a trailing carriage return', () {
      final bytes = bytesOf('+trailing\r');

      expect(source_patches.stripCarriageReturnsBeforeNewlines(bytes), bytes);
    });
  });

  // Zig installs a Windows DLL under bin/ and leaves only the import library in
  // lib/. Searching lib/ alone finds a .lib that cannot be loaded, which is how
  // this broke on CI.
  group('resolveBuiltLibrary', () {
    const elfHeader = <int>[0x7F, 0x45, 0x4C, 0x46, 0x02, 0x01, 0x01, 0x00];
    const peHeader = <int>[0x4D, 0x5A, 0x90, 0x00, 0x03, 0x00, 0x00, 0x00];
    const archiveHeader = <int>[0x21, 0x3C, 0x61, 0x72, 0x63, 0x68, 0x3E, 0x0A];

    late Directory prefix;

    setUp(() => prefix = Directory.systemTemp.createTempSync('vte_prefix_'));
    tearDown(() => prefix.deleteSync(recursive: true));

    Directory subdir(String name) =>
        Directory('${prefix.path}${Platform.pathSeparator}$name')
          ..createSync(recursive: true);

    test('finds a windows dll in bin/ next to an import library in lib/', () {
      File(
        '${subdir('lib').path}${Platform.pathSeparator}ghostty-vt.lib',
      ).writeAsBytesSync(archiveHeader);
      File(
        '${subdir('bin').path}${Platform.pathSeparator}ghostty-vt.dll',
      ).writeAsBytesSync(peHeader);

      expect(
        build_hook.resolveBuiltLibrary(prefix, 'ghostty-vt.dll').toFilePath(),
        endsWith('bin${Platform.pathSeparator}ghostty-vt.dll'),
      );
    });

    test('still prefers lib/ for unix shared objects', () {
      File(
        '${subdir('lib').path}${Platform.pathSeparator}libghostty-vt.so',
      ).writeAsBytesSync(elfHeader);

      expect(
        build_hook.resolveBuiltLibrary(prefix, 'libghostty-vt.so').toFilePath(),
        endsWith('lib${Platform.pathSeparator}libghostty-vt.so'),
      );
    });

    test('reports every directory it searched when nothing is loadable', () {
      File(
        '${subdir('lib').path}${Platform.pathSeparator}ghostty-vt.lib',
      ).writeAsBytesSync(archiveHeader);
      subdir('bin');

      expect(
        () => build_hook.resolveBuiltLibrary(prefix, 'ghostty-vt.dll'),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            allOf(contains('lib'), contains('bin')),
          ),
        ),
      );
    });
  });
}
