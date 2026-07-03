// Semantic version bump helper.
//
// Reads the current `version: X.Y.Z+B` from pubspec.yaml, finds the last released
// `v*` tag, classifies every commit since that tag (Conventional-Commit prefix +
// corroborating diff), and proposes the next version per docs/versioning_conventions.md.
//
//   dart run tool/bump_version.dart            # dry-run: classify range, propose version
//   dart run tool/bump_version.dart --write    # apply the auto-classified bump to pubspec.yaml
//   dart run tool/bump_version.dart --minor --write   # override classification, then apply
//   dart run tool/bump_version.dart --since v2.0.20+29 # re-classify a past range (never writes)
//
// Flags: --major / --minor / --patch override the auto-classification.
//        --since <tag>  classify <tag>..HEAD instead of <last-tag>..HEAD (analysis only).
//        --write applies the change; without it the script only prints.
//
// This script is an aid, not an authority. When the diff carries nuance the classifier
// cannot see (a breaking backend requirement, a milestone), override it explicitly.

import 'dart:io';

const _pubspecPath = 'pubspec.yaml';

/// Semver level, ordered low → high so `.index` gives precedence.
enum Bump { none, patch, minor, major }

class Version {
  final int major, minor, patch, build;
  Version(this.major, this.minor, this.patch, this.build);

  static final _re = RegExp(r'^(\d+)\.(\d+)\.(\d+)\+(\d+)$');

  factory Version.parse(String s) {
    final m = _re.firstMatch(s.trim());
    if (m == null) {
      throw FormatException('Cannot parse version "$s" (expected X.Y.Z+B)');
    }
    return Version(
      int.parse(m[1]!),
      int.parse(m[2]!),
      int.parse(m[3]!),
      int.parse(m[4]!),
    );
  }

  /// The build number always increments; the semver fields follow [bump].
  Version next(Bump bump) {
    final b = build + 1;
    switch (bump) {
      case Bump.major:
        return Version(major + 1, 0, 0, b);
      case Bump.minor:
        return Version(major, minor + 1, 0, b);
      case Bump.patch:
        return Version(major, minor, patch + 1, b);
      case Bump.none:
        return Version(major, minor, patch, b);
    }
  }

  @override
  String toString() => '$major.$minor.$patch+$build';
}

void main(List<String> args) {
  var write = false;
  Bump? override;
  String? since;

  for (var i = 0; i < args.length; i++) {
    switch (args[i].toLowerCase()) {
      case '--write':
        write = true;
      case '--major':
        override = Bump.major;
      case '--minor':
        override = Bump.minor;
      case '--patch':
        override = Bump.patch;
      case '--since':
        if (i + 1 >= args.length) {
          stderr.writeln('--since requires a tag argument');
          exit(2);
        }
        since = args[++i];
      default:
        stderr.writeln('Unknown argument: ${args[i]}');
        stderr.writeln('Usage: dart run tool/bump_version.dart '
            '[--major|--minor|--patch] [--since <tag>] [--write]');
        exit(2);
    }
  }

  // --since is an analysis window; it never mutates pubspec.yaml.
  if (since != null && write) {
    stderr.writeln('--since is analysis-only and cannot be combined with --write.');
    exit(2);
  }

  // 1. Current version.
  final pubspec = File(_pubspecPath);
  if (!pubspec.existsSync()) {
    stderr.writeln('$_pubspecPath not found; run from the project root.');
    exit(1);
  }
  final pubspecText = pubspec.readAsStringSync();
  final versionLine =
      RegExp(r'^version:\s*(.+)$', multiLine: true).firstMatch(pubspecText);
  if (versionLine == null) {
    stderr.writeln('No `version:` line in $_pubspecPath.');
    exit(1);
  }
  final current = Version.parse(versionLine.group(1)!);

  // 2. Last released tag and the commit range (--since overrides the base tag).
  final lastTag = since ?? _lastTag();
  final range = lastTag == null ? null : '$lastTag..HEAD';
  final subjects = _commitSubjects(range);
  final changedFiles = _changedFiles(range);

  // 3. Classify.
  final classified = _classify(subjects, changedFiles, override);
  final bump = classified.bump;
  final next = current.next(bump);

  // Report.
  stdout.writeln('Current version : $current');
  stdout.writeln('Last tag        : ${lastTag ?? '(none — using full history)'}');
  stdout.writeln('Commits in range: ${subjects.length}');
  for (final line in classified.reasons) {
    stdout.writeln('  $line');
  }
  final label = override != null ? '${bump.name} (overridden)' : bump.name;
  stdout.writeln('Bump            : $label');
  stdout.writeln('Next version    : $next');

  if (bump == Bump.none && override == null) {
    stdout.writeln(
        'Note            : no functional change detected — only the build number moves.');
  }

  // 4. Apply.
  if (!write) {
    stdout.writeln('\n(dry-run — pass --write to apply)');
    return;
  }
  final updated =
      pubspecText.replaceFirst(versionLine.group(0)!, 'version: $next');
  pubspec.writeAsStringSync(updated);
  stdout.writeln('\nWrote version: $next to $_pubspecPath');
}

