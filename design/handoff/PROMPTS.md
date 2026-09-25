# Prompts for Claude Code — Cleaner app

Paste these one at a time. Run `/clear` between steps: every prompt points at the files, so a fresh context works and stays sharp.
Review on the simulator (hot reload) and commit after each step before moving on.

### Step 0 — Understand & plan (use Plan mode: Shift+Tab)
```
Read design/handoff/HANDOFF.md and every file in design/handoff/screens/ (look at the PNGs too).
Then explore this codebase: routing/navigation, state management, theme setup, where each existing screen lives, and the Supabase models/queries each screen uses.
Produce: (1) a table mapping every design screen to the existing file(s) it replaces or the new file it needs, (2) for each "New" feature, which data already exists and what is missing, (3) the list of shared widgets you will create and where, (4) any dependencies you want to add.
Do not write code yet.
```

### Step 1 — Theme, shared widgets, navigation shell
```
Following design/handoff/HANDOFF.md: add design/handoff/spotless_theme.dart to the app (lib/theme/), add google_fonts, switch MaterialApp to SpotlessTheme.light().
Create the shared widgets listed under "Shared building blocks" and the navigation shell described there, keeping all existing routes working.
Add a hidden debug screen (only in debug builds) that shows every shared widget so I can review them. Run flutter analyze and stop.
```

### Step 2 — Schedule
```
Implement screen 01 "Schedule" from design/handoff/screens/01-schedule.md.
Visual target: 01-schedule.png and 01-schedule-full.png; take exact spacing/sizes/colours from 01-schedule.html.
It replaces the existing *Schedule (Booking requests with Confirm/Decline, Upcoming, Completed)* screen — keep every piece of its current functionality.
Reuse the shared widgets and theme tokens; follow the hard rules in design/handoff/HANDOFF.md.
When finished: run flutter analyze, tell me how to reach the screen, list TODO(redesign) items, then stop for my review.
```
### Step 3 — Job details
```
Implement screen 02 "Job details" from design/handoff/screens/02-job.md.
Visual target: 02-job.png and 02-job-full.png; take exact spacing/sizes/colours from 02-job.html.
This is a new screen — wire it to real data where it exists and follow the Backend notes for the rest (flags + TODOs, no schema changes).
Reuse the shared widgets and theme tokens; follow the hard rules in design/handoff/HANDOFF.md.
When finished: run flutter analyze, tell me how to reach the screen, list TODO(redesign) items, then stop for my review.
```
### Step 4 — My services
```
Implement screen 03 "My services" from design/handoff/screens/03-services.md.
Visual target: 03-services.png and 03-services-full.png; take exact spacing/sizes/colours from 03-services.html.
It replaces the existing *Services (My services list with delete, Rate history)* screen — keep every piece of its current functionality.
Reuse the shared widgets and theme tokens; follow the hard rules in design/handoff/HANDOFF.md.
When finished: run flutter analyze, tell me how to reach the screen, list TODO(redesign) items, then stop for my review.
```
### Step 5 — Add a service
```
Implement screen 04 "Add a service" from design/handoff/screens/04-add-service.md.
Visual target: 04-add-service.png and 04-add-service-full.png; take exact spacing/sizes/colours from 04-add-service.html.
It replaces the existing *Add a service (Existing / Propose new tabs)* screen — keep every piece of its current functionality.
Reuse the shared widgets and theme tokens; follow the hard rules in design/handoff/HANDOFF.md.
When finished: run flutter analyze, tell me how to reach the screen, list TODO(redesign) items, then stop for my review.
```
### Step 6 — Working hours
```
Implement screen 05 "Working hours" from design/handoff/screens/05-working-hours.md.
Visual target: 05-working-hours.png and 05-working-hours-full.png; take exact spacing/sizes/colours from 05-working-hours.html.
It replaces the existing *Working hours (existing screen behind Profile > Working hours)* screen — keep every piece of its current functionality.
Reuse the shared widgets and theme tokens; follow the hard rules in design/handoff/HANDOFF.md.
When finished: run flutter analyze, tell me how to reach the screen, list TODO(redesign) items, then stop for my review.
```
### Step 7 — Profile
```
Implement screen 06 "Profile" from design/handoff/screens/06-profile.md.
Visual target: 06-profile.png and 06-profile-full.png; take exact spacing/sizes/colours from 06-profile.html.
It replaces the existing *Profile (photo, name, Approved cleaner, Contact details + Edit, Working hours, Log out)* screen — keep every piece of its current functionality.
Reuse the shared widgets and theme tokens; follow the hard rules in design/handoff/HANDOFF.md.
When finished: run flutter analyze, tell me how to reach the screen, list TODO(redesign) items, then stop for my review.
```
### Step 8 — Earnings
```
Implement screen 07 "Earnings" from design/handoff/screens/07-earnings.md.
Visual target: 07-earnings.png and 07-earnings-full.png; take exact spacing/sizes/colours from 07-earnings.html.
This is a new screen — wire it to real data where it exists and follow the Backend notes for the rest (flags + TODOs, no schema changes).
Reuse the shared widgets and theme tokens; follow the hard rules in design/handoff/HANDOFF.md.
When finished: run flutter analyze, tell me how to reach the screen, list TODO(redesign) items, then stop for my review.
```

### Final step — Motion & polish pass
```
Do a polish pass over every redesigned screen using the "Motion" section of design/handoff/HANDOFF.md:
entrance animations, animated selection states, press feedback, haptics, skeleton loading states, empty states.
Check dark text contrast, 44pt touch targets, and text scaling up to 1.3x. List anything you could not match to the designs.
```

If the customer app already has `spotless_theme.dart` and the shared widgets, copy them across (or move them into a shared package) in Step 1 instead of rebuilding.
