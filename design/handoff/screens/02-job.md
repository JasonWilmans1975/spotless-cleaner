# 02 · Job details  (New)

**Replaces:** —
**Visual target:** `02-job.png`, full length `02-job-full.png` · **Exact values:** `02-job.html`

## Purpose
Everything needed on the day of a job.

## Layout (top → bottom)
- Top bar: service name + reference/date, help icon.
- Map preview card (use a static map or placeholder) with 'Navigate' dark pill -> opens Apple/Google Maps via url_launcher.
- Status card by phase: Ready ('Starts …', 'you'll earn £X', primary 'Start job'), In progress (hero card, green live dot, elapsed timer, 'Finish job'), Done (green banner).
- Customer card: avatar, name, message + call buttons; address and access notes rows.
- Checklist card: progress text + green progress bar + checkbox rows (from service's what's-included).
- Photos: two dashed tiles 'Before photos' / 'After photos'.

## Interactions & states
- Start/Finish update booking status (if statuses exist) and notify customer.
- Checklist is local state unless persisted.

## Data
- Booking, customer, service included items.

## Backend notes
- In-progress/completed statuses, photos storage — TODO if missing.

## Done when
- Matches the PNG at 390pt on an iPhone simulator; no overflow at 375pt / 430pt; long names wrap or ellipsize gracefully.
- Loading, empty and error states exist (skeleton or spinner in the card shapes, EmptyState widget, SnackBar for errors).
- All existing behaviour of the replaced screen still works; colours/fonts come from the theme only; `flutter analyze` clean.
