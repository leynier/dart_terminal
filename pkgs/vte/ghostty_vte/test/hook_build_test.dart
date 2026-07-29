import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:test/test.dart';

import '../hook/build.dart' as build_hook;
import 'package:ghostty_vte/src/hook/source_build_tree.dart'
    as source_build_tree;
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
    test('uses emulated TLS compatible Android targets', () {
      expect(
        build_hook.zigTargetForBuildHook(OS.android, Architecture.arm),
        'arm-linux-androideabi.21',
      );
      expect(
        build_hook.zigTargetForBuildHook(OS.android, Architecture.arm64),
        'aarch64-linux-android.21',
      );
      expect(
        build_hook.zigTargetForBuildHook(OS.android, Architecture.x64),
        'x86_64-linux-android.21',
      );
      expect(
        build_hook.zigTargetForBuildHook(OS.android, Architecture.ia32),
        'x86-linux-android.21',
      );
    });

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

  group('prepareGhosttySourceBuildTree', () {
    late Directory temp;
    late Directory source;
    late Directory output;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('ghostty_source_tree_');
      source = Directory('${temp.path}${Platform.pathSeparator}source')
        ..createSync();
      output = Directory('${temp.path}${Platform.pathSeparator}output')
        ..createSync();
    });

    tearDown(() => temp.deleteSync(recursive: true));

    File sourceFile(String relativePath, String contents) {
      final file = File(
        '${source.path}${Platform.pathSeparator}'
        '${relativePath.replaceAll('/', Platform.pathSeparator)}',
      );
      file.parent.createSync(recursive: true);
      return file..writeAsStringSync(contents);
    }

    String unpatchedGhosttyLibVt() => '''
fn initLib(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    zig: anytype,
) void {
    const lib = b.addLibrary(.{
        .root_module = zig.vt_c,
        .version = zig.version,
    });
    lib.installHeadersDirectory(
        b.path("include/ghostty"),
        "ghostty",
        .{},
    );
}
''';

    Directory prepare() => source_build_tree.prepareGhosttySourceBuildTree(
      packageRoot: Directory.current,
      sourceRoot: source,
      outputDirectory: output,
    );

    test('patches a staged copy without modifying the source checkout', () {
      final original = sourceFile(
        'src/build/GhosttyLibVt.zig',
        unpatchedGhosttyLibVt(),
      );
      final originalBytes = original.readAsBytesSync();

      final staged = prepare();
      final stagedFile = File(
        '${staged.path}${Platform.pathSeparator}src'
        '${Platform.pathSeparator}build'
        '${Platform.pathSeparator}GhosttyLibVt.zig',
      );

      expect(stagedFile.readAsStringSync(), contains('link_libc = true'));
      expect(original.readAsBytesSync(), originalBytes);
    });

    test('patches output nested inside an unrelated Git checkout', () {
      final repository = Directory(
        '${temp.path}${Platform.pathSeparator}repository',
      )..createSync();
      final initialized = Process.runSync('git', <String>[
        'init',
      ], workingDirectory: repository.path);
      expect(initialized.exitCode, 0);
      source = Directory('${repository.path}${Platform.pathSeparator}source')
        ..createSync();
      output = Directory('${repository.path}${Platform.pathSeparator}output')
        ..createSync();
      final original = sourceFile(
        'src/build/GhosttyLibVt.zig',
        unpatchedGhosttyLibVt(),
      );
      final originalBytes = original.readAsBytesSync();

      final staged = prepare();

      expect(
        File(
          '${staged.path}${Platform.pathSeparator}src'
          '${Platform.pathSeparator}build'
          '${Platform.pathSeparator}GhosttyLibVt.zig',
        ).readAsStringSync(),
        contains('link_libc = true'),
      );
      expect(original.readAsBytesSync(), originalBytes);
    });

    test('copies local source edits and excludes root metadata and caches', () {
      sourceFile('src/build/GhosttyLibVt.zig', unpatchedGhosttyLibVt());
      sourceFile('src/local-change.zig', 'const local_change = true;\n');
      for (final name in <String>[
        '.git',
        '.zig-cache',
        'build-cmake',
        'zig-cache',
        'zig-out',
        'zig-pkg',
      ]) {
        sourceFile('$name/ignored', 'ignored');
      }

      final staged = prepare();

      expect(
        File(
          '${staged.path}${Platform.pathSeparator}src'
          '${Platform.pathSeparator}local-change.zig',
        ).readAsStringSync(),
        'const local_change = true;\n',
      );
      for (final name in <String>[
        '.git',
        '.zig-cache',
        'build-cmake',
        'zig-cache',
        'zig-out',
        'zig-pkg',
      ]) {
        expect(
          FileSystemEntity.typeSync(
            '${staged.path}${Platform.pathSeparator}$name',
            followLinks: false,
          ),
          FileSystemEntityType.notFound,
        );
      }
    });

    test('accepts a source checkout where the patch is already applied', () {
      final original = sourceFile(
        'src/build/GhosttyLibVt.zig',
        unpatchedGhosttyLibVt(),
      );
      source_patches.applyBundledGhosttyPatches(
        packageRoot: Directory.current,
        ghosttyRoot: source,
      );
      final patchedBytes = original.readAsBytesSync();

      final staged = prepare();

      expect(
        File(
          '${staged.path}${Platform.pathSeparator}src'
          '${Platform.pathSeparator}build'
          '${Platform.pathSeparator}GhosttyLibVt.zig',
        ).readAsBytesSync(),
        patchedBytes,
      );
      expect(original.readAsBytesSync(), patchedBytes);
    });

    test(
      'leaves the source and final output untouched when patching fails',
      () {
        final original = sourceFile(
          'src/build/GhosttyLibVt.zig',
          'const incompatible_source = true;\n',
        );
        final existingOutput = File(
          '${output.path}${Platform.pathSeparator}ghostty-source'
          '${Platform.pathSeparator}existing',
        );
        existingOutput.parent.createSync();
        existingOutput.writeAsStringSync('keep');
        final originalBytes = original.readAsBytesSync();

        expect(prepare, throwsA(isA<StateError>()));
        expect(original.readAsBytesSync(), originalBytes);
        expect(existingOutput.readAsStringSync(), 'keep');
        expect(
          output.listSync().where(
            (entity) => entity.path.contains('ghostty-source-staging-'),
          ),
          isEmpty,
        );
      },
    );

    test('preserves symbolic links when the platform permits them', () {
      sourceFile('src/build/GhosttyLibVt.zig', unpatchedGhosttyLibVt());
      sourceFile('src/link-target.zig', 'const linked = true;\n');
      final link = Link(
        '${source.path}${Platform.pathSeparator}src'
        '${Platform.pathSeparator}link.zig',
      );
      try {
        link.createSync('link-target.zig');
      } on FileSystemException {
        markTestSkipped('Symbolic links are unavailable on this platform.');
        return;
      }

      final staged = prepare();
      final stagedLink = Link(
        '${staged.path}${Platform.pathSeparator}src'
        '${Platform.pathSeparator}link.zig',
      );

      expect(stagedLink.targetSync(), 'link-target.zig');
      expect(
        FileSystemEntity.typeSync(stagedLink.path, followLinks: false),
        FileSystemEntityType.link,
      );
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
