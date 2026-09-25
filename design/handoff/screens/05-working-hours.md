# 05 · Working hours  (Redesign)

**Replaces:** Working hours (existing screen behind Profile > Working hours)
**Visual target:** `05-working-hours.png`, full length `05-working-hours-full.png` · **Exact values:** `05-working-hours.html`

## Purpose
Set weekly availability and booking preferences.

## Layout (top → bottom)
- Top bar 'Working hours' + subtitle.
- 'Weekly hours' card: row per day — name, time-range pill (tap to edit with time pickers), switch.
- 'Time off' card: sun icon, status, 'Add dates' soft button.
- 'Booking preferences' card: Max jobs per day stepper, travel radius chips (3/5/10/15 mi), minimum notice chips (12h/24h/48h).
- Sticky 'Save working hours'.

## Interactions & states
- Keep whatever the current screen saves; new preferences only if fields exist.

## Data
- Cleaner working hours.

## Backend notes
- Time off, max jobs, radius, notice are new — TODO if missing.

## Done when
- Matches the PNG at 390pt on an iPhone simulator; no overflow at 375pt / 430pt; long names wrap or ellipsize gracefully.
- Loading, empty and error states exist (skeleton or spinner in the card shapes, EmptyState widget, SnackBar for errors).
- All existing behaviour of the replaced screen still works; colours/fonts come from the theme only; `flutter analyze` clean.
