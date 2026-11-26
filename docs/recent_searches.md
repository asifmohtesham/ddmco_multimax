# Recent searches

Multimax remembers the ten newest committed searches for each user and search
context. A commit happens when the user submits with the keyboard, opens a
found document, taps **Apply** in local search, or picks a recent search.
Typing, opening a pre-filled **Search: …** chip, and hardware/DataWedge updates
to a list's query leave history unchanged. Voice dictation fills the dashboard
query and previews results. The transcript is saved when the user submits it
or opens a hit.

Saved text is trimmed and internal whitespace collapses to one space.
Case-insensitive duplicates move to the top with the latest casing. Empty
queries are ignored. DocType API search and dashboard search also ignore
queries shorter than three characters after normalization.

> **Dashboard search is not reachable today.** Since `2864699c` (26 Sep 2026)
> the dashboard's search icon opens the AwesomeBar, and nothing in the app opens
> `GlobalDocumentSearchDelegate`. Its history support is built and covered by
> widget tests, but users won't see it until something opens that delegate
> again. The AwesomeBar keeps its own RECENT list. The Pixel 7 smoke test on
> 20 Nov 2026 confirmed the list-screen behaviour on a device.

## Storage and screen setup

`StorageService` uses GetStorage with the key
`recent_searches::<context>::<userEmail>`. The dashboard uses `global` for
all scope chips. For a list, the context comes from `recentSearchKey`,
`searchDoctype`, or the name of the route that opened search, in that order.
An overlay without a usable context or signed-in email has no history.
Signing out preserves the history for that email on the device.

Most screens can use the default. To give a list its own history when it
shares a doctype with another list, pass a distinct, stable key to
`DocTypeListHeader(recentSearchKey: 'sales-orders-open', …)`. Pass the same
`recentSearchKey` to the filter chip's `editListSearch` call. A screen that
opens `DocTypeSearchDelegate` directly can pass the key to the delegate.

## Suggestions

An empty field shows **Recent searches** in newest-first order when history
exists. Below the API or dashboard minimum, matches contain the typed text
regardless of case. The minimum-length hint appears when there are no matches.
At the minimum and above, the overlay shows live results. Local search shows
matches above its hint and **Apply** button while typing. Dashboard scope chips
stay above the suggestions. With no history, the existing empty states appear.

Selecting an entry opens results in API and dashboard search, or applies the
filter and closes local search. The remove button deletes one entry in place.
**Clear all** prompts before clearing the current context. Storage writes run
in the background, and search continues if a write fails.

## Dashboard scans

Scans from the Dashboard's **Scan Item / Batch / Rack** field, camera or
hardware scanner appear in the search overlay's **RECENT** list. Both successful
and failed scans are saved. Failed scans show what happened. Tapping a scan
repeats the lookup and moves the entry to the top with its latest result.

The AwesomeBar keeps up to ten entries on the device, newest first, across
scans and navigation picks. Scanning the same code again replaces the earlier
scan entry. Empty input and POS Upload labels are excluded.

## AwesomeBar RECENT list

- **When.** Each entry shows when it was saved: "Just now", "5 min ago",
  "14:05", "Yesterday 14:05" or "24 Nov 14:05". When the entries span more
  than one day, they sit under **Today**, **Yesterday** and **Earlier**.
  Entries saved before 2.63 have no time, so they show under Earlier.
- **Remove.** × removes one entry. **Clear all** asks first. Outside
  Dashboard, scans are hidden, so Clear all keeps them.
- **Failed scans.** A failed scan has an edit button. It opens the code for
  correction, for example after a smudged barcode, and then scans the edited
  code.
- **Long press** opens the actions for an entry:
  - Scans: **Scan again**, **Edit code and scan**, **Open item** (successful
    item or batch scans only), **Search for this code** (puts the code into
    the search field), **Copy code** and **Remove from recent**.
  - Other entries: **Open** or **Search again**, and **Remove from recent**.
- **Searches that found nothing.** A search submitted with the keyboard's
  search key that finds nothing is saved as "No results". Tapping it runs
  the search again. Typing alone saves nothing, and neither does a failed
  request, such as when the device is offline.
- **Empty state.** With nothing typed and nothing recent, the overlay shows
  a start hint. "No results found" appears only after a search.
- **Loading.** While a search runs, a thin bar shows at the top of the
  list. The previous results stay on screen until the new ones arrive.
- **Colours.** Section headings use muted ink, and matches are marked in
  bold body ink. The accent colour falls below 4.5:1 on the search view's
  surface for dark Maroon and light Blue and Purple, so it isn't used for
  text there.

## Out of scope

History stays on the device. There is no server sync. The AwesomeBar's recent
navigation destinations are a separate feature.
