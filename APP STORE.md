# App Store Connect — Submission Content

## App Information

**Category:** Business *(Primary)*
**Secondary Category:** Productivity *(optional)*

**Privacy Policy URL:** *(host the template at the bottom — e.g. `https://www.ddmco.com/privacy`)*

---

## Version 1.0 — Prepare for Submission

**Name:** `Multimax`

**Subtitle** (29/30 chars):
```
Warehouse & Manufacturing Ops
```

**Promotional Text** (138/170 chars — can be updated any time without a new build):
```
Real-time stock control, work orders, and delivery management — synced to your ERPNext system. Built for warehouse and shop-floor teams.
```

**Description:**
```
Multimax is a mobile operations app for supply-chain and manufacturing teams running Frappe ERPNext. It brings warehouse and factory workflows to your phone so staff can act on stock movements, purchase receipts, and production tasks without a desktop.

── OPERATIONS ──

Stock Entry — create and submit material transfers, material issues, and goods receipts from the warehouse floor. Scan items and rack locations with the built-in camera or a Zebra hardware scanner.

Delivery Notes — manage outbound shipments, mark items as dispatched, and update delivery status.

Purchase Orders & Receipts — review open orders and receive incoming goods. Batch numbers and quantities are verified on the spot with barcode scanning.

Packing Slips — barcode-driven line-by-line packing verification before dispatch.

Material Requests — raise and review internal material requests linked to the production schedule.

── MANUFACTURING ──

Work Orders — view active orders, track progress, and start execution from the list.

Job Cards — operators clock in and out of operations, resume in-progress cards, and submit completions from the shop floor.

Bills of Materials (BOM) — browse active BOMs, inspect component requirements, and search assemblies.

── DASHBOARD & REPORTS ──

• Performance timeline — daily and weekly team activity view
• Manufacturing pulse — live KPIs for active work orders, job cards, and BOMs
• Batch-wise balance — stock on hand per batch number
• Item variant details — stock levels across all variants of a product
• Job card summary — production completion by operator and operation

── BARCODE SCANNING ──

Camera scanning is built into the app. Also supports Zebra DataWedge hardware scanners. Decodes EAN-8 item codes, batch numbers, and warehouse rack locations in a single scan.

── CONNECTIVITY ──

Connects to your organisation's private ERPNext instance over HTTPS. Credentials are issued by your system administrator. No data is processed outside your own ERP server.

Requires an active ERPNext account — not for public sign-up.
```

**Keywords** (96/100 chars):
```
warehouse,stock,erpnext,frappe,delivery,purchase,barcode,scanner,manufacturing,packing,inventory
```

**Support URL:** *(your company support page — e.g. `https://www.ddmco.com/support`)*

---

## App Review Information

**Sign-In Required:** Yes

| Field | Value                                      |
|---|--------------------------------------------|
| Demo Username | *(ERPNext test account at erp.domain.com)* |
| Demo Password | *(password for that account)*              |

**Notes for Reviewer:**
```
This is an internal warehouse management app for the DDMCO / Multimax organisation.

SIGN-IN: The app requires ERPNext credentials. Please use the demo account entered above. The login screen has a URL field — it is pre-filled with https://erp.domain.com; leave it as-is.

WHAT TO EXPLORE: After signing in, the Dashboard shows a Quick Access grid (Stock Entry, Delivery Note, Purchase Receipt, Packing Slip) and a Manufacturing section (Work Orders, Job Cards, BOM). Tap any tile to browse that module.

CAMERA: The app requests camera access for barcode scanning. Tap any barcode input field on a form to test it.

NOTE: The app communicates exclusively with https://erp.domain.com over HTTPS. No user data is stored on device beyond the server URL and session cookie.
```

---

## Export Compliance

When prompted during TestFlight processing or submission:

| Question | Answer |
|---|---|
| Does your app use encryption? | **Yes** |
| Is it exempt from export regulations? | **Yes** — standard HTTPS/TLS only (US EAR 740.17(b)(1)) |

---

## Age Rating

**App Information → Age Rating** — answer all questionnaire items as **None / No**.
Result: **4+**

---

## Privacy Policy Template

Host this at a stable URL before submitting (e.g. `https://www.ddmco.com/privacy`):

```
Privacy Policy — Multimax

The Multimax app does not collect, store, or share any personal data
with DDMCO or third parties.

All business data (inventory, orders, users) resides exclusively on
your organisation's private ERPNext server. The app connects to that
server over HTTPS using credentials provided by your administrator.

The camera is used solely for barcode scanning within the app.
No images are stored or transmitted.

Contact: [your-support-email@ddmco.com]
Last updated: 20 May 2026
```

---

## Submission Checklist

- [ ] Screenshots uploaded (iPhone 6.5" — minimum 3, already done)
- [ ] Description, subtitle, keywords filled in
- [ ] Support URL set
- [ ] Privacy Policy URL live and linked
- [ ] Demo ERPNext account created and credentials entered under App Review
- [ ] Export Compliance answered
- [ ] Age Rating set (4+)
- [ ] Category set to Business
- [ ] Build 2.0.0 (9) attached to the submission
- [ ] Click **Add for Review**
