// Semantic version bump helper.
//
// Reads the current `version: X.Y.Z+B` from pubspec.yaml, finds the last released
// `v*` tag reachable from HEAD, classifies every commit since that tag
// (Conventional-Commit prefix + corroborating diff), and proposes the next version
// per docs/versioning_conventions.md. A proposal that collides with an existing
// release — or a branch that is behind the latest one — is warned about, and
// --write is refused.
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

  static final _tagRe = RegExp(r'^v(\d+)\.(\d+)\.(\d+)(?:\+(\d+))?$');

  /// The version a release tag name encodes, or null if [tag] is not one.
  /// Older tags are `vX.Y.Z+B`; newer ones drop the build (`vX.Y.Z`), read
  /// here as build 0 so a missing build never outranks a real one.
  static Version? tryParseTag(String tag) {
    final m = _tagRe.firstMatch(tag.trim());
    if (m == null) return null;
    return Version(
      int.parse(m[1]!),
      int.parse(m[2]!),
      int.parse(m[3]!),
      int.parse(m[4] ?? '0'),
    );
  }

  String get semver => '$major.$minor.$patch';

  /// Orders by `X.Y.Z` only; the build number is compared on its own.
  int compareSemver(Version other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
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
  exitCode = run(args);
}

/// Runs the tool against the repo in [workingDirectory] (default: the current
/// directory) and returns the process exit code.
int run(
  List<String> args, {
  String? workingDirectory,
  StringSink? out,
  StringSink? err,
}) {
  out ??= stdout;
  err ??= stderr;

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
          err.writeln('--since requires a tag argument');
          return 2;
        }
        since = args[++i];
      default:
        err.writeln('Unknown argument: ${args[i]}');
        err.writeln('Usage: dart run tool/bump_version.dart '
            '[--major|--minor|--patch] [--since <tag>] [--write]');
        return 2;
    }
  }

  // --since is an analysis window; it never mutates pubspec.yaml.
  if (since != null && write) {
    err.writeln('--since is analysis-only and cannot be combined with --write.');
    return 2;
  }

  // 1. Current version.
  final pubspec = File(workingDirectory == null
      ? _pubspecPath
      : '$workingDirectory/$_pubspecPath');
  if (!pubspec.existsSync()) {
    err.writeln('$_pubspecPath not found; run from the project root.');
    return 1;
  }
  final pubspecText = pubspec.readAsStringSync();
  final versionLine = _versionLineRe.firstMatch(pubspecText);
  if (versionLine == null) {
    err.writeln('No `version:` line in $_pubspecPath.');
    return 1;
  }
  final current = Version.parse(versionLine.group(1)!);

  // 2. Last released tag and the commit range (--since overrides the base tag).
  final reachableTag = lastReachableTag(workingDirectory: workingDirectory);
  final lastTag = since ?? reachableTag;
  final range = lastTag == null ? null : '$lastTag..HEAD';
  final messages = commitMessages(range, workingDirectory: workingDirectory);
  final changedFiles = _changedFiles(range, workingDirectory: workingDirectory);
  final newModules = newModuleDirs(lastTag, workingDirectory: workingDirectory);

  // 3. Classify.
  final classified = classify(messages, changedFiles, newModules, override);
  final bump = classified.bump;
  final next = current.next(bump);

  // Report.
  out.writeln('Current version : $current');
  out.writeln('Last tag        : ${lastTag ?? '(none — using full history)'}');
  out.writeln('Commits in range: ${messages.length}');
  for (final line in classified.reasons) {
    out.writeln('  $line');
  }
  final label = override != null ? '${bump.name} (overridden)' : bump.name;
  out.writeln('Bump            : $label');
  out.writeln('Next version    : $next');

  if (bump == Bump.none && override == null) {
    out.writeln(
        'Note            : no functional change detected — only the build number moves.');
  }

  // 4. Guard: the proposal must not collide with an existing release.
  final problems = releaseCollisions(
    proposed: next,
    bump: bump,
    baseTag: reachableTag,
    releases: releaseTags(workingDirectory: workingDirectory),
  );
  for (final problem in problems) {
    out.writeln('WARNING         : $problem');
  }

  // 5. Apply.
  if (!write) {
    out.writeln(problems.isEmpty
        ? '\n(dry-run — pass --write to apply)'
        : '\n(dry-run — --write would be refused; see warnings above)');
    return 0;
  }
  if (problems.isNotEmpty) {
    err.writeln('Refusing to write $next to $_pubspecPath:');
    for (final problem in problems) {
      err.writeln('  - $problem');
    }
    return 1;
  }
  final updated =
      pubspecText.replaceFirst(versionLine.group(0)!, 'version: $next');
  pubspec.writeAsStringSync(updated);
  out.writeln('\nWrote version: $next to $_pubspecPath');
  return 0;
}

