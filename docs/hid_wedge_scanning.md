# HID Keyboard-Wedge Scanning (Netum C750)

The app accepts Bluetooth HID keyboard-wedge scanners (e.g. the Netum C750)
in addition to Zebra DataWedge / integrated PDA scanners. HID scans are
assembled by `HidWedgeService` and routed into `DataWedgeService.scannedCode`,
so every scan-driven screen behaves exactly as it does with a Zebra device.

## Scanner setup (one-time)

Scan the C750 configuration barcodes to set:

1. **HID / Bluetooth keyboard mode** (not BLE/SPP serial mode).
2. **CR (Enter) suffix enabled** — the app uses Enter to delimit a scan. With
   no suffix, scans cannot be detected.
3. **US-English keyboard locale** — match the phone's layout so symbols such
   as `-` map correctly.

Then pair the scanner with the phone in Android Bluetooth settings.

## How it works

- `WedgeBurstAssembler` treats keystrokes arriving within 50 ms of each other
  as one burst; an Enter finalises the burst into a barcode string.
- Slow human typing (gaps >= 50 ms) is never treated as a scan, so manual
  entry into search / quantity / login fields still works.
- Known limitation: if a text field is focused when you scan, the single
  leading character may also land in that field. The full code still routes
  correctly. On the scan-driven screens (lists, sheets) no field is focused,
  so this does not occur there.

## Not supported (by design)

- Netum BLE/SPP SDK mode and scanner back-channel commands (beep / trigger /
  sleep). HID is one-way (scanner -> phone).
