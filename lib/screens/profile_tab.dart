import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../api_client.dart';
import '../flags.dart';
import '../theme/spotless_theme.dart';
import '../ui/layout.dart';
import '../ui/tiles.dart';
import 'hours_screen.dart';
import 'reviews_screen.dart';

/// Profile photo, stats, contact details and bio, work links, approval status
/// and logout. The [cleaner] itself is owned by HomeScreen (so the
/// pending-approval banner above the tabs and this screen never disagree);
/// edits call back up via [onCleanerUpdated] instead of holding a copy.
class ProfileTab extends StatefulWidget {
  final Cleaner cleaner;
  final ValueChanged<Cleaner> onCleanerUpdated;
  final Future<void> Function() onLogout;

  /// Confirmed jobs still to come (from HomeScreen's bookings).
  final int upcomingCount;
  final VoidCallback onOpenEarnings;

  const ProfileTab({
    super.key,
    required this.cleaner,
    required this.onCleanerUpdated,
    required this.onLogout,
    this.upcomingCount = 0,
    required this.onOpenEarnings,
  });

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  final _api = ApiClient();
  bool _uploadingPhoto = false;
  bool _loggingOut = false;
  CleanerStats? _stats;
  int? _servicesCount;

  static const _maxPhotoBytes = 4.5 * 1024 * 1024;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  /// Rating and services count for the stat tiles — nice-to-haves, so a
  /// failure just leaves them blank.
  Future<void> _loadStats() async {
    try {
      final results = await Future.wait([_api.getMyStats(), _api.getMyServiceRates()]);
      if (!mounted) return;
      setState(() {
        _stats = results[0] as CleanerStats?;
        _servicesCount = (results[1] as List<MyServiceRate>).length;
      });
    } catch (_) {}
  }

