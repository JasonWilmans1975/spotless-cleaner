# Spotless Solutions — Cleaner app UI redesign handoff

You are implementing a UI redesign of the **Spotless Solutions Cleaner app** (Flutter + Supabase).
The designs were made on a design canvas; this folder contains everything you need.
Read this file fully before touching code, then read the spec for the screen you are asked to build.

## Goal
Make the app far more inviting, dynamic and polished **without changing what it does**.
Colours and type come from the Spotless website (localhost:3000) and must stay consistent with it.

## Hard rules
1. **Keep all existing functionality.** Every "Redesign" spec lists what the current screen does — all of it must still work (same Supabase calls, same validation, same navigation outcomes).
2. **Do not change business logic, models, repositories or Supabase queries** unless a spec explicitly says so. Restyle and restructure the widget tree; reuse existing state management (providers/blocs/controllers) exactly as the project already does.
3. **No backend changes without asking.** Features marked *New* that have no backing data: build the UI, feed it from the real data that exists, and hide or mock (clearly) the rest behind a `const bool kRedesign<Feature> = false` style flag. Mark every gap with `// TODO(redesign): …`. Never create tables, columns or migrations on your own — propose them and wait.
4. **Use the theme, not literals.** Wire in `spotless_theme.dart` (`SpotlessTheme.light()`), read colours from `Theme.of(context).colorScheme` and `Theme.of(context).extension<SpotlessTokens>()!`. No hard-coded hex values in screens.
5. **No emoji in UI.** Icons are 1.8px-stroke outline icons (Lucide style). Prefer an outline icon package (e.g. `lucide_icons_flutter`) — ask before adding any dependency; fall back to Material *Outlined/Rounded* icons.
6. **Placeholders**: text in `[square brackets]` and values like "Give £10, get £10", ratings, job counts are design placeholders — use real data or hide.
7. One screen per task. After each screen: `flutter analyze` clean, no overflow at 375pt and 430pt widths, then stop and summarise (files changed, how to reach the screen, TODOs).

## How to read the references (per screen, in `screens/`)
- `NN-slug.png` — visual target, first viewport (390×844 pt, rendered @2x).
- `NN-slug-full.png` — the whole scrollable screen.
- `NN-slug.html` — static HTML of the design: **exact** paddings, font sizes, radii, colours are in the inline styles. Use it to resolve any measurement.
- `NN-slug.md` — purpose, layout top→bottom, interactions, data, backend notes.
- Note: the PNGs were rendered without web fonts, so text shows in a fallback sans. The real fonts are Space Grotesk (headings) and Public Sans (body).
- Units: design px = Flutter logical pixels 1:1.

## Design tokens
| Token | Value | Use |
|---|---|---|
| primary (`--acc`) | `#4A5D8F` | buttons, selected states, links, active nav |
| accent (`--acc2`) | `#B8607A` | stars, favourites, badges, 'New'/'Popular' pills |
| ink | `#26201A` | text, dark hero cards, selected filter chips |
| ink-soft | `#4D4437` | secondary text on white |
| muted | `#6B6254` | captions, helper text (never lighter for small text) |
| line / line-soft | `#E8E1D3` / `#EFEADD` | card borders / dividers |
| surface (`--bg`) | `#FAF7F1` | scaffold background |
| card | `#FFFFFF` | cards, inputs, bottom bars |
| primarySoft / primarySofter | primary mixed 87% / 94% with white | icon tiles, soft buttons, date blocks |
| accentSoft | accent mixed 87% with white | referral card, favourite pills |
| gold / goldSoft | `#7D5F17` / `#F5EAD6` | 'awaiting confirmation' |
| green / greenSoft | `#3F7A4F` / `#E3EFE4` | approved, accepted, verified, availability on |
| red / redSoft | `#A33B3B` / `#F6E3E1` | destructive (delete, cancel, log out) |
| radius | 22 (card), 12 (small tiles = r*.55), 16 (inputs/chips = r*.75), 30 (hero = r+8), pills 999 | |
| type | Headings **Space Grotesk** 700 (letter-spacing -2%), body **Public Sans** | via google_fonts |
| shadow | card: `0 1 2 rgba(60,48,30,.04)` + `0 16 32 -22 rgba(60,48,30,.3)`; primary button: primary @45% blur 22 spread -8 y 10 | |
All of these already exist in `spotless_theme.dart` (`SpotlessColors`, `SpotlessTokens`, `SpotlessTheme.light()`).

## Shared building blocks (build once, reuse everywhere)
Put them under `lib/ui/` (or the project's existing widgets folder):
`SpotlessHeroCard` and `SpotlessPill` (already in the theme file), `SectionHeader` (title + optional trailing link), `IconTile` (rounded square/circle with icon on a soft background), `InitialsAvatar`, `DateBlock` (DOW/day/month), `StepProgressBar` (3 segments + labels), `DayStrip` (7 selectable day chips), `ChoiceChipGrid` (time slots / tips / radius), `SelectableCard` (primary border + soft ring when selected, radio or checkbox), `StickyBottomBar` (white, top border, safe-area padding), `EmptyState`, `TimelineTile` (done / current / future), `SettingsGroup` + `SettingsRow`, `PillSwitchRow`.
Navigation: cleaner app keeps its 4-item bottom nav — Schedule (badge = pending requests), Earnings (new), Services, Profile — restyled: active item gets a primarySoft pill behind the icon and primary label. Job details, Add a service and Working hours push over the shell without the nav bar.

## Motion (the brief asked for "dynamic")
Subtle, fast, consistent: cards fade+slide 8px on first build (staggered 40ms), selection changes use `AnimatedContainer` 180ms easeOut, pills/chips scale 0.97 on press, hero countdown and totals use `AnimatedSwitcher`, page transitions default Cupertino on iOS. Light haptic (`HapticFeedback.selectionClick`) on selections and primary actions. Respect reduced-motion.

## Screens (build in this order)
| # | Screen | Status | Replaces | Spec |
|---|---|---|---|---|
| 01 | Schedule | Redesign | Schedule (Booking requests with Confirm/Decline, Upcoming, Completed) | `screens/01-schedule.md` |
| 02 | Job details | New | — | `screens/02-job.md` |
| 03 | My services | Redesign | Services (My services list with delete, Rate history) | `screens/03-services.md` |
| 04 | Add a service | Redesign | Add a service (Existing / Propose new tabs) | `screens/04-add-service.md` |
| 05 | Working hours | Redesign | Working hours (existing screen behind Profile > Working hours) | `screens/05-working-hours.md` |
| 06 | Profile | Redesign | Profile (photo, name, Approved cleaner, Contact details + Edit, Working hours, Log out) | `screens/06-profile.md` |
| 07 | Earnings | New | — | `screens/07-earnings.md` |

Interactive prototype of the whole flow: the Design canvas "Spotless Solutions — App Redesign" (ask Liam for the link if you need to see behaviour).
