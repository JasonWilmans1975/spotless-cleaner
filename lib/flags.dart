/// Redesign features with no backend yet. Flip one on once its data is in
/// place — every use is marked `TODO(redesign)`.
library;

/// Notifications bell on Schedule — there's no notifications feed.
const kRedesignNotifications = false;

/// Payout / bank details (Earnings prompt, Profile row) — nothing stores them.
const kRedesignPayouts = false;

/// DBS / insurance documents on Profile — only approval status exists.
const kRedesignVerificationDocs = false;

/// Help & support row — there's no support channel in the app.
const kRedesignHelp = false;

/// Booking preferences on Working hours (max jobs per day, travel radius,
/// minimum notice) — customer availability doesn't use them yet.
const kRedesignBookingPreferences = false;

/// "See your public profile" on Profile — the customer-facing profile lives in
/// the customer app, so there's nothing to preview here yet.
const kRedesignPublicProfile = false;