  void _toast(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(LucideIcons.camera),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(LucideIcons.image),
              title: const Text('Choose from library'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    XFile? picked;
    try {
      picked = await ImagePicker().pickImage(source: source, maxWidth: 1600, imageQuality: 85);
    } catch (e) {
      _toast('Could not open camera/library: $e');
      return;
    }
    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    if (bytes.length > _maxPhotoBytes) {
      _toast('That image is too large — please use one under 4.5MB.');
      return;
    }
    final ext = picked.path.contains('.') ? picked.path.split('.').last : 'jpg';

    setState(() => _uploadingPhoto = true);
    try {
      final avatarUrl = await _api.uploadPhoto(bytes, ext);
      widget.onCleanerUpdated(widget.cleaner.withAvatar(avatarUrl));
      _toast('Photo updated');
    } catch (e) {
      _toast(e.toString());
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _editDetails() async {
    final updated = await showModalBottomSheet<Cleaner>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _DetailsSheet(cleaner: widget.cleaner, api: _api),
    );
    if (updated == null) return;
    widget.onCleanerUpdated(updated);
    _toast('Details saved');
  }

  Future<void> _confirmLogout() async {
    setState(() => _loggingOut = true);
    await widget.onLogout(); // navigates away on success; no need to reset _loggingOut
  }

  @override
  Widget build(BuildContext context) {
    final s = context.tokens;
    final cleaner = widget.cleaner;
    final address = [cleaner.address, cleaner.postcode].where((x) => x?.trim().isNotEmpty ?? false).join(', ');
    final stats = _stats;
    final rating = stats != null && stats.reviewCount > 0 && stats.avgRating != null
        ? stats.avgRating!.toStringAsFixed(1)
        : 'New';
    final reviewCount = stats?.reviewCount ?? 0;

    var i = 0;
    Widget section(Widget child) => Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: FadeSlideIn(index: i++, child: child),
        );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: Column(children: [
          const ScreenHeader(title: 'Profile'),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadStats,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                children: [
                  section(_ProfileCard(
                    cleaner: cleaner,
                    uploading: _uploadingPhoto,
                    onChangePhoto: _uploadingPhoto ? null : _pickPhoto,
                    stats: [
                      ('${widget.upcomingCount}', 'Upcoming'),
                      (_servicesCount == null ? '–' : '$_servicesCount', 'Services'),
                      (rating, 'Rating'),
                    ],
                  )),
                  // TODO(redesign): "See your public profile" preview (kRedesignPublicProfile).
                  section(SpotlessCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Row(children: [
                        const Expanded(
                          child: Text('Contact details', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                        ),
                        TextButton(onPressed: _editDetails, child: const Text('Edit')),
                      ]),
                      _InfoRow(
                        icon: LucideIcons.phone,
                        text: cleaner.phone?.trim().isNotEmpty == true ? cleaner.phone!.trim() : 'No phone on file',
                      ),
                      _InfoRow(icon: LucideIcons.mapPin, text: address.isEmpty ? 'No address on file' : address),
                      const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider()),
                      Text('About you', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: s.muted)),
                      const SizedBox(height: 4),
                      Text(
                        cleaner.bio?.trim().isNotEmpty == true
                            ? cleaner.bio!.trim()
                            : 'Add a short bio — customers see it on your profile when choosing a cleaner.',
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.5,
                          color: cleaner.bio?.trim().isNotEmpty == true ? SpotlessColors.inkSoft : s.muted,
                          fontStyle: cleaner.bio?.trim().isNotEmpty == true ? FontStyle.normal : FontStyle.italic,
                        ),
                      ),
                    ]),
                  )),
                  section(SettingsGroup(label: 'Work', children: [
                    SettingsRow(
                      icon: LucideIcons.clock,
                      title: 'Working hours',
                      subtitle: 'Your days, times and time off',
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HoursScreen())),
                    ),
                    SettingsRow(
                      icon: LucideIcons.chartColumn,
                      title: 'Earnings',
                      subtitle: 'What you’ve earned and have booked',
                      // TODO(redesign): payout details + "Action needed" pill (kRedesignPayouts).
                      trailing: kRedesignPayouts ? SpotlessPill('Action needed', colors: s.awaiting) : null,
                      onTap: widget.onOpenEarnings,
                    ),
                    SettingsRow(
                      icon: LucideIcons.star,
                      title: 'Reviews',
                      subtitle: reviewCount == 0 ? 'No reviews yet' : '$rating average · $reviewCount ${reviewCount == 1 ? 'review' : 'reviews'}',
                      iconBackground: s.accentSoft,
                      iconColor: context.colors.secondary,
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ReviewsScreen())),
                    ),
                  ])),
                  // TODO(redesign): DBS / insurance documents (kRedesignVerificationDocs) — approval status only for now.
                  section(SettingsGroup(label: 'Verification', children: [
                    SettingsRow(
                      icon: LucideIcons.badgeCheck,
                      title: 'Spotless approval',
                      subtitle: cleaner.isPendingApproval ? 'An admin is reviewing your application' : 'You can be booked by customers',
                      iconBackground: cleaner.isPendingApproval ? s.goldSoft : s.greenSoft,
                      iconColor: cleaner.isPendingApproval ? s.gold : s.green,
                      trailing: cleaner.isPendingApproval
                          ? SpotlessPill('Pending', colors: s.awaiting)
                          : SpotlessPill('Approved', colors: s.approved),
                    ),
                  ])),
                  // TODO(redesign): notifications + help rows (kRedesignNotifications, kRedesignHelp).
                  OutlinedButton(
                    onPressed: _loggingOut ? null : _confirmLogout,
                    style: OutlinedButton.styleFrom(foregroundColor: s.red),
                    child: _loggingOut
                        ? SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: s.red))
                        : const Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(LucideIcons.logOut, size: 18),
                            SizedBox(width: 8),
                            Flexible(child: Text('Log out', overflow: TextOverflow.ellipsis)),
                          ]),
                  ),
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.cleaner, required this.uploading, required this.onChangePhoto, required this.stats});
  final Cleaner cleaner;
  final bool uploading;
  final VoidCallback? onChangePhoto;
  final List<(String, String)> stats;

  @override
  Widget build(BuildContext context) {
    final s = context.tokens;
    return SpotlessCard(
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
      child: Column(children: [
        Semantics(
          button: true,
          label: 'Change photo',
          child: GestureDetector(
            onTap: onChangePhoto,
            child: Stack(clipBehavior: Clip.none, children: [
              InitialsAvatar(name: cleaner.name, url: cleaner.avatarUrl, size: 96),
              if (uploading)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: .4), shape: BoxShape.circle),
                    child: const Center(
                      child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                    ),
                  ),
                ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: context.colors.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Icon(LucideIcons.camera, size: 15, color: Colors.white),
                ),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Text(cleaner.name, textAlign: TextAlign.center, style: s.heading(22)),
        if (cleaner.email?.trim().isNotEmpty == true)
          Text(cleaner.email!.trim(), textAlign: TextAlign.center, style: TextStyle(fontSize: 13.5, color: s.muted)),
        const SizedBox(height: 10),
        cleaner.isPendingApproval
            ? SpotlessPill('Awaiting approval', colors: s.awaiting, icon: LucideIcons.hourglass)
            : SpotlessPill('Approved cleaner', colors: s.approved, icon: LucideIcons.shieldCheck),
        const SizedBox(height: 16),
        Row(children: [
          for (var n = 0; n < stats.length; n++) ...[
            if (n > 0) const SizedBox(width: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                decoration: BoxDecoration(color: s.primarySofter, borderRadius: BorderRadius.circular(s.radiusMd)),
                child: Column(children: [
                  FittedBox(fit: BoxFit.scaleDown, child: Text(stats[n].$1, style: s.heading(20))),
                  Text(stats[n].$2, style: TextStyle(fontSize: 12, color: s.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
                ]),
              ),
            ),
          ],
        ]),
      ]),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final s = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: 1), child: Icon(icon, size: 16, color: s.muted)),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 14, height: 1.4, color: SpotlessColors.inkSoft))),
      ]),
    );
  }
}

