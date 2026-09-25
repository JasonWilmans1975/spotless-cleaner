import 'package:flutter/material.dart';

import '../main.dart';

import '../api_client.dart';

const _weekdayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

/// Self-service weekly working hours — pushed from the Profile tab. Same data
/// the admin sets on a cleaner's behalf via /admin/cleaners on the website
/// (cleaner_hours: one row per weekday worked, with a start/end time), now
/// editable by the cleaner themselves.
class HoursScreen extends StatefulWidget {
  const HoursScreen({super.key});

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
  List<_DayRow> _days = List.generate(
    7,
    (_) => _DayRow(working: false, start: const TimeOfDay(hour: 8, minute: 0), end: const TimeOfDay(hour: 17, minute: 0)),
  );

  @override
  void initState() {
    super.initState();
    _load();
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
      final hours = await _api.getMyHours();
      final days = List.generate(
        7,
        (_) => _DayRow(working: false, start: const TimeOfDay(hour: 8, minute: 0), end: const TimeOfDay(hour: 17, minute: 0)),
      );
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

  Future<void> _pickTime(int index, {required bool isStart}) async {
    final current = isStart ? _days[index].start : _days[index].end;
    final picked = await showTimePicker(context: context, initialTime: current);
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _days[index].start = picked;
      } else {
        _days[index].end = picked;
      }
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
    return Scaffold(
      appBar: AppBar(title: const Text('Working hours')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    const SizedBox(height: 40),
                    Icon(Icons.wifi_off, size: 40, color: kBrandMuted2),
                    const SizedBox(height: 12),
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton(onPressed: _load, child: const Text('Try again')),
                  ],
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  children: [
                    const Text(
                      "Set the days and hours customers can book you. Turn a day off if you don't work it.",
                      style: TextStyle(color: kBrandMuted, fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    for (var i = 0; i < 7; i++)
                      _DayCard(
                        label: _weekdayNames[i],
                        day: _days[i],
                        onToggle: (v) => setState(() => _days[i].working = v),
                        onPickStart: () => _pickTime(i, isStart: true),
                        onPickEnd: () => _pickTime(i, isStart: false),
                      ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Save working hours'),
                    ),
                  ],
                ),
    );
  }
}

class _DayCard extends StatelessWidget {
  final String label;
  final _DayRow day;
  final ValueChanged<bool> onToggle;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;

  const _DayCard({
    required this.label,
    required this.day,
    required this.onToggle,
    required this.onPickStart,
    required this.onPickEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                Switch(value: day.working, onChanged: onToggle),
              ],
            ),
            if (day.working)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onPickStart,
                        child: Text('From ${day.start.format(context)}'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onPickEnd,
                        child: Text('Until ${day.end.format(context)}'),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
