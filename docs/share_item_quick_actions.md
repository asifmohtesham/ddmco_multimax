# Item quick actions from a shared photo

Share one photo with **Multimax** to read its barcode and look up the Item. The
bottom sheet shows the Item image or a placeholder, its code and name, and its
**Variant Of** template when present. Tap the header to open the Item form.

## Routing

- One image from the share menu or a native drop opens Item quick actions. A
  share received while signed out or during startup waits until the app reaches
  a signed-in screen.
- Two or more images open **Items from Photos**. A single photo can also go there
  by tapping **Items from Photos** in the quick-actions sheet.
- While **Items from Photos** is reviewing an existing set, a new share goes
  through its existing add-or-start-again prompt and content deduplication. When
  it is busy processing or generating a file, it shows the existing busy message.
- While Item quick actions are open, the most recent incoming share waits for
  the current sheet to close.

The sheet uses the same still-image decoder as Items from Photos and retries a
whole-photo miss with tiled and enlarged images. It shows each distinct decoded
value once and asks which barcode to use when there is more than one. A photo
with no barcode offers **Items from Photos** and **Scan with camera** on phones
and iPads. A lookup miss shows the scanned value. A failed lookup shows a short
permission or connection message, with **Retry lookup** for the same barcode.

Item lookup shares the camera's checked EAN-8 lookup and uses ERPNext's exact
Item Barcode or Batch lookup when needed. A full Batch can identify its Item.

## Item actions

**Upload Item Image** appears only for an Item with an empty image field and
when the user can write that Item. It previews the shared photo. **Pick Another**
opens the existing gallery or camera picker, and **Upload** confirms the
selection. The upload sends the original-resolution file, omits the
`optimize` field, and sets `Item.image` to the attached file URL. EXIF is removed
from supported JPEGs without re-encoding. Photos with orientation data that
affects display, unrecognized metadata, or other formats retain their bytes.
If the attachment succeeds and saving the Item field fails, retrying in the
same sheet reuses the attachment.

**Suppliers by Item** opens the report with **Variant Of** set to the Item's
template. For a template or plain Item, **Suppliers for this Item** selects that
Item in the report's **Items** Link filter. Access follows the drawer's Purchase User
or Stock User role check and the session's Desk report permissions. The drawer
entry still opens the report with its normal defaults.

## Device checks

Use a device connected to a disposable ERPNext test site with sample Items and
the Suppliers by Item report. Use mock ERP responses for automated tests.

1. On Android and iPhone or iPad, share a single photo with one readable Item
   label from Photos. Test with Multimax open, with the app closed, and while
   signed out. After sign-in, verify the sheet appears once and the header opens
   the correct Item. On Apple silicon, also try a Finder share or drop into the
   iPad app.
2. Share two or more photos and verify the usual Items from Photos review opens.
   Repeat with a single photo and select **Items from Photos** from quick
   actions. Share again while a review is open and while a file is generating
   to check the existing prompt and busy message.
3. Share a photo with multiple distinct labels, one with no barcode, and one
   with an unmatched barcode. Check the choice list, camera fallback, scanned
   value, and photo fallback. Use a full Batch label to check the linked Item.
   Disconnect the device for a lookup, then reconnect and retry.
4. As an authorized user, test both report routes. Verify a variant selects its
   template and a plain or template Item selects its own code. Check that the
   action is absent when the user lacks the report role or Desk report access.
5. For a writable Item with an empty image field, confirm the preview starts
   with the shared photo. Try **Pick Another** from gallery and camera, then
   upload to the disposable site and verify the Item form shows the image. For
   an Item with an existing image or a user without Item write access, check that
   the upload action is absent.
6. Repeat on a phone and tablet in portrait and landscape. Check that the sheet
   stays within the safe area and scrolls when the choice list is long.
