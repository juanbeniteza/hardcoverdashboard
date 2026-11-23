# Hardcover Dashboard for KOReader

A read-only [Hardcover.app](https://hardcover.app) reading dashboard plugin for KOReader, designed for color and grayscale e-ink screens with a single-page, zero-scroll layout.

## Features

- **Single-Page Dashboard:** Displays **Currently Reading**, **Reading Goals**, and the **Reading Activity** monthly calendar together on one screen—side-by-side cards above the calendar in portrait, or two columns in landscape.
- **Monthly Reading Activity Calendar:** Shows reading streaks, daily page-count badges, continuous colored (or grayscale) multi-day book bars that break cleanly across unread days and stack when multiple books are read on the same day, plus cover thumbnails on finish/last-read days. Only books with logged page progress appear on the calendar.
- **Day Detail Popup:** Tap any day cell to view every book read on that date with its cover, color indicator, author, read date range, and pages read on that date.
- **Currently Reading & Goals:** View page or audiobook progress bars, cycle through multiple active books or goals without scrolling, and track annual reading challenges (including hour goals converted from seconds).
- **Offline-First & Read-Only:** Caches dashboard data and book covers on disk for instant offline viewing. Sends GraphQL queries only—never mutates your Hardcover account.
- **Screenshots:** Supports KOReader's diagonal screenshot gestures and includes a **Take Screenshot** action in the settings menu.

## Install

1. Download `hardcoverdashboard.koplugin.zip` from the [latest GitHub Release](https://github.com/juanbeniteza/hardcoverdashboard/releases/latest) (or clone this repository).
2. Copy the `hardcoverdashboard.koplugin` folder into your device's KOReader `plugins` directory (for example, `.adds/koreader/plugins/` on Kobo).
3. Restart KOReader and open **Tools → Hardcover Dashboard**.
4. Paste a read-only Hardcover Personal Access Token when prompted, or open the **⚙** menu and choose **Import Token from Hardcover Plugin** if you already use `hardcoverapp.koplugin`.

### Required Hardcover API Scopes (Read-Only)

Generate a Personal Access Token at [https://hardcover.app/account/api](https://hardcover.app/account/api) with these read-only scopes:

- `read:me:content`
- `read:library`
- `read:goals`
- `read:journal`
- `read:catalog:data`

*(Legacy Hardcover API tokens created before August 2026 also work.)*

## Usage

- **Navigate Months:** Tap `<` / `>`, swipe left/right, or use hardware page-turn buttons. Tap **Today** to jump back to the current month.
- **Day Details:** Tap any calendar cell to open the day breakdown popup.
- **Cycle Books / Goals:** When you have multiple currently reading books or goals, tap the `1 / N ›` pill on the card header.
- **Settings (`⚙`):** Sync Now, Take Screenshot, Set API Token, Import Token from Hardcover Plugin, toggle Sunday/Monday week start, toggle book covers, or Clear Cache.

## Tests

From the repository root, run:

```sh
luajit tests/run_tests.lua
```

The unit tests require no KOReader runtime or network access and cover date math, journal metadata parsing, page-progress filtering, calendar lane assignment, streaks, goals, and currently reading cards.

## License

[MIT](LICENSE)
