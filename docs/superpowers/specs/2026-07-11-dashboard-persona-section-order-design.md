# Dashboard Persona-Aware Section Ordering — Design

**Date:** 2026-07-11
**Status:** Approved

## Problem

The dashboard renders sections in a fixed order: Scan hero → Quick Create →
Needs attention → Upcoming tasks → Today's pulse. "Upcoming tasks" and
"Quick Create" are equally important, but to different people: managers are
expected to track tasks, while operators who perform the physical work reach
for Quick Create. One fixed order under-serves one of the two personas.

## Decision

Reorder per user with a combined **role + behavior** rule (no new API calls,
no new settings UI, no server dependency):

```
tasksFirst = isManagerish AND hasOpenTodos
```

- **isManagerish** — the roles cached at login (`user.roles`) contain any
  role whose name contains `manager`, case-insensitive. This covers Stock /
  Purchase / Manufacturing / Sales / System Manager and any custom
  `* Manager` role without a maintained list.
- **hasOpenTodos** — `upcomingTodos.isNotEmpty`, the list the dashboard
  already fetches for the Upcoming-tasks section.

Truth table:

| Persona            | Open ToDos | Order                                   |
|--------------------|-----------|------------------------------------------|
| Manager            | yes       | Tasks → Quick Create → Needs attention…  |
| Manager            | no        | Today's layout (tasks section empty/hidden) |
| Operator           | yes / no  | Today's layout (tasks stay below)        |

Rationale for AND over OR: a manager with an empty task list gains nothing
from leading with an empty section, and an operator's layout must not flip
whenever a task lands — shop-floor stability was an explicit requirement.

### Job Title explicitly rejected

"Job Title" is not a Frappe User field; it is `Employee.designation`. Using
it would cost an extra Employee lookup per login, fail for logins without a
linked Employee record, require a maintained designation-string list, and
risk resource-API 403s for non-System-Manager operators (a recurring failure
mode in this app). Roles are already fetched, cached, and universal.

## Layout change

In manager mode the **only** change is that Upcoming tasks moves up to
directly after the Scan hero. Quick Create, Needs attention, and Today's
pulse keep their existing relative order. Operator mode is byte-for-byte
today's layout. One section moves; nothing else reshuffles.

## No layout jump on load

`upcomingTodos` arrives asynchronously; a naive reactive swap would render
Quick-Create-first and then jump once the fetch lands. Instead, persist the
last computed `tasksFirst` verdict in GetStorage **per user** and seed the
initial build from it; recompute (and re-persist) when the fetch completes.
The dashboard then only reflows on the rare day a manager's task list
transitions empty ↔ non-empty, not on every open.

## Implementation shape

- Pure static predicate in `HomeController`:
  `bool showTasksFirst({required List<String> roles, required bool hasOpenTodos})`
  — unit-testable without DI.
- `RxBool tasksFirst` on `HomeController`, seeded from GetStorage
  (key namespaced by user id), updated after the ToDo fetch resolves.
- `home_screen.dart` builds the section list conditionally:
  `_buildUpcomingTasks` renders either immediately after `ScanHeroCard`
  (manager mode) or in its current slot 5 (operator mode). Wrapped in the
  existing `Obx`/`DocTypeGuard` structure — no new widgets.

## Testing

- Unit tests for the predicate: manager+todos → true; manager+empty → false;
  operator+todos → false; operator+empty → false; role-name variants
  ("Stock Manager", "manufacturing manager", custom "Delivery Manager",
  non-matches "Stock User" and "Management Trainee" — "management" lacks
  the trailing 'r', so `contains('manager')` correctly excludes it).
- Unit test for GetStorage seeding: stored verdict drives initial value;
  fetch result overwrites and persists.
- Widget test asserting the section order flips with the flag (Upcoming
  tasks before Quick Create when `tasksFirst`, after otherwise).
- Existing dashboard tests untouched.

## Out of scope

- User-facing override toggle (can be added later if the heuristic misfires).
- Any change to which ToDos are fetched or how they render.
- Reordering Needs attention / Today's pulse.
