# 06 · Profile  (Redesign)

**Replaces:** Profile (photo, name, Approved cleaner, Contact details + Edit, Working hours, Log out)
**Visual target:** `06-profile.png`, full length `06-profile-full.png` · **Exact values:** `06-profile.html`

## Purpose
Cleaner identity, verification and settings. Keeps photo edit, contact details edit, working hours link, log out.

## Layout (top → bottom)
- Top bar 'Profile' + settings icon.
- Profile card: 96px photo with camera badge, name, email, 'Approved cleaner' green pill, stats row (Upcoming, Services, Rating or 'New').
- 'See your public profile' soft button.
- Contact details card with Edit (phone, address).
- Groups: WORK (Working hours -> Working hours screen, Earnings & payouts with gold 'Action needed' pill, Reviews), VERIFICATION (DBS, Insurance with green 'Verified' pills), MORE (Notifications, Help).
- Red-text 'Log out' button.

## Interactions & states
- Existing edit flows unchanged.

## Data
- Cleaner profile + approval status.

## Backend notes
- Verification docs are new — show only approval status if that's all that exists.

## Done when
- Matches the PNG at 390pt on an iPhone simulator; no overflow at 375pt / 430pt; long names wrap or ellipsize gracefully.
- Loading, empty and error states exist (skeleton or spinner in the card shapes, EmptyState widget, SnackBar for errors).
- All existing behaviour of the replaced screen still works; colours/fonts come from the theme only; `flutter analyze` clean.
