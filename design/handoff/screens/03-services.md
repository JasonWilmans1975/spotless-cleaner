# 03 · My services  (Redesign)

**Replaces:** Services (My services list with delete, Rate history)
**Visual target:** `03-services.png`, full length `03-services-full.png` · **Exact values:** `03-services.html`

## Purpose
Manage offered services and rates. Keeps tap-to-edit rate, edit details for proposed services, delete, rate history.

## Layout (top → bottom)
- Top bar 'My services' + subtitle, round primary '+' button -> Add a service.
- Service cards: icon tile, name, 'Proposed by you' pill (these also get full-detail edit), 'Default £X' or 'Using default rate', large rate + unit on the right; footer: 'Edit rate' soft pill button + red trash icon button.
- Suggestion card (hero style): 'Offer Standard home cleaning' -> Add a service.
- 'Rate history' card: vertical timeline with primary dots — service, 'by you', old rate struck through -> new rate, timestamp.

## Interactions & states
- Edit rate -> existing rate editor (bottom sheet).
- Delete -> confirm dialog -> existing delete.

## Data
- Cleaner services + rates, rate history.

## Backend notes
- None

## Done when
- Matches the PNG at 390pt on an iPhone simulator; no overflow at 375pt / 430pt; long names wrap or ellipsize gracefully.
- Loading, empty and error states exist (skeleton or spinner in the card shapes, EmptyState widget, SnackBar for errors).
- All existing behaviour of the replaced screen still works; colours/fonts come from the theme only; `flutter analyze` clean.
