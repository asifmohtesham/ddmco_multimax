import 'package:flutter/material.dart';
import 'package:multimax/app/modules/global_widgets/app_nav_drawer.dart';

/// A drop-in [Scaffold] replacement for every DocType **list** screen.
///
/// Guarantees that `drawer: AppNavDrawer()` is always present, which is the
/// prerequisite for `automaticallyImplyLeading: false` on [DocTypeListHeader]
/// to show the hamburger menu icon instead of a back arrow.
///
/// ## Migration
///
/// Replace the raw [Scaffold] call in any list screen:
///
/// ```dart
/// // Before
/// return Scaffold(
///   backgroundColor: colorScheme.surfaceContainerLow,
///   drawer: const AppNavDrawer(),
///   body: ...,
///   floatingActionButton: ...,
/// );
///
/// // After
/// return AppShellScaffold(
///   body: ...,
///   floatingActionButton: ...,
/// );
/// ```
///
/// ## What is NOT forwarded
///
/// Parameters that belong exclusively to form or modal screens
/// (`endDrawer`, `appBar`, `bottomSheet`, `persistentFooterButtons`)
/// are intentionally excluded. Use a plain [Scaffold] for those.
///
/// See `docs/app_bar_conventions.md` for the full convention.
class AppShellScaffold extends StatelessWidget {
  // ── Required ───────────────────────────────────────────────────────────
  final Widget body;

  // ── Optional — forwarded verbatim to Scaffold ─────────────────────────

  /// Defaults to [ColorScheme.surfaceContainerLow], matching the convention
  /// used by all existing list screens.
  final Color? backgroundColor;

  /// Floating action button. Supports both [FloatingActionButton] and
  /// [FloatingActionButton.extended].
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;

  /// Persistent bottom widget (e.g. the barcode scan bar on Stock Entry).
  final Widget? bottomNavigationBar;

  /// Whether the [body] should extend behind the [bottomNavigationBar].
  final bool extendBody;

  /// Whether the scaffold should resize when the keyboard appears.
  final bool resizeToAvoidBottomInset;

  const AppShellScaffold({
    super.key,
    required this.body,
    this.backgroundColor,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.bottomNavigationBar,
    this.extendBody                  = false,
    this.resizeToAvoidBottomInset    = true,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor:           backgroundColor ?? cs.surfaceContainerLow,
      drawer:                    const AppNavDrawer(),
      body:                      body,
      floatingActionButton:      floatingActionButton,
      floatingActionButtonLocation: floatingActionButtonLocation,
      bottomNavigationBar:       bottomNavigationBar,
      extendBody:                extendBody,
      resizeToAvoidBottomInset:  resizeToAvoidBottomInset,
    );
  }
}