/// Nearest `v*` tag that is an ancestor of HEAD, or null if HEAD reaches none.
/// A newer tag on another branch is not a base for this branch's range.
String? lastReachableTag({String? workingDirectory}) {
  final r = Process.runSync(
      'git', ['describe', '--tags', '--abbrev=0', '--match', 'v*'],
      workingDirectory: workingDirectory);
  if (r.exitCode != 0) return null;
  final tag = (r.stdout as String).trim();
  return tag.isEmpty ? null : tag;
}

/// Full commit messages (subject + body) in [range], newest first. The body is
/// needed because a `BREAKING CHANGE:` footer never appears in the subject.
List<String> commitMessages(String? range, {String? workingDirectory}) {
  // -z separates commits with NUL, so multi-line bodies stay in one record.
  final gitArgs = [
    'log',
    '-z',
    '--pretty=format:%B',
    if (range != null) range,
  ];
  final r =
      Process.runSync('git', gitArgs, workingDirectory: workingDirectory);
  if (r.exitCode != 0) return const [];
  return (r.stdout as String)
      .split('\x00')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
}

List<String> _changedFiles(String? range, {String? workingDirectory}) {
  final gitArgs = [
    'diff',
    '--name-only',
    if (range != null) range else 'HEAD',
  ];
  final r =
      Process.runSync('git', gitArgs, workingDirectory: workingDirectory);
  if (r.exitCode != 0) return const [];
  return (r.stdout as String)
      .split('\n')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
}

const _modulesDir = 'lib/app/modules/';

/// Top-level module directories that exist at HEAD but not at [base], e.g.
/// `lib/app/modules/foo`. With no [base] every module counts as new.
List<String> newModuleDirs(String? base, {String? workingDirectory}) {
  Set<String> dirsAt(String rev) {
    final r = Process.runSync(
        'git', ['ls-tree', '-d', '--name-only', rev, _modulesDir],
        workingDirectory: workingDirectory);
    if (r.exitCode != 0) return const {};
    return (r.stdout as String)
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet();
  }

  final before = base == null ? const <String>{} : dirsAt(base);
  return dirsAt('HEAD').difference(before).toList()..sort();
}

final _versionLineRe = RegExp(r'^version:\s*(.+)$', multiLine: true);

/// A released `v*` tag, as the collision guard sees it.
class Release {
  final String tag;

  /// `version:` of pubspec.yaml at the tag; null when absent or unparseable.
  final Version? pubspec;

  /// Whether the tag is an ancestor of HEAD.
  final bool reachable;

  Release(this.tag, {this.pubspec, required this.reachable});

  /// Highest `X.Y.Z` and highest build this release lays claim to, or null if
  /// it names no version. The tag name and the pubspec at the tag can disagree
  /// (v2.25.5 carries 2.25.3+81), so each field takes the higher of the two.
  Version? get version {
    final claims = [Version.tryParseTag(tag), pubspec].whereType<Version>();
    if (claims.isEmpty) return null;
    final top = claims.reduce((a, b) => a.compareSemver(b) >= 0 ? a : b);
    final build =
        claims.map((c) => c.build).reduce((a, b) => a >= b ? a : b);
    return Version(top.major, top.minor, top.patch, build);
  }

  String get label => pubspec == null ? tag : '$tag (pubspec.yaml $pubspec)';
}

