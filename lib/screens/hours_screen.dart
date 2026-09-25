import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../api_client.dart';
import '../flags.dart';
import '../format.dart';
import '../ui/layout.dart';
import '../ui/tiles.dart';

const _weekdayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

/// A run of consecutive days off, shown as one row ("Mon 6 – Fri 10 Oct").
typedef TimeOffRange = ({DateTime first, DateTime last, List<int> ids});

/// Groups days off (any order) into runs of consecutive dates, soonest first.
List<TimeOffRange> groupTimeOff(List<TimeOff> days) {
  final sorted = [...days]..sort((a, b) => a.date.compareTo(b.date));
  final out = <TimeOffRange>[];
  for (final d in sorted) {
    final last = out.isEmpty ? null : out.last;
    if (last != null && daysUntil(d.date, last.last) <= 1) {
      out[out.length - 1] = (first: last.first, last: d.date, ids: [...last.ids, d.id]);
    } else {
      out.add((first: d.date, last: d.date, ids: [d.id]));
    }
  }
  return out;
}

/// "Mon 6 Oct" or "Mon 6 – Fri 10 Oct" for a time-off run.
String timeOffLabel(TimeOffRange r) {
  String day(DateTime d) => shortDate(d).replaceFirst(',', '');
  return r.first == r.last ? day(r.first) : '${day(r.first)} – ${day(r.last)}';
}

/// Self-service weekly working hours and days off — pushed from Profile. Same
/// hours data the admin sets on a cleaner's behalf via /admin/cleaners on the
/// website (cleaner_hours: one row per weekday worked, with a start/end time).
class HoursScreen extends StatefulWidget {
  /// Load overrides for tests; default to the API.
  final Future<List<WorkingHours>> Function()? loadHours;
  final Future<List<TimeOff>> Function()? loadTimeOff;

  const HoursScreen({super.key, this.loadHours, this.loadTimeOff});

  @override
  State<HoursScreen> createState() => _HoursScreenState();
}

/// Local editable state for one day of the week — mutated in place via setState
/// rather than rebuilding the whole list on every toggle/time change.
class _DayRow {
  bool working;
  TimeOfDay start;
  TimeOfDay end;
  _DayRow({required this.working, required this.start, required this.end});
}

class _HoursScreenState extends State<HoursScreen> {
  final _api = ApiClient();
  bool _loading = true;
  String? _error;
  bool _saving = false;
  List<_DayRow> _days = _defaultDays();
  List<TimeOff>? _timeOff; // null while loading
  String? _timeOffError;
  bool _savingTimeOff = false;

  static List<_DayRow> _defaultDays() => List.generate(
        7,
        (_) => _DayRow(working: false, start: const TimeOfDay(hour: 8, minute: 0), end: const TimeOfDay(hour: 17, minute: 0)),
      );

  @override
  void initState() {
    super.initState();
    _load();
    _loadTimeOff();
  }

  TimeOfDay _parseTime(String hhmm) {
    final parts = hhmm.split(':');
    final h = parts.isNotEmpty ? (int.tryParse(parts[0]) ?? 8) : 8;
    final m = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
    return TimeOfDay(hour: h, minute: m);
  }

  String _fmtTime(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final hours = await (widget.loadHours ?? _api.getMyHours)();
      final days = _defaultDays();
      for (final h in hours) {
        if (h.weekday < 0 || h.weekday > 6) continue;
        days[h.weekday] = _DayRow(working: true, start: _parseTime(h.startTime), end: _parseTime(h.endTime));
      }
      if (!mounted) return;
      setState(() {
        _days = days;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _loadTimeOff() async {
    setState(() => _timeOffError = null);
    try {
      final days = await (widget.loadTimeOff ?? _api.getTimeOff)();
      if (mounted) setState(() => _timeOff = days);
    } catch (e) {
      if (mounted) setState(() => _timeOffError = e.toString());
    }
  }

  Future<void> _addTimeOff() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final range = await showDateRangePicker(
      context: context,
      firstDate: today,
      lastDate: DateTime(today.year + 1, today.month, today.day),
      helpText: 'Days off',
      saveText: 'Add',
    );
    if (range == null || !mounted) return;
    setState(() => _savingTimeOff = true);
    try {
      await _api.addTimeOff(range.start, range.end);
      HapticFeedback.selectionClick();
      await _loadTimeOff();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _savingTimeOff = false);
    }
  }

  Future<void> _removeTimeOff(TimeOffRange r) async {
    setState(() => _savingTimeOff = true);
    try {
      for (final id in r.ids) {
        await _api.removeTimeOff(id);
      }
      await _loadTimeOff();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _savingTimeOff = false);
    }
  }

