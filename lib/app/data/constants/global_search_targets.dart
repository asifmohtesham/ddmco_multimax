import 'package:flutter/material.dart';
import 'package:multimax/app/modules/global_widgets/workspace_menu.dart';

/// One searchable doctype for the Dashboard global search.
///
/// [argsFor] returns the exact navigation arguments the target form expects —
/// traced per-doctype from each form controller / list-row tap. This is the
/// canonical "open this document" contract for the doctype.
class GlobalSearchTarget {
  /// Frappe DocType queried, e.g. 'Delivery Note'.
  final String doctype;

  /// Section header shown in the grouped results, e.g. 'Delivery Notes'.
  final String label;

  /// Decorative leading icon (reuses the Quick-Create tile visuals).
  final IconData icon;

  /// Decorative tint for [icon] (rendered at low alpha over the surface).
  final Color color;

  /// Form route to navigate to on tap.
  final String route;

  /// Builds the navigation arguments for document [id].
  final Map<String, dynamic> Function(String id) argsFor;

  /// Whether to offer this doctype to the user as a browsable target — the
  /// Dashboard fan-out, its scope chips, and the ToDo reference-type picker.
  ///
  /// `false` registers the doctype for routing ONLY: its list screen can run
  /// an in-list search and open a hit, but it never appears in a cross-doctype
  /// result list. For doctypes whose `name` is a random hash that is the whole
  /// point — the hash is meaningless next to other doctypes' hits, but
  /// irrelevant inside its own list, where the row is matched on real fields.
  final bool discoverable;

  const GlobalSearchTarget({
    required this.doctype,
    required this.label,
    required this.icon,
    required this.color,
    required this.route,
    required this.argsFor,
    this.discoverable = true,
  });
}

/// Every doctype a search hit can be OPENED as, in display order.
///
/// **Derived automatically from [kNavCatalog]** — only entries with a non-null
/// [NavLink.formRoute] produce a search target. Adding a new DocType to
/// [kNavCatalog] with a `formRoute` is all that's needed to register it for
/// search; there is no second list to maintain.
///
/// This is the routing registry: [searchNavArgsFor] and [searchTargetForDoctype]
/// read it, so a doctype missing from here cannot be navigated to from a search
/// result (the lookup degrades to a bare id, which forms reading
/// `Get.arguments['name']` throw on).
///
/// It is NOT the list of doctypes offered to users for browsing — that is
/// [kDiscoverableSearchTargets], the `discoverable` subset.
final List<GlobalSearchTarget> kGlobalSearchTargets = [
  for (final link in kNavCatalog)
    if (link.linkType == 'DocType' && link.formRoute != null)
      GlobalSearchTarget(
        doctype: link.linkTo,
        label: link.searchLabel ?? '${link.title}s',
        icon: link.icon,
        color: link.color,
        route: link.formRoute!,
        argsFor: link.argsFor,
        discoverable: link.discoverable,
      ),
];

/// The targets offered to the user for browsing: the Dashboard's all-doctype
/// fan-out, its scope chips, and the ToDo reference-type picker.
///
/// Derived from [kGlobalSearchTargets]; see [GlobalSearchTarget.discoverable].
final List<GlobalSearchTarget> kDiscoverableSearchTargets =
    kGlobalSearchTargets.where((t) => t.discoverable).toList();

/// Canonical navigation arguments for opening document [id] on form [route].
///
/// Routes registered in [kGlobalSearchTargets] get that target's [argsFor]
/// map — the shape the form controller actually reads (`{'name': …, 'mode':
/// …}` etc.). Unregistered routes fall back to the bare [id] for callers
/// whose forms accept a plain String argument.
dynamic searchNavArgsFor(String route, String id) {
  for (final t in kGlobalSearchTargets) {
    if (t.route == route) return t.argsFor(id);
  }
  return id;
}

/// Looks up the registered [GlobalSearchTarget] for [doctype], e.g. to
/// resolve where a ToDo's `reference_type` should navigate to. Returns
/// `null` when the doctype has no registered form route — callers should
/// render the reference as non-tappable in that case.
GlobalSearchTarget? searchTargetForDoctype(String doctype) {
  for (final t in kGlobalSearchTargets) {
    if (t.doctype == doctype) return t;
  }
  return null;
}