/// Newest `v*` tag by commit date, or null if the repo has none.
String? _lastTag() {
  final r = Process.runSync(
      'git', ['tag', '--list', 'v*', '--sort=-creatordate']);
  if (r.exitCode != 0) return null;
  final tags = (r.stdout as String)
      .split('\n')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  return tags.isEmpty ? null : tags.first;
}

List<String> _commitSubjects(String? range) {
  final gitArgs = ['log', '--pretty=%s', if (range != null) range];
  final r = Process.runSync('git', gitArgs);
  if (r.exitCode != 0) return const [];
  return (r.stdout as String)
      .split('\n')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
}

List<String> _changedFiles(String? range) {
  final gitArgs = [
    'diff',
    '--name-only',
    if (range != null) range else 'HEAD',
  ];
  final r = Process.runSync('git', gitArgs);
  if (r.exitCode != 0) return const [];
  return (r.stdout as String)
      .split('\n')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
}

class _Classification {
  final Bump bump;
  final List<String> reasons;
  _Classification(this.bump, this.reasons);
}

/// Leading Conventional-Commit type, e.g. `feat`, `fix`, `feat!`, `chore`.
final _typeRe = RegExp(r'^(\w+)(\([^)]*\))?(!)?:');
final _breakingFooterRe = RegExp(r'BREAKING[ -]CHANGE', caseSensitive: false);

_Classification _classify(
  List<String> subjects,
  List<String> changedFiles,
  Bump? override,
) {
  final reasons = <String>[];

  // Signal 1: commit prefixes.
  var fromCommits = Bump.none;
  for (final s in subjects) {
    final m = _typeRe.firstMatch(s);
    final breaking = (m?.group(3) == '!') || _breakingFooterRe.hasMatch(s);
    final type = m?.group(1)?.toLowerCase();
    Bump level;
    if (breaking) {
      level = Bump.major;
    } else if (type == 'feat') {
      level = Bump.minor;
    } else {
      // fix, perf, refactor, style, docs, chore, test, or unprefixed.
      level = Bump.patch;
    }
    if (level.index > fromCommits.index) fromCommits = level;
  }
  reasons.add('commit prefixes suggest: ${fromCommits.name}');

  // Signal 2: the diff. A new module directory means a feature even if the
  // commit was labelled `fix`; a range that only touches docs/tests is chore.
  final addsModule = changedFiles.any(
      (f) => f.startsWith('lib/app/modules/') && !f.contains('/test'));
  final onlyDocsOrTests = changedFiles.isNotEmpty &&
      changedFiles.every((f) =>
          f.endsWith('.md') ||
          f.startsWith('docs/') ||
          f.startsWith('test/'));

  var fromDiff = Bump.none;
  if (addsModule) {
    fromDiff = Bump.minor;
    reasons.add('diff touches lib/app/modules/** → at least MINOR');
  } else if (onlyDocsOrTests) {
    fromDiff = Bump.patch;
    reasons.add('diff only touches docs/tests → PATCH');
  }

  // Highest of the two signals wins.
  var auto = fromCommits.index >= fromDiff.index ? fromCommits : fromDiff;
  if (fromDiff.index > fromCommits.index) {
    reasons.add('diff overrides commit prefixes (higher level)');
  }

  if (override != null) {
    reasons.add('manual override: ${override.name}');
    return _Classification(override, reasons);
  }
  return _Classification(auto, reasons);
}
