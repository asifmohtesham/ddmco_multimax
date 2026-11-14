# DocType Form View Conventions

This document defines the standard structure for every **DocType Form View** in
the app (the detail/edit screens under `lib/app/modules/*/form/*_form_screen.dart`).
It is the form-screen counterpart to
[`doctype_list_view_conventions.md`](doctype_list_view_conventions.md) and extends
[`app_bar_conventions.md`](app_bar_conventions.md).

The goal: every form screen looks and behaves identically except for its fields.
Anything shared is a widget, not copy-paste.

---

## 1. Anatomy of a standard form screen

```
PopScope                       (canPop: !isDirty → confirmDiscard)   ← editable forms only
└─ DefaultTabController        (length: N)                          ← OR an explicit controller (see §3)
   └─ Scaffold (resizeToAvoidBottomInset: false)
      └─ NestedScrollView
         ├─ headerSliverBuilder → DocTypeFormHeader
         │     • title / docType / statusLabel / docStatus
         │     • onSave / onReload / onShare / onSubmit / extraActions
         │     • bottom: TabBar(...)            ← tab labels render white on the maroon bar
         └─ body → TabBarView( Details, Items, … )
```

`DocTypeFormHeader` is a solid **maroon** (`colorScheme.primary`) bar: back arrow +
reload / save / share actions, an extended DocType label + doc name + `StatusPill`.
Its `bottom` slot (the `TabBar`) is wrapped in a local `TabBarTheme` that paints the
tabs with `onPrimary` ink — the global `tabBarTheme` is tuned for tabs on a white
list surface and would otherwise make the selected label maroon-on-maroon (invisible).

---

## 2. Shared building blocks

All in `lib/app/modules/global_widgets/`. **Do not** re-implement these privately.

| Concern                                   | Widget                  |
|-------------------------------------------|-------------------------|
| Titled section card (group of fields)     | `DocSectionCard`        |
| `label ── value` read-only row (+ copy)   | `DocDetailRow`          |
| `label ── value` totals row (+ bold)      | `DocSummaryRow`         |
| Tappable picker / date field (label+value)| `DocPickerField`        |
| Passive in-tab empty state (icon+message) | `FormEmptyState`        |
| Selectable in-screen filter chip          | `SelectableFilterChip`  |
| Header                                     | `DocTypeFormHeader`     |

Notes:

* `DocSectionCard` owns its own `margin` (default 16dp bottom). Pass
  `margin: EdgeInsets.zero` if the call site already adds inter-card spacing.
* `FormEmptyState` is the **form** empty state (no CTA). It is distinct from
  `ListEmptyState`, which is the list-screen empty state with Clear/Reload buttons.
* `DocPickerField` is the standard field for any value chosen via a picker
  (type sheets, warehouse pickers, date dialogs). Editable = surface fill +
  strong border + trailing affordance; read-only = subtle fill, no affordance.
  All inks are theme tokens — never wrap it in (or replace it with) a
  hardcoded pastel-gradient banner; those break dark mode.
* `SelectableFilterChip` is the toggle filter on an Items tab (All / Pending /
  Completed). It is distinct from `FilterChipWidget`, the read-only applied-filter
  pill (with ×) rendered in the list-header chip row. A form filter that needs extra
  affordances (e.g. Purchase Receipt's "Link broken" chip with an icon + error color)
  may stay a bespoke `ChoiceChip`.

---

## 3. Tab controller — `DefaultTabController` vs explicit

Most forms wrap the `Scaffold` in `DefaultTabController(length: N)` and pass a
`const TabBar`. Use an **explicit** controller (a small `GetxController` with
`GetSingleTickerProviderStateMixin`, like `ItemTabController`) when the form needs
either of:

1. **Lazy per-tab loading** — fetch a tab's data only on first visit, via a
   tab-change listener (`onTabChanged`). Avoids loading every tab up front.
2. **Modal/bottom-sheet hosting** — isolating the ticker lifecycle from the data
   controller prevents the `_dependents.isEmpty` dispose assertion when the form is
   shown as an overlay.

Also set `isScrollable: true` on the `TabBar` when a form has **4+ tabs** so labels
don't cramp.

The **Item form** (`item/form/`) is the reference implementation of all three.
