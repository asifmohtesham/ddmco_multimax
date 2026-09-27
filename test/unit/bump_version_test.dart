import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/bump_version.dart';

/// Classifies [messages] on the commit signal alone (no diff, no override).
Bump bumpFor(List<String> messages) =>
    classify(messages, const [], const [], null).bump;

void main() {
  group('classify — diff signal', () {
    test('a fix that adds helper files to an existing module stays PATCH', () {
      final result = classify(
        ['fix(auth): single-dialog logout feedback'],
        [
          'lib/app/modules/auth/authentication_controller.dart',
          'lib/app/modules/auth/logout_flow.dart',
          'lib/app/modules/auth/widgets/logout_dialog.dart',
          'test/unit/logout_flow_test.dart',
        ],
        const [],
        null,
      );

      expect(result.bump, Bump.patch);
    });

    test('a fix that adds a whole new module is MINOR and names the module',
        () {
      final result = classify(
        ['fix: add foo'],
        ['lib/app/modules/foo/foo_screen.dart'],
        ['lib/app/modules/foo'],
        null,
      );

      expect(result.bump, Bump.minor);
      expect(result.reasons.join('\n'), contains('lib/app/modules/foo'));
    });

    test('a new module does not downgrade a breaking commit', () {
      final result = classify(
        ['feat!: replace foo'],
        ['lib/app/modules/foo/foo_screen.dart'],
        ['lib/app/modules/foo'],
        null,
      );

      expect(result.bump, Bump.major);
    });
  });

  group('classify — breaking-change detection', () {
    test('a prose mention of a breaking change in the subject is not breaking',
        () {
      expect(
        bumpFor([
          'fix: pin html package to 0.15.6 to avoid matches() breaking change '
              'in flutter_html',
        ]),
        Bump.patch,
      );
    });

    test('an uppercase mid-line mention is not a footer', () {
      expect(
        bumpFor([
          'fix: pin html package\n\n'
              'Upstream shipped a BREAKING CHANGE: matches() was removed.',
        ]),
        Bump.patch,
      );
    });

    test('a lowercase "breaking change:" line is not a footer', () {
      expect(
        bumpFor(['fix: pin html package\n\nbreaking change: none for us']),
        Bump.patch,
      );
    });

    test('feat! in the subject is breaking', () {
      expect(bumpFor(['feat!: drop legacy DN sync']), Bump.major);
    });

    test('a scoped type with ! in the subject is breaking', () {
      expect(bumpFor(['fix(auth)!: force re-login']), Bump.major);
    });

    test('a BREAKING CHANGE: footer is breaking', () {
      expect(
        bumpFor([
          'feat: move DN sync to the v15 endpoint\n\n'
              'Uses the new bulk API.\n\n'
              'BREAKING CHANGE: requires ERPNext v15.x',
        ]),
        Bump.major,
      );
    });

    test('a BREAKING-CHANGE: footer is breaking', () {
      expect(
        bumpFor(['fix: rework session store\n\nBREAKING-CHANGE: forces re-login']),
        Bump.major,
      );
    });

    test('the type is read from the subject, not from body lines', () {
      expect(
        bumpFor(['fix: squash follow-ups\n\nfeat: not a real feature line']),
        Bump.patch,
      );
    });
  });

  group('git readers', () {
    late Directory repo;

    void git(List<String> args) {
      final r = Process.runSync(
        'git',
        [
          '-c', 'user.name=Test',
          '-c', 'user.email=test@example.com',
          '-c', 'commit.gpgsign=false',
          '-c', 'tag.gpgsign=false',
          '-c', 'core.hooksPath=/dev/null',
          ...args,
        ],
        workingDirectory: repo.path,
      );
      if (r.exitCode != 0) fail('git ${args.join(' ')} failed: ${r.stderr}');
    }

    void commitFile(String path, String message) {
      File('${repo.path}/$path')
        ..createSync(recursive: true)
        ..writeAsStringSync('// $path\n');
      git(['add', path]);
      git(['commit', '-q', '-m', message]);
    }

    setUp(() {
      repo = Directory.systemTemp.createTempSync('bump_version_test_');
      git(['init', '-q']);
      commitFile('lib/app/modules/auth/login_screen.dart', 'chore: base');
      git(['tag', 'v0.0.1']);
    });

    tearDown(() => repo.deleteSync(recursive: true));

    test('a footer in the commit body reaches the classifier', () {
      git([
        'commit', '-q', '--allow-empty',
        '-m', 'feat: move DN sync to the v15 endpoint',
        '-m', 'BREAKING CHANGE: requires ERPNext v15.x',
      ]);

      final messages =
          commitMessages('v0.0.1..HEAD', workingDirectory: repo.path);

      expect(messages, hasLength(1));
      expect(bumpFor(messages), Bump.major);
    });

    test('a multi-line body still counts as one commit', () {
      git([
        'commit', '-q', '--allow-empty',
        '-m', 'fix(auth): single-dialog logout feedback',
        '-m', 'First paragraph.\n\n- bullet one\n- bullet two',
      ]);
      git(['commit', '-q', '--allow-empty', '-m', 'fix: pin html package']);

      final messages =
          commitMessages('v0.0.1..HEAD', workingDirectory: repo.path);

      expect(messages, hasLength(2));
      expect(bumpFor(messages), Bump.patch);
    });

    test('newModuleDirs reports a module directory absent at the base tag',
        () {
      commitFile('lib/app/modules/foo/foo_screen.dart', 'fix: add foo');

      expect(
        newModuleDirs('v0.0.1', workingDirectory: repo.path),
        ['lib/app/modules/foo'],
      );
    });

    test('newModuleDirs ignores files added inside an existing module', () {
      commitFile('lib/app/modules/auth/logout_flow.dart', 'fix(auth): logout');
      commitFile(
          'lib/app/modules/auth/widgets/logout_dialog.dart', 'fix(auth): dialog');

      expect(newModuleDirs('v0.0.1', workingDirectory: repo.path), isEmpty);
    });

    test('newModuleDirs treats every module as new when there is no base tag',
        () {
      expect(
        newModuleDirs(null, workingDirectory: repo.path),
        ['lib/app/modules/auth'],
      );
    });
  });
}
