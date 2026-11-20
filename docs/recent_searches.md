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
> again. The AwesomeBar keeps its own, separate list of recently visited
> places. The Pixel 7 smoke test on 20 Nov 2026 confirmed the list-screen
> behaviour on a device. The dashboard part could not be tested there.

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

## Out of scope

History stays on the device. There is no server sync. The AwesomeBar's recent
navigation destinations are a separate feature.