  Future<void> _editDay(int index) async {
    final day = _days[index];
    final result = await showModalBottomSheet<(TimeOfDay, TimeOfDay)>(
      context: context,
      builder: (_) => _TimeRangeSheet(dayName: _weekdayNames[index], start: day.start, end: day.end),
    );
    if (result == null) return;
    setState(() {
      day.start = result.$1;
      day.end = result.$2;
    });
  }

  Future<void> _save() async {
    for (var i = 0; i < 7; i++) {
      final d = _days[i];
      if (!d.working) continue;
      final startMin = d.start.hour * 60 + d.start.minute;
      final endMin = d.end.hour * 60 + d.end.minute;
      if (startMin >= endMin) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${_weekdayNames[i]}: end time must be after start time')));
        return;
      }
    }
    HapticFeedback.mediumImpact();
    setState(() => _saving = true);
    try {
      final hours = <WorkingHours>[
        for (var i = 0; i < 7; i++)
          if (_days[i].working) WorkingHours(weekday: i, startTime: _fmtTime(_days[i].start), endTime: _fmtTime(_days[i].end)),
      ];
      await _api.updateMyHours(hours);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Working hours saved')));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      body = ListView(children: [
        EmptyState(
          icon: LucideIcons.wifiOff,
          title: "Couldn't load your hours",
          message: _error,
          actionLabel: 'Try again',
          onAction: _load,
        ),
      ]);
    } else {
      var i = 0;
      Widget section(Widget child) => Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: FadeSlideIn(index: i++, child: child),
          );
      body = ListView(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
        children: [
          section(const SectionHeader('Weekly hours')),
          section(SpotlessCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(children: [
              for (var n = 0; n < 7; n++) ...[
                if (n > 0) const Divider(),
                _DayLine(
                  name: _weekdayNames[n],
                  day: _days[n],
                  onToggle: (v) {
                    HapticFeedback.selectionClick();
                    setState(() => _days[n].working = v);
                  },
                  onEdit: () => _editDay(n),
                ),
              ],
            ]),
          )),
          section(_timeOffCard()),
          // TODO(redesign): booking preferences (max jobs per day, travel radius, minimum notice) —
          // customer availability doesn't use them yet (kRedesignBookingPreferences).
          if (kRedesignBookingPreferences) section(const SectionHeader('Booking preferences')),
        ],
      );
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(children: [
            const ScreenHeader(title: 'Working hours', subtitle: 'When customers can book you', showBack: true),
            Expanded(child: body),
          ]),
        ),
        bottomNavigationBar: _loading || _error != null
            ? null
            : StickyBottomBar(
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                  child: _saving
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Save working hours'),
                ),
              ),
      ),
    );
  }

  Widget _timeOffCard() {
    final s = context.tokens;
    final ranges = _timeOff == null ? const <TimeOffRange>[] : groupTimeOff(_timeOff!);
    final dayCount = _timeOff?.length ?? 0;
    final String subtitle;
    if (_timeOffError != null) {
      subtitle = "Couldn't load your days off";
    } else if (_timeOff == null) {
      subtitle = 'Loading…';
    } else if (dayCount == 0) {
      subtitle = 'No time off planned';
    } else {
      subtitle = '$dayCount ${dayCount == 1 ? 'day' : 'days'} off coming up';
    }
    return SpotlessCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          IconTile(LucideIcons.sun, size: 42, circle: true, background: s.goldSoft, foreground: s.gold),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Time off', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              Text(subtitle, style: TextStyle(fontSize: 13, color: s.muted)),
            ]),
          ),
          const SizedBox(width: 8),
          if (_timeOffError != null)
            TextButton(onPressed: _loadTimeOff, child: const Text('Retry'))
          else
            FilledButton(
              onPressed: _savingTimeOff || _timeOff == null ? null : _addTimeOff,
              style: FilledButton.styleFrom(
                backgroundColor: s.primarySofter,
                foregroundColor: context.colors.primary,
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
              ),
              child: _savingTimeOff
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(LucideIcons.plus, size: 15),
                      SizedBox(width: 4),
                      Text('Add dates'),
                    ]),
            ),
        ]),
        if (ranges.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Divider(),
          for (final r in ranges)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(children: [
                Icon(LucideIcons.calendarRange, size: 16, color: s.muted),
                const SizedBox(width: 10),
                Expanded(child: Text(timeOffLabel(r), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
                IconButton(
                  tooltip: 'Remove ${timeOffLabel(r)}',
                  onPressed: _savingTimeOff ? null : () => _removeTimeOff(r),
                  style: IconButton.styleFrom(backgroundColor: Colors.transparent, side: BorderSide.none),
                  icon: Icon(LucideIcons.x, size: 17, color: s.red),
                ),
              ]),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text("Days off are saved straight away — customers can't book you on them.",
                style: TextStyle(fontSize: 12.5, color: s.muted)),
          ),
        ],
      ]),
    );
  }
}

