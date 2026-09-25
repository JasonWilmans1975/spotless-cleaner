# 01 · Schedule  (Redesign)

**Replaces:** Schedule (Booking requests with Confirm/Decline, Upcoming, Completed)
**Visual target:** `01-schedule.png`, full length `01-schedule-full.png` · **Exact values:** `01-schedule.html`

## Purpose
The cleaner's home: act on requests fast and see the week.

## Layout (top → bottom)
- Header: avatar, greeting + first name, notifications icon.
- Availability card: status dot, 'Accepting new bookings' / 'Paused' + helper, switch (green when on).
- 'THIS WEEK' hero card: booked £ total, jobs count, hours scheduled, 'Earnings >' link.
- Week strip (white card) with 7 day buttons; selected = ink; accent dot on days with jobs.
- 'Booking requests' + gold '1 awaiting you' pill. Request card: gold header strip 'New request · respond soon', service icon tile + name + price, rows (date/time, address, customer), Decline (ghost) + Accept (primary) buttons.
- After Accept: green confirmation banner with Undo; after Decline: neutral banner with Undo (Undo = short grace period before committing, or simply revert UI if you commit immediately).
- 'Upcoming' job cards (date block, service, price, time, address, Confirmed pill, reference, 'Directions').
- 'Completed' dashed empty state.
- Bottom nav: Schedule (badge = pending requests), Earnings, Services, Profile.

## Interactions & states
- Accept/Decline call the existing confirm/decline logic.
- Tap upcoming job -> Job details.
- Week strip filters the lists to the selected day (or scrolls to it).

## Data
- Pending requests, upcoming and completed bookings for this cleaner.

## Backend notes
- Availability pause switch is new — needs a boolean on the cleaner profile; TODO if missing.

## Done when
- Matches the PNG at 390pt on an iPhone simulator; no overflow at 375pt / 430pt; long names wrap or ellipsize gracefully.
- Loading, empty and error states exist (skeleton or spinner in the card shapes, EmptyState widget, SnackBar for errors).
- All existing behaviour of the replaced screen still works; colours/fonts come from the theme only; `flutter analyze` clean.