/// Every `v*` tag, with the pubspec.yaml version at that tag and whether HEAD
/// contains it.
List<Release> releaseTags({String? workingDirectory}) {
  List<String> tags(List<String> filter) {
    final r = Process.runSync('git', ['tag', '--list', 'v*', ...filter],
        workingDirectory: workingDirectory);
    if (r.exitCode != 0) return const [];
    return (r.stdout as String)
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  Version? pubspecAt(String tag) {
    final r = Process.runSync('git', ['show', '$tag:$_pubspecPath'],
        workingDirectory: workingDirectory);
    if (r.exitCode != 0) return null;
    final line = _versionLineRe.firstMatch(r.stdout as String);
    if (line == null) return null;
    try {
      return Version.parse(line.group(1)!);
    } on FormatException {
      return null;
    }
  }

  final reachable = tags(const ['--merged', 'HEAD']).toSet();
  return [
    for (final tag in tags(const []))
      Release(tag,
          pubspec: pubspecAt(tag), reachable: reachable.contains(tag)),
  ];
}

/// Reasons [proposed] must not be released, given every existing release;
/// empty when it is safe. [baseTag] is the tag the commit range started from.
///
/// Only the proposal is judged. Past releases that collide with each other
/// (three tags share build 81) are history, not a reason to refuse.
List<String> releaseCollisions({
  required Version proposed,
  required Bump bump,
  required String? baseTag,
  required List<Release> releases,
}) {
  final known = [
    for (final r in releases)
      if (r.version case final v?) (release: r, version: v),
  ];
  if (known.isEmpty) return const [];

  final problems = <String>[];

  // Released work that HEAD does not contain: the branch is behind.
  final base =
      known.where((k) => k.release.tag == baseTag).firstOrNull?.version;
  final missing = [
    for (final k in known)
      if (!k.release.reachable &&
          (base == null ||
              k.version.compareSemver(base) > 0 ||
              k.version.build > base.build))
        k.release.tag,
  ];
  if (missing.isNotEmpty) {
    problems.add('${missing.join(', ')} '
        '${missing.length == 1 ? 'is' : 'are'} newer than '
        '${baseTag ?? 'any tag HEAD contains'} but not an ancestor of HEAD — '
        'this branch is behind the latest release; merge it in first');
  }

  final topSemver = known
      .reduce((a, b) => a.version.compareSemver(b.version) >= 0 ? a : b);
  final order = proposed.compareSemver(topSemver.version);
  // A build-only release (Bump.none) deliberately keeps X.Y.Z.
  if (order < 0 || (order == 0 && bump != Bump.none)) {
    problems.add('version ${proposed.semver} is not greater than released '
        '${topSemver.release.label}');
  }

  final topBuild =
      known.reduce((a, b) => a.version.build >= b.version.build ? a : b);
  if (proposed.build <= topBuild.version.build) {
    problems.add('build number ${proposed.build} is not greater than '
        '${topBuild.version.build}, used by ${topBuild.release.label} — '
        'Play Store rejects a reused versionCode');
  }

  return problems;
}

class Classification {
  final Bump bump;
  final List<String> reasons;
  Classification(this.bump, this.reasons);
}

/// Leading Conventional-Commit type, e.g. `feat`, `fix`, `feat!`, `chore`.
/// Not multiLine: `^` anchors to the subject, so body lines are never a type.
final _typeRe = RegExp(r'^(\w+)(\([^)]*\))?(!)?:');

/// The `BREAKING CHANGE:` / `BREAKING-CHANGE:` footer token: uppercase, at the
/// start of a line, followed by a colon. A prose mention ("avoids a breaking
/// change in …") is not a declaration.
final _breakingFooterRe = RegExp(r'^BREAKING[ -]CHANGE:', multiLine: true);

/// Classifies full commit [messages] (subject + body), the [changedFiles] and
/// the [newModules] in the range into a single bump; [override] wins when given.
Classification classify(
  List<String> messages,
  List<String> changedFiles,
  List<String> newModules,
  Bump? override,
) {
  final reasons = <String>[];

  // Signal 1: commit prefixes.
  var fromCommits = Bump.none;
  for (final s in messages) {
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
  // Files added inside an existing module are not a signal on their own — a
  // new screen there is a feature only if its commit says `feat:`.
  final addsModule = newModules.isNotEmpty;
  final onlyDocsOrTests = changedFiles.isNotEmpty &&
      changedFiles.every((f) =>
          f.endsWith('.md') ||
          f.startsWith('docs/') ||
          f.startsWith('test/'));

  var fromDiff = Bump.none;
  if (addsModule) {
    fromDiff = Bump.minor;
    reasons.add('diff adds new module ${newModules.join(', ')} → at least MINOR');
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
    return Classification(override, reasons);
  }
  return Classification(auto, reasons);
}
