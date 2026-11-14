# Operator Smoke Test — MR/PS Create/Write Permission Gate

Validates the fix that gates the **New Material Request** / **New Packing Slip** FABs
on the doctype's `create` roles and the **Delete / View‑Edit / PS Edit** controls on
its `write` roles — with the role rows sourced from `frappe.desk.form.load.getdoctype`
(reachable by operators) instead of `/api/resource/DocType/<name>` (403s for operators).

**Goal:** prove the buttons appear for real creators/writers, are hidden from
read‑only users, and no user hits a 403 during list load.

---

## 0. Preconditions

- [ ] **Fixed build installed** on the test device (the build containing
      `ApiProvider.fetchDocTypeRoles` + `rolesWithPermission` and the
      `createRoles`/`writeRoles` `RoleGuard` gates). Confirm build number before starting.
      > Until this build is live, non‑SM users (now including Jawwad, SM removed 2026‑07‑01)
      > hit the original bug — a fail here without the fixed build is expected, not the gate.
- [ ] Pointed at the correct ERPNext instance (`erp.multimax.cloud` or the intended test instance).
- [ ] Two test accounts identified, **neither holding System Manager** (SM bypasses the gate and voids the test):
  - [ ] **Creator operator** — has a create/write role for MR *and* PS
        (e.g. Stock User or Stock Manager). Jawwad now qualifies.
  - [ ] **Read‑only operator** — can *read* MR/PS but has **no** create/write role on them.
        (If none exists, create/borrow one — the discrimination test can't be skipped.)
- [ ] Record each account's roles (Desk → User, or `bench execute`) so expected results are known up front.
- [ ] Have at least one **Draft** Material Request and one **Draft** Packing Slip available to exercise Edit/Delete.

Reference — roles currently granting create/write (permlevel 0), from live `getdoctype`:
- **Material Request:** Purchase Manager, Stock Manager, Purchase User, Stock User, Stock User - Custom
- **Packing Slip:** Sales Manager, Stock Manager, Sales User, Stock User, Item Manager, Stock User - Custom

---

## 1. Creator operator — positive cases

Log in as the **creator operator**.

### Material Request
- [ ] Open the Material Request list → **New Material Request** FAB is visible.
- [ ] Scroll down → FAB collapses to the mini `+` (still visible), scroll up → extended label returns.
- [ ] Tap FAB → create form opens; fill required fields → **Save succeeds** (no 403 / permission error).
- [ ] Open a **Draft** MR (expand detail) → **Delete** button visible **and** the CTA shows **Edit** (not just View).
- [ ] Tap Edit → make a change → **Save succeeds**.
- [ ] Open a **Submitted** MR → CTA shows **View** only (no Edit/Delete). *(expected: write‑gated)*

### Packing Slip
- [ ] Open the Packing Slip list → **New Packing Slip** FAB is visible (extended + mini as above).
- [ ] Tap FAB → create flow proceeds; complete it → **Save succeeds**.
- [ ] Open a **Draft** PS → **Edit** CTA visible.
- [ ] Tap Edit → make a change → **Save succeeds**.
- [ ] Open a non‑Draft PS → shows **View Details** only (no Edit).

---

## 2. Read‑only operator — negative / discrimination cases

Log in as the **read‑only operator**. This proves the gate actually filters and isn't just always‑showing.

- [ ] Material Request list → **New Material Request FAB is HIDDEN**.
- [ ] Open a Draft MR detail → **no Delete**, CTA shows **View** only (fallback), **no Edit**.
- [ ] Packing Slip list → **New Packing Slip FAB is HIDDEN**.
- [ ] Open a Draft PS detail → **no Edit** CTA (renders nothing / View path only).
- [ ] List screens still load normally (reading is unaffected).

---

## 3. Robustness / load behaviour (either account)

- [ ] **Cold start** (kill app, log in fresh) → on first open of each list the FAB is **already present with no visible delay** (create/write perms are prefetched at login via `PermissionService`, not fetched on screen-open). A late pop-in after ~1–2s is a regression.
- [ ] No permission error/snackbar is shown to the user during list load.
- [ ] (If logs available) `frappe.desk.form.load.getdoctype` for `Material Request` / `Packing Slip` fires **at login** and returns **HTTP 200**; there is **no** `/api/resource/DocType/...` 403 driving the gate.
- [ ] **Failure fallback:** if `getdoctype` were to fail, the role sets fall back to `System Manager` only → buttons hidden for the operator, app does **not** crash and the list still loads. (Observe if it occurs; don't force.)

---

## 4. Jawwad regression (SM removed)

- [ ] Log in as **jawwad@multimax.cloud** (now on standard roles, no SM).
- [ ] Confirm he can **see and use** New MR, New PS, and PS Draft Edit — i.e. the operational ticket that prompted the SM hotfix is resolved *without* elevated privileges.

---

## 5. Sign‑off

| Field | Value |
|---|---|
| Build / version tested | |
| Tester | |
| Date | |
| Creator operator (account + key roles) | |
| Read‑only operator (account + key roles) | |
| Result (Pass / Fail) | |
| Notes / failures | |

**Pass criteria:** all of §1, §2, and §4 pass. If any creator cannot see or use a
button, or a read‑only user *can*, the gate is **not** validated — do not close the ticket.

**If it fails after the fixed build is confirmed installed:** most likely `getdoctype`
is gated more tightly for bare operators than expected (role sets falling back to
System‑Manager‑only). Capture the `getdoctype` HTTP status for that account and hand back
for investigation. Interim mitigation if operators are blocked in production: re‑grant the
affected user System Manager as a temporary hotfix (as was done for Jawwad) while the gate
is re‑worked.
