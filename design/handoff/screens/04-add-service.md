# 04 · Add a service  (Redesign)

**Replaces:** Add a service (Existing / Propose new tabs)
**Visual target:** `04-add-service.png`, full length `04-add-service-full.png` · **Exact values:** `04-add-service.html`

## Purpose
Add existing services or propose a new one. Keeps every existing field.

## Layout (top → bottom)
- Top bar 'Add a service'. Segmented control Existing / Propose new.
- Existing: helper text, selectable cards (icon tile, name, default price · duration, checkbox; selected = primary border + soft ring), hint card. Sticky 'Add selected (n)'.
- Propose new: info card about admin review; fields Service name; Icon picker (6 icon options grid — replaces the emoji text field; store the icon key in the same column); Short description with counter; Pricing type Hourly/Fixed chips; Your price with £ prefix and unit suffix; Duration (mins) + Label shown to customers side by side; What's included (one per line). Sticky 'Send for review'.

## Interactions & states
- Same validation and submit calls as today.

## Data
- Services not yet offered by this cleaner.

## Backend notes
- If the icon column expects an emoji, map icon keys -> keep backward compatibility (render old emoji values as text).

## Done when
- Matches the PNG at 390pt on an iPhone simulator; no overflow at 375pt / 430pt; long names wrap or ellipsize gracefully.
- Loading, empty and error states exist (skeleton or spinner in the card shapes, EmptyState widget, SnackBar for errors).
- All existing behaviour of the replaced screen still works; colours/fonts come from the theme only; `flutter analyze` clean.
