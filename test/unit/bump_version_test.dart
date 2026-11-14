import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/bump_version.dart';

/// Classifies [messages] on the commit signal alone (no diff, no override).
Bump bumpFor(List<String> messages) =>
    classify(messages, const [], const [], null).bump;

/// Guard verdict for [proposed] against [releases]; empty means safe to write.
List<String> collisionsFor(
  String proposed,
  List<Release> releases, {
  Bump bump = Bump.patch,
  String? baseTag,
}) =>
    releaseCollisions(
      proposed: Version.parse(proposed),
      bump: bump,
      baseTag: baseTag,
      releases: releases,
    );

/// A release tag; [pubspec] is the `version:` of pubspec.yaml at that tag.
Release released(String tag, {String? pubspec, bool reachable = true}) =>
    Release(
      tag,
      pubspec: pubspec == null ? null : Version.parse(pubspec),
      reachable: reachable,
    );

void main() {
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

  void commitFile(String path, String message, {String? content}) {
    File('${repo.path}/$path')
      ..createSync(recursive: true)
      ..writeAsStringSync(content ?? '// $path\n');
    git(['add', path]);
    git(['commit', '-q', '-m', message]);
  }

  void commitPubspec(String version) => commitFile(
        'pubspec.yaml',
        'chore(release): bump version to $version',
        content: 'name: app\nversion: $version\n',
      );

  String pubspecVersion() => File('${repo.path}/pubspec.yaml')
      .readAsLinesSync()
      .firstWhere((l) => l.startsWith('version:'))
      .substring('version:'.length)
      .trim();

  /// Rebuilds the 2026-09-27 incident: `feature` forks from v2.25.6, then
  /// `release` ships v2.25.7+85 without `feature` catching up. Leaves HEAD on
  /// `feature`, one commit past the fork.
  void shipReleasePastFeature() {
    commitPubspec('2.25.6+84');
    git(['tag', 'v2.25.6']);
    git(['branch', 'feature']);
    git(['checkout', '-q', '-b', 'release']);
    commitPubspec('2.25.7+85');
    git(['tag', '-a', 'v2.25.7', '-m', 'v2.25.7']);
    git(['checkout', '-q', 'feature']);
    commitFile('tool/helper.dart', 'fix(tool): tidy helper');
  }

  /// A throwaway repo per test: one commit, tagged v0.0.1 (no pubspec.yaml).
  void useTempRepo() {
    setUp(() {
      repo = Directory.systemTemp.createTempSync('bump_version_test_');
      git(['init', '-q']);
      commitFile('lib/app/modules/auth/login_screen.dart', 'chore: base');
      git(['tag', 'v0.0.1']);
    });

    tearDown(() => repo.deleteSync(recursive: true));
  }

  group('releaseCollisions', () {
    test('no existing releases means nothing to collide with', () {
      expect(collisionsFor('1.0.0+1', const []), isEmpty);
    });

    test('a proposal above every release on a current branch is safe', () {
      final releases = [
        released('v2.25.6', pubspec: '2.25.6+84'),
        released('v2.25.7', pubspec: '2.25.7+85'),
      ];

      expect(
        collisionsFor('2.25.8+86', releases, baseTag: 'v2.25.7'),
        isEmpty,
      );
    });

    test('a newer tag that HEAD does not contain is reported by name', () {
      final releases = [
        released('v2.25.6', pubspec: '2.25.6+84'),
        released('v2.25.7', pubspec: '2.25.7+85', reachable: false),
      ];

      // The proposal itself is numerically clear of v2.25.7: only the missing
      // ancestry is wrong.
      final problems =
          collisionsFor('2.26.0+90', releases, baseTag: 'v2.25.6');

      expect(problems, hasLength(1));
      expect(problems.single, contains('v2.25.7'));
      expect(problems.single, contains('not an ancestor of HEAD'));
    });

    test('an unreachable tag older than the base tag is not a problem', () {
      final releases = [
        released('v2.0.0+20', pubspec: '2.0.0+20', reachable: false),
        released('v2.25.7', pubspec: '2.25.7+85'),
      ];

      expect(
        collisionsFor('2.25.8+86', releases, baseTag: 'v2.25.7'),
        isEmpty,
      );
    });

    test('any unreachable tag counts as newer when HEAD reaches no tag', () {
      final releases = [
        released('v1.0.0', pubspec: '1.0.0+1', reachable: false),
      ];

      final problems = collisionsFor('1.0.1+2', releases);

      expect(problems.join('\n'), contains('v1.0.0'));
    });

    test('reusing a released version is a collision', () {
      final releases = [released('v2.25.7', pubspec: '2.25.7+85')];

      final problems =
          collisionsFor('2.25.7+86', releases, baseTag: 'v2.25.7');

      expect(problems, hasLength(1));
      expect(problems.single, contains('2.25.7'));
      expect(problems.single, contains('v2.25.7'));
    });

    test('reusing a released build number is a collision', () {
      final releases = [released('v2.25.7', pubspec: '2.25.7+85')];

      final problems = collisionsFor('2.26.0+85', releases,
          bump: Bump.minor, baseTag: 'v2.25.7');

      expect(problems, hasLength(1));
      expect(problems.single, contains('85'));
      expect(problems.single, contains('v2.25.7'));
    });

    test('the tag name counts when it is ahead of the pubspec at that tag',
        () {
      // Mirrors the real v2.25.5, whose pubspec.yaml still said 2.25.3+81.
      final releases = [released('v2.25.5', pubspec: '2.25.3+81')];

      final problems =
          collisionsFor('2.25.4+82', releases, baseTag: 'v2.25.5');

      expect(problems.join('\n'), contains('v2.25.5'));
    });

    test('the pubspec at a tag counts when it is ahead of the tag name', () {
      final releases = [released('v1.0.0', pubspec: '1.2.0+9')];

      final problems = collisionsFor('1.1.0+10', releases,
          bump: Bump.minor, baseTag: 'v1.0.0');

      expect(problems.join('\n'), contains('1.2.0+9'));
    });

    test('a build number in the tag name counts without a readable pubspec',
        () {
      final releases = [released('v2.25.1+79')];

      final problems = collisionsFor('2.26.0+79', releases,
          bump: Bump.minor, baseTag: 'v2.25.1+79');

      expect(problems, hasLength(1));
      expect(problems.single, contains('79'));
    });

    test('a build-only release may keep the latest released version', () {
      final releases = [released('v2.25.7', pubspec: '2.25.7+85')];

      expect(
        collisionsFor('2.25.7+86', releases,
            bump: Bump.none, baseTag: 'v2.25.7'),
        isEmpty,
      );
    });

    test('a build-only release may not fall below the latest release', () {
      final releases = [
        released('v2.25.6', pubspec: '2.25.6+84'),
        released('v2.25.7', pubspec: '2.25.7+85'),
      ];

      final problems = collisionsFor('2.25.6+86', releases,
          bump: Bump.none, baseTag: 'v2.25.7');

      expect(problems.join('\n'), contains('v2.25.7'));
    });

    test('duplicates among past releases do not block a clean proposal', () {
      // Real history: three tags share build 81.
      final releases = [
        released('v2.25.3', pubspec: '2.25.3+81'),
        released('v2.25.4', pubspec: '2.25.3+81'),
        released('v2.25.5', pubspec: '2.25.3+81'),
        released('v2.25.6', pubspec: '2.25.6+84'),
      ];

      expect(
        collisionsFor('2.25.7+85', releases, baseTag: 'v2.25.6'),
        isEmpty,
      );
    });

    test('a v* tag that is not a version is ignored', () {
      final releases = [released('v-next', reachable: false)];

      expect(collisionsFor('1.0.0+1', releases), isEmpty);
    });
  });

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
    useTempRepo();

    test('lastReachableTag ignores a newer tag that HEAD does not contain',
        () {
      shipReleasePastFeature();

      expect(lastReachableTag(workingDirectory: repo.path), 'v2.25.6');
    });

    test('lastReachableTag only considers v* tags', () {
      commitFile('lib/a.dart', 'fix: a');
      git(['tag', 'build-1']);

      expect(lastReachableTag(workingDirectory: repo.path), 'v0.0.1');
    });

    test('lastReachableTag is null when HEAD reaches no v* tag', () {
      git(['tag', '-d', 'v0.0.1']);

      expect(lastReachableTag(workingDirectory: repo.path), isNull);
    });

    test('releaseTags reads the pubspec version at each tag', () {
      shipReleasePastFeature();

      final pubspecs = {
        for (final r in releaseTags(workingDirectory: repo.path))
          r.tag: r.pubspec?.toString(),
      };

      expect(pubspecs, {
        'v0.0.1': null, // tagged before pubspec.yaml existed
        'v2.25.6': '2.25.6+84',
        'v2.25.7': '2.25.7+85',
      });
    });

    test('releaseTags marks which tags are ancestors of HEAD', () {
      shipReleasePastFeature();

      final reachable = {
        for (final r in releaseTags(workingDirectory: repo.path))
          r.tag: r.reachable,
      };

      expect(reachable, {'v0.0.1': true, 'v2.25.6': true, 'v2.25.7': false});
    });

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

  group('run', () {
    useTempRepo();

    late StringBuffer out;
    late StringBuffer err;

    setUp(() {
      out = StringBuffer();
      err = StringBuffer();
    });

    int runTool(List<String> args) =>
        run(args, workingDirectory: repo.path, out: out, err: err);

    test('bases the range on the tag HEAD contains, not the newest tag', () {
      shipReleasePastFeature();

      runTool([]);

      expect('$out', contains('Last tag        : v2.25.6'));
      expect('$out', contains('Commits in range: 1'));
    });

    test('a dry-run on a branch behind the latest release warns', () {
      shipReleasePastFeature();

      final code = runTool([]);

      expect(code, 0);
      expect('$out', contains('WARNING'));
      expect('$out', contains('v2.25.7'));
    });

    test('--write is refused on a branch behind the latest release', () {
      shipReleasePastFeature();

      final code = runTool(['--write']);

      expect(code, isNot(0));
      expect('$err', contains('Refusing to write'));
      expect(pubspecVersion(), '2.25.6+84');
    });

    test('an override cannot force a write past the guard', () {
      shipReleasePastFeature();

      final code = runTool(['--major', '--write']);

      expect(code, isNot(0));
      expect(pubspecVersion(), '2.25.6+84');
    });

    test('an unknown argument exits 2 and leaves pubspec.yaml alone', () {
      shipReleasePastFeature();

      final code = runTool(['--wirte']);

      expect(code, 2);
      expect('$err', contains('Unknown argument: --wirte'));
      expect(pubspecVersion(), '2.25.6+84');
    });

    test('--write applies the bump when HEAD contains every release', () {
      shipReleasePastFeature();
      git(['checkout', '-q', 'release']);
      commitFile('lib/a.dart', 'fix: a');

      final code = runTool(['--write']);

      expect(code, 0);
      expect('$out', isNot(contains('WARNING')));
      expect(pubspecVersion(), '2.25.8+86');
    });
  });
}
