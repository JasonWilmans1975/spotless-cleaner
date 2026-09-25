import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../api_client.dart';
import '../flags.dart';
import '../format.dart';
import '../links.dart';
import '../theme/spotless_theme.dart';
import '../ui/layout.dart';
import '../ui/tiles.dart';
import 'chat_screen.dart';
import 'schedule_tab.dart';

enum JobPhase { request, upcoming, ready, inProgress, done, cancelled }

/// Where a job is on the day: a request still to answer, confirmed but on a
/// later day, ready to start (its day has come), in progress, done or cancelled.
JobPhase jobPhase(CleanerBooking b, DateTime now) => switch (b.status) {
      'pending' => JobPhase.request,
      'completed' => JobPhase.done,
      'cancelled' => JobPhase.cancelled,
      _ when b.startedAt != null => JobPhase.inProgress,
      _ when b.date.compareTo(isoDate(now)) > 0 => JobPhase.upcoming,
      _ => JobPhase.ready,
    };

/// "1:05:09" / "12:03" for the in-progress timer.
String elapsedText(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

/// Ticked checklist items per booking for this app session.
/// ponytail: in-memory — survives leaving and reopening the job, not an app
/// restart; persist (shared_preferences or a column) if cleaners need that.
final _checklists = <int, Set<int>>{};

/// Everything needed on the day of a job. Pops with `true` if the booking
/// changed (started / finished) so the Schedule refreshes.
class JobScreen extends StatefulWidget {
  final CleanerBooking booking;

  /// All of this cleaner's bookings, for "first clean together".
  final List<CleanerBooking> allBookings;

  const JobScreen({super.key, required this.booking, this.allBookings = const []});

  @override
  State<JobScreen> createState() => _JobScreenState();
}

class _JobScreenState extends State<JobScreen> {
  final _api = ApiClient();
  late CleanerBooking _b = widget.booking;
  late final Stream<List<ChatMessage>> _chat = _api.watchChat(widget.booking.id);
  bool _changed = false;
  bool _working = false; // start / finish in flight
  Timer? _ticker;
  List<JobPhoto>? _photos;
  String? _uploadingKind;
  Review? _review;

  Set<int> get _done => _checklists.putIfAbsent(_b.id, () => <int>{});

  @override
  void initState() {
    super.initState();
    _syncTicker();
    _loadPhotos();
    if (_b.status == 'completed') _loadReview();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// Ticks once a second while the job is in progress, for the elapsed timer.
  void _syncTicker() {
    final running = jobPhase(_b, DateTime.now()) == JobPhase.inProgress;
    if (running && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
    } else if (!running) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  void _toast(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _loadPhotos() async {
    if (_b.status != 'confirmed' && _b.status != 'completed') return;
    try {
      final photos = await _api.listJobPhotos(_b.id);
      if (mounted) setState(() => _photos = photos);
    } catch (_) {
      if (mounted) setState(() => _photos = const []);
    }
  }

  Future<void> _loadReview() async {
    try {
      final reviews = await _api.getMyReviews();
      final mine = reviews.where((r) => r.bookingId == _b.id).firstOrNull;
      if (mounted) setState(() => _review = mine);
    } catch (_) {}
  }

  CleanerBooking _with({String? status, DateTime? startedAt, DateTime? completedAt}) => CleanerBooking(
        id: _b.id,
        ref: _b.ref,
        serviceName: _b.serviceName,
        date: _b.date,
        startTime: _b.startTime,
        endTime: _b.endTime,
        status: status ?? _b.status,
        customerName: _b.customerName,
        address: _b.address,
        postcode: _b.postcode,
        priceCents: _b.priceCents,
        customerComment: _b.customerComment,
        serviceId: _b.serviceId,
        serviceSlug: _b.serviceSlug,
        serviceFeatures: _b.serviceFeatures,
        phone: _b.phone,
        email: _b.email,
        notes: _b.notes,
        durationMinutes: _b.durationMinutes,
        createdAt: _b.createdAt,
        confirmedAt: _b.confirmedAt,
        startedAt: startedAt ?? _b.startedAt,
        completedAt: completedAt ?? _b.completedAt,
      );

  Future<void> _start() async {
    HapticFeedback.mediumImpact();
    setState(() => _working = true);
    try {
      final at = await _api.startJob(_b.id);
      if (!mounted) return;
      setState(() {
        _b = _with(startedAt: at);
        _changed = true;
      });
      _syncTicker();
    } catch (e) {
      _toast(e.toString());
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _finish() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Finish this job?'),
        content: const Text("It'll be marked as completed and the customer can rate it."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Not yet')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Finish job')),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    HapticFeedback.mediumImpact();
    setState(() => _working = true);
    try {
      await _api.finishJob(_b.id);
      if (!mounted) return;
      setState(() {
        _b = _with(status: 'completed', completedAt: DateTime.now());
        _changed = true;
      });
      _syncTicker();
    } catch (e) {
      _toast(e.toString());
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _addPhoto(String kind) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(children: [
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
        ]),
      ),
    );
    if (source == null) return;
    XFile? picked;
    try {
      picked = await ImagePicker().pickImage(source: source, maxWidth: 2000, imageQuality: 80);
    } catch (e) {
      _toast('Could not open camera/library: $e');
      return;
    }
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    final ext = picked.path.contains('.') ? picked.path.split('.').last : 'jpg';
    setState(() => _uploadingKind = kind);
    try {
      await _api.uploadJobPhoto(_b.id, kind, bytes, ext);
      await _loadPhotos();
    } catch (e) {
      _toast(e.toString());
    } finally {
      if (mounted) setState(() => _uploadingKind = null);
    }
  }

  Future<void> _deletePhoto(JobPhoto photo) async {
    try {
      await _api.deleteJobPhoto(photo);
      await _loadPhotos();
    } catch (e) {
      _toast(e.toString());
    }
  }

  void _showPhotos(String kind) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => StatefulBuilder(builder: (sheet, setSheet) {
        final photos = (_photos ?? const <JobPhoto>[]).where((p) => p.kind == kind).toList();
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('${kind == 'before' ? 'Before' : 'After'} photos', style: context.tokens.heading(20)),
              const SizedBox(height: 12),
              GridView.count(
                shrinkWrap: true,
                crossAxisCount: 3,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  for (final p in photos)
                    Stack(fit: StackFit.expand, children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(context.tokens.radiusSm),
                        child: p.url == null
                            ? ColoredBox(color: context.tokens.lineSoft)
                            : Image.network(p.url!, fit: BoxFit.cover),
                      ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: IconButton(
                          tooltip: 'Delete photo',
                          style: IconButton.styleFrom(
                            fixedSize: const Size(32, 32),
                            minimumSize: const Size(32, 32),
                            backgroundColor: Colors.white,
                          ),
                          onPressed: () async {
                            await _deletePhoto(p);
                            setSheet(() {});
                          },
                          icon: Icon(LucideIcons.trash2, size: 15, color: context.tokens.red),
                        ),
                      ),
                    ]),
                ],
              ),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: () {
                  Navigator.pop(sheet);
                  _addPhoto(kind);
                },
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(LucideIcons.imagePlus, size: 18),
                  SizedBox(width: 8),
                  Flexible(child: Text('Add photo', overflow: TextOverflow.ellipsis)),
                ]),
              ),
            ]),
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final phase = jobPhase(_b, now);
    final d = DateTime.tryParse(_b.date);
    final address = [_b.address, _b.postcode].where((x) => x.trim().isNotEmpty).join(', ');
    var i = 0;
    Widget section(Widget child) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: FadeSlideIn(index: i++, child: child),
        );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark,
        child: Scaffold(
          body: SafeArea(
            bottom: false,
            child: Column(children: [
              // TODO(redesign): help button needs a support channel (kRedesignHelp).
              ScreenHeader(
                title: _b.serviceName,
                subtitle: [_b.ref, if (d != null) shortDate(d).replaceFirst(',', '')].join(' · '),
                showBack: true,
                trailing: [
                  if (kRedesignHelp)
                    IconButton(tooltip: 'Get help', onPressed: () {}, icon: const Icon(LucideIcons.circleHelp, size: 20)),
                ],
              ),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.fromLTRB(20, 6, 20, 28 + MediaQuery.paddingOf(context).bottom),
                  children: [
                    if (address.isNotEmpty) section(_MapCard(address: address, label: _b.postcode)),
                    section(_statusCard(phase, now)),
                    section(_customerCard(address)),
                    if (_b.serviceFeatures.isNotEmpty && phase != JobPhase.cancelled) section(_checklist()),
                    if (_photos != null) ...[
                      section(SectionHeader(
                        'Photos',
                        trailing: Text('Saved with this job', style: TextStyle(fontSize: 12.5, color: context.tokens.muted)),
                      )),
                      section(Row(children: [
                        Expanded(child: _photoTile('before')),
                        const SizedBox(width: 10),
                        Expanded(child: _photoTile('after')),
                      ])),
                    ],
                  ],
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _statusCard(JobPhase phase, DateTime now) {
    final s = context.tokens;
    final minutes = bookingMinutes(_b);
    final earn = '${minutes > 0 ? '${durationText(minutes)} · ' : ''}you\'ll earn ${formatMoney(_b.priceCents)}';
    final d = DateTime.tryParse(_b.date);
    final starts = 'Starts ${d == null ? _b.date : shortDate(d).replaceFirst(',', '')}, ${_b.startTime}';

    Widget banner(Color bg, Color fg, IconData icon, String title, String? subtitle, {Widget? extra}) => Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(s.radius)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              IconTile(icon, size: 42, circle: true, background: Colors.white, foreground: fg),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: fg)),
                  if (subtitle != null) Text(subtitle, style: TextStyle(fontSize: 13, color: fg)),
                ]),
              ),
            ]),
            ?extra,
          ]),
        );

    switch (phase) {
      case JobPhase.request:
        return banner(s.goldSoft, s.gold, LucideIcons.clock, 'Awaiting your answer', 'Accept or decline this request on Schedule.');
      case JobPhase.cancelled:
        return banner(s.redSoft, s.red, LucideIcons.x, 'Cancelled', 'This booking was cancelled.');
      case JobPhase.done:
        final r = _review;
        return banner(
          s.greenSoft,
          s.green,
          LucideIcons.circleCheckBig,
          'Job completed',
          _b.completedAt == null ? earn.replaceFirst("you'll earn", 'earned') : 'Finished ${dayMonthTime(_b.completedAt!)}',
          extra: r == null
              ? null
              : Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      for (var n = 1; n <= 5; n++)
                        Icon(Icons.star_rounded, size: 18, color: n <= r.rating ? context.colors.secondary : Colors.white),
                      if (r.tipCents > 0) ...[
                        const SizedBox(width: 8),
                        Text('+ ${formatMoney(r.tipCents)} tip', style: TextStyle(fontWeight: FontWeight.w700, color: s.green)),
                      ],
                    ]),
                    if (r.comment?.trim().isNotEmpty ?? false)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text('"${r.comment!.trim()}" — ${r.reviewerName}',
                            style: const TextStyle(fontStyle: FontStyle.italic, color: SpotlessColors.inkSoft)),
                      ),
                  ]),
                ),
        );
      case JobPhase.inProgress:
        final elapsed = now.difference(_b.startedAt!);
        return SpotlessHeroCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: s.green,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: s.green.withValues(alpha: .35), spreadRadius: 4)],
                ),
              ),
              const SizedBox(width: 10),
              Text('IN PROGRESS',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 1.15, color: s.heroMuted)),
            ]),
            const SizedBox(height: 12),
            Text(elapsedText(elapsed.isNegative ? Duration.zero : elapsed), style: s.heading(40, color: s.heroInk)),
            Text('Started ${_b.startedAt!.hour.toString().padLeft(2, '0')}:${_b.startedAt!.minute.toString().padLeft(2, '0')} · $earn',
                style: TextStyle(fontSize: 13.5, color: s.heroMuted)),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _working ? null : _finish,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: context.colors.onSurface,
                minimumSize: const Size.fromHeight(52),
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(LucideIcons.circleCheckBig, size: 18),
                SizedBox(width: 8),
                Flexible(child: Text('Finish job', overflow: TextOverflow.ellipsis)),
              ]),
            ),
          ]),
        );
      case JobPhase.upcoming:
      case JobPhase.ready:
        final ready = phase == JobPhase.ready;
        return SpotlessCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const IconTile(LucideIcons.clock, size: 42, circle: true),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(starts, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  Text(earn, style: TextStyle(fontSize: 13, color: s.muted)),
                ]),
              ),
            ]),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: ready && !_working ? _start : null,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
              child: _working
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(LucideIcons.play, size: 18),
                      SizedBox(width: 8),
                      Flexible(child: Text('Start job', overflow: TextOverflow.ellipsis)),
                    ]),
            ),
            if (!ready)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('You can start on the day of the clean.',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: s.muted)),
              ),
          ]),
        );
    }
  }

  Widget _customerCard(String address) {
    final s = context.tokens;
    final previous = previousBookingsWith(_b, widget.allBookings);
    final together = previous == 0 ? 'first clean together' : '${previous + 1} cleans together';
    Widget row(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.only(top: 1), child: Icon(icon, size: 16, color: s.muted)),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 14, height: 1.4, color: SpotlessColors.inkSoft))),
          ]),
        );
    final soft = IconButton.styleFrom(backgroundColor: s.primarySoft, foregroundColor: context.colors.primary, side: BorderSide.none);
    return SpotlessCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          InitialsAvatar(name: _b.customerName, size: 48, background: s.accentSoft, foreground: s.accentDeep),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_b.customerName.trim().isEmpty ? 'Customer' : _b.customerName.trim(),
                  style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
              Text('Customer · $together', style: TextStyle(fontSize: 12.5, color: s.muted)),
            ]),
          ),
          StreamBuilder<List<ChatMessage>>(
            stream: _chat,
            builder: (context, snap) {
              final unread = (snap.data ?? const <ChatMessage>[]).where((m) => m.unreadByCleaner).length;
              return Badge(
                isLabelVisible: unread > 0,
                label: Text('$unread'),
                backgroundColor: context.colors.secondary,
                child: IconButton(
                  tooltip: 'Message customer',
                  style: soft,
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatScreen(booking: _b))),
                  icon: const Icon(LucideIcons.messageSquare, size: 19),
                ),
              );
            },
          ),
          if (_b.phone.trim().isNotEmpty) ...[
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Call customer',
              style: soft,
              onPressed: () async {
                if (!await callPhone(_b.phone)) _toast("Couldn't start a call on this device");
              },
              icon: const Icon(LucideIcons.phone, size: 19),
            ),
          ],
        ]),
        const SizedBox(height: 14),
        const Divider(),
        if (address.isNotEmpty) row(LucideIcons.mapPin, address),
        row(LucideIcons.stickyNote, _b.notes.trim().isEmpty ? 'No access notes from the customer' : _b.notes.trim()),
      ]),
    );
  }

  Widget _checklist() {
    final s = context.tokens;
    final items = _b.serviceFeatures;
    final done = _done.where((n) => n < items.length).length;
    return SpotlessCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Expanded(child: Text('Checklist', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
          Text('$done of ${items.length} done', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: s.muted)),
        ]),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: items.isEmpty ? 0 : done / items.length),
            duration: const Duration(milliseconds: 250),
            builder: (context, v, _) =>
                LinearProgressIndicator(value: v, minHeight: 6, color: s.green, backgroundColor: s.lineSoft),
          ),
        ),
        const SizedBox(height: 6),
        for (var n = 0; n < items.length; n++)
          Semantics(
            checked: _done.contains(n),
            child: InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _done.contains(n) ? _done.remove(n) : _done.add(n));
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 11),
                decoration: BoxDecoration(
                  border: n == items.length - 1 ? null : Border(bottom: BorderSide(color: s.lineSoft)),
                ),
                child: Row(children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: _done.contains(n) ? context.colors.primary : Colors.white,
                      border: Border.all(color: _done.contains(n) ? context.colors.primary : s.line, width: 2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: _done.contains(n) ? const Icon(LucideIcons.check, size: 14, color: Colors.white) : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(items[n],
                        style: TextStyle(
                          fontSize: 14.5,
                          color: _done.contains(n) ? s.muted : null,
                          decoration: _done.contains(n) ? TextDecoration.lineThrough : null,
                        )),
                  ),
                ]),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _photoTile(String kind) {
    final s = context.tokens;
    final photos = (_photos ?? const <JobPhoto>[]).where((p) => p.kind == kind).toList();
    final label = kind == 'before' ? 'Before photos' : 'After photos';
    final uploading = _uploadingKind == kind;
    final radius = BorderRadius.circular(s.radiusMd);
    if (photos.isEmpty) {
      return DashedBorder(
        radius: s.radiusMd,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: radius,
            onTap: uploading ? null : () => _addPhoto(kind),
            child: SizedBox(
              height: 104,
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                uploading
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(LucideIcons.camera, size: 22, color: s.muted),
                const SizedBox(height: 6),
                Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: s.muted)),
              ]),
            ),
          ),
        ),
      );
    }
    final first = photos.first;
    return Pressable(
      child: GestureDetector(
        onTap: () => _showPhotos(kind),
        child: ClipRRect(
          borderRadius: radius,
          child: SizedBox(
            height: 104,
            child: Stack(fit: StackFit.expand, children: [
              first.url == null ? ColoredBox(color: s.lineSoft) : Image.network(first.url!, fit: BoxFit.cover),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withValues(alpha: .55)],
                  ),
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 10,
                child: Text('$label · ${photos.length}',
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
              ),
              if (uploading) const Center(child: CircularProgressIndicator(color: Colors.white)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Map placeholder (dotted "paper" with a pin) and a Navigate pill.
class _MapCard extends StatelessWidget {
  const _MapCard({required this.address, required this.label});
  final String address, label;

  @override
  Widget build(BuildContext context) {
    final s = context.tokens;
    return ClipRRect(
      borderRadius: BorderRadius.circular(s.radius),
      child: Container(
        height: 170,
        decoration: BoxDecoration(
          color: s.lineSoft,
          border: Border.all(color: s.line),
          borderRadius: BorderRadius.circular(s.radius),
        ),
        child: Stack(children: [
          Positioned.fill(child: CustomPaint(painter: _DotsPainter(s.line))),
          Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              IconTile(LucideIcons.mapPin, size: 40, circle: true, background: context.colors.primary, foreground: Colors.white),
              Container(width: 3, height: 10, color: context.colors.primary),
            ]),
          ),
          if (label.trim().isNotEmpty)
            Positioned(
              left: 12,
              top: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: ShapeDecoration(color: Colors.white.withValues(alpha: .85), shape: const StadiumBorder()),
                child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: s.muted)),
              ),
            ),
          Positioned(
            right: 12,
            bottom: 12,
            child: FilledButton(
              onPressed: () async {
                if (!await openDirections(address) && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't open maps")));
                }
              },
              style: FilledButton.styleFrom(
                backgroundColor: context.colors.inverseSurface,
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(LucideIcons.navigation, size: 16),
                SizedBox(width: 6),
                Text('Navigate'),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

class _DotsPainter extends CustomPainter {
  _DotsPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (double y = 8; y < size.height; y += 16) {
      for (double x = 8; x < size.width; x += 16) {
        canvas.drawCircle(Offset(x, y), 1.2, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotsPainter old) => old.color != color;
}