/// Edit phone / address / postcode (required, as before) and the bio.
/// Pops with the updated [Cleaner] once saved; errors stay in the sheet.
class _DetailsSheet extends StatefulWidget {
  const _DetailsSheet({required this.cleaner, required this.api});
  final Cleaner cleaner;
  final ApiClient api;

  @override
  State<_DetailsSheet> createState() => _DetailsSheetState();
}

class _DetailsSheetState extends State<_DetailsSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _phone = TextEditingController(text: widget.cleaner.phone ?? '');
  late final _address = TextEditingController(text: widget.cleaner.address ?? '');
  late final _postcode = TextEditingController(text: widget.cleaner.postcode ?? '');
  late final _bio = TextEditingController(text: widget.cleaner.bio ?? '');
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_phone, _address, _postcode, _bio]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _required(String? v) => (v == null || v.trim().isEmpty) ? 'Required' : null;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated = await widget.api.updateProfile(
        phone: _phone.text.trim(),
        address: _address.text.trim(),
        postcode: _postcode.text.trim(),
        bio: _bio.text.trim(),
      );
      if (mounted) Navigator.pop(context, updated);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.tokens;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Edit your details', style: s.heading(20)),
              const SizedBox(height: 16),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Phone'),
                validator: _required,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _address,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Address'),
                validator: _required,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _postcode,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Postcode'),
                validator: _required,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _bio,
                minLines: 3,
                maxLines: 6,
                maxLength: 500,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'About you (optional)',
                  hintText: 'What you love about cleaning, what you bring, languages you speak…',
                  helperText: 'Shown to customers on your profile',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                ErrorBanner(_error!),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Save'),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
