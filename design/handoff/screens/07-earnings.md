# 07 · Earnings  (New)

**Replaces:** —
**Visual target:** `07-earnings.png`, full length `07-earnings-full.png` · **Exact values:** `07-earnings.html`

## Purpose
Show what the cleaner has earned and will earn.

## Layout (top → bottom)
- Top bar 'Earnings' with Week/Month segmented control.
- Hero card: period label, big total, jobs pill, bar chart (7 days or weekly bars; value labels above bars; empty bars as stubs).
- Gold 'Add payout details' prompt (bank icon) when no payout account.
- 2x2 stat tiles: Jobs completed, Avg. per job, Hours booked, Tips.
- Activity list: service, date · reference, amount + status pill.

## Interactions & states
- Week/Month toggles the aggregation.

## Data
- Bookings for this cleaner with price and status.

## Backend notes
- Payout details are new — link to a TODO screen.

## Done when
- Matches the PNG at 390pt on an iPhone simulator; no overflow at 375pt / 430pt; long names wrap or ellipsize gracefully.
- Loading, empty and error states exist (skeleton or spinner in the card shapes, EmptyState widget, SnackBar for errors).
- All existing behaviour of the replaced screen still works; colours/fonts come from the theme only; `flutter analyze` clean.