class _DayLine extends StatelessWidget {
  const _DayLine({required this.name, required this.day, required this.onToggle, required this.onEdit});
  final String name;
  final _DayRow day;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;

  String _t(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final s = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(children: [
        SizedBox(
          width: 96,
          child: Text(name,
              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: day.working ? null : s.muted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ),
        Expanded(
          child: Semantics(
            button: day.working,
            label: day.working ? '$name hours, ${_t(day.start)} to ${_t(day.end)}' : '$name, day off',
            excludeSemantics: true,
            child: Pressable(
              enabled: day.working,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: day.working ? onEdit : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    height: 36,
                    alignment: Alignment.center,
                    decoration: ShapeDecoration(
                      shape: const StadiumBorder(),
                      color: day.working ? s.primarySofter : s.lineSoft,
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        day.working ? '${_t(day.start)} – ${_t(day.end)}' : 'Day off',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: day.working ? context.colors.primary : s.muted,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Switch(value: day.working, onChanged: onToggle),
      ]),
    );
  }
}

/// From / Until for one day; pops with the pair, or null if dismissed.
class _TimeRangeSheet extends StatefulWidget {
  const _TimeRangeSheet({required this.dayName, required this.start, required this.end});
  final String dayName;
  final TimeOfDay start, end;

  @override
  State<_TimeRangeSheet> createState() => _TimeRangeSheetState();
}

class _TimeRangeSheetState extends State<_TimeRangeSheet> {
  late TimeOfDay _start = widget.start, _end = widget.end;

  bool get _valid => _start.hour * 60 + _start.minute < _end.hour * 60 + _end.minute;

  Future<void> _pick(bool isStart) async {
    final picked = await showTimePicker(context: context, initialTime: isStart ? _start : _end);
    if (picked == null) return;
    setState(() => isStart ? _start = picked : _end = picked);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.tokens;
    Widget row(IconData icon, String label, TimeOfDay t, bool isStart) => SettingsRow(
          icon: icon,
          title: label,
          subtitle: t.format(context),
          onTap: () => _pick(isStart),
        );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('${widget.dayName} hours', style: s.heading(20)),
          const SizedBox(height: 8),
          row(LucideIcons.sunrise, 'From', _start, true),
          const Divider(),
          row(LucideIcons.sunset, 'Until', _end, false),
          if (!_valid)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('End time must be after start time', style: TextStyle(color: s.red, fontSize: 13)),
            ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _valid ? () => Navigator.pop(context, (_start, _end)) : null,
            child: const Text('Done'),
          ),
        ]),
      ),
    );
  }
}
