import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../screens/home_screen.dart';
import '../theme/spotless_theme.dart';
import 'layout.dart';
import 'pickers.dart';
import 'tiles.dart';

/// Every shared widget on one page, for review on the simulator.
/// Reached by long-pressing the Schedule title — debug builds only.
class DebugGallery extends StatefulWidget {
  const DebugGallery({super.key});

  @override
  State<DebugGallery> createState() => _DebugGalleryState();
}

class _DebugGalleryState extends State<DebugGallery> {
  static final _today = DateUtils.dateOnly(DateTime.now());
  final _strip = GlobalKey<DayStripState>();

  int _step = 1;
  DateTime? _day;
  String _range = '';
  String? _time = '10:00';
  int _tip = 5;
  int _cleaner = 0;
  bool _check = true;
  bool _switch = true;
  int _navIndex = 0;

  @override
  Widget build(BuildContext context) {
    final s = context.tokens;
    Widget label(String text) => Padding(padding: const EdgeInsets.only(top: 28, bottom: 10), child: Overline(text));

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
          children: [
            const ScreenHeader(title: 'Widget gallery', subtitle: 'Debug builds only', showBack: true),

            label('Pills'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final st in ['pending', 'confirmed', 'completed', 'cancelled'])
                SpotlessPill(st, colors: s.statusColors(st)),
              SpotlessPill('Popular', colors: (s.accentSoft, s.accentDeep)),
              SpotlessPill('Approved cleaner', colors: s.approved, icon: LucideIcons.shieldCheck),
            ]),

            label('Hero card'),
            SpotlessHeroCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('YOUR NEXT CLEAN', style: TextStyle(color: s.heroMuted, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1)),
                const SizedBox(height: 8),
                Text('Deep cleaning', style: s.heading(27, color: s.heroInk)),
                Text('Thu 24 Sep · 11:00', style: TextStyle(color: s.heroMuted)),
              ]),
            ),

            label('Section header'),
            SectionHeader('Book a clean', actionLabel: 'See all', onAction: () {}),

            label('Card'),
            SpotlessCard(onTap: () {}, child: const Text('Tappable card with the design shadow')),

            label('Icon tiles & avatars'),
            Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
              const IconTile(LucideIcons.sparkles),
              const IconTile(LucideIcons.house, size: 52),
              IconTile(LucideIcons.gift, circle: true, background: s.accentSoft, foreground: context.colors.secondary),
              const InitialsAvatar(name: 'Lucy Green', size: 56),
              const InitialsAvatar(name: 'sam', size: 40),
              const InitialsAvatar(name: '', size: 32),
            ]),

            label('Date block'),
            Row(children: [DateBlock(_today), const SizedBox(width: 12), DateBlock(_today.add(const Duration(days: 40)))]),

            label('Step progress'),
            StepProgressBar(current: _step),
            Row(children: [
              for (var i = 1; i <= 3; i++) TextButton(onPressed: () => setState(() => _step = i), child: Text('Step $i')),
            ]),

            label('Day strip (90 days) — $_range'),
            DayStrip(
              key: _strip,
              first: _today,
              dayCount: 90,
              selected: _day,
              isEnabled: (d) => d.weekday != DateTime.sunday,
              onSelected: (d) => setState(() => _day = d),
              onVisibleRangeChanged: (a, b) => setState(() => _range = '${a.day}/${a.month} – ${b.day}/${b.month}'),
            ),
            Row(children: [
              TextButton(
                onPressed: () => setState(() => _day = _today.add(const Duration(days: 80))),
                child: const Text('Jump +80 days'),
              ),
              TextButton(onPressed: () => _strip.currentState?.scrollTo(_today), child: const Text('Today')),
            ]),

            label('Choice chip grid'),
            ChoiceChipGrid<String>(
              items: const ['08:00', '09:00', '10:00', '11:00', '12:00', '13:00'],
              labelOf: (t) => t,
              isSelected: (t) => t == _time,
              isEnabled: (t) => t != '09:00',
              onSelected: (t) => setState(() => _time = t),
            ),
            const SizedBox(height: 12),
            ChoiceChipGrid<int>(
              items: const [0, 2, 5, 10],
              columns: 4,
              selectedColor: SpotlessColors.ink,
              labelOf: (v) => v == 0 ? 'No tip' : '£$v',
              isSelected: (v) => v == _tip,
              onSelected: (v) => setState(() => _tip = v),
            ),

            label('Selectable cards'),
            for (var i = 0; i < 2; i++) ...[
              SelectableCard(
                selected: _cleaner == i,
                onTap: () => setState(() => _cleaner = i),
                child: Row(children: [
                  InitialsAvatar(name: i == 0 ? 'Lucy Green' : 'Sam Taylor', size: 46),
                  const SizedBox(width: 12),
                  Expanded(child: Text(i == 0 ? 'Lucy Green' : 'Sam Taylor', style: const TextStyle(fontWeight: FontWeight.w700))),
                  Text(i == 0 ? '£24' : '£20', style: const TextStyle(fontWeight: FontWeight.w700)),
                ]),
              ),
              const SizedBox(height: 10),
            ],
            SelectableCard(
              selected: _check,
              checkbox: true,
              onTap: () => setState(() => _check = !_check),
              child: const Text('Checkbox variant'),
            ),

            label('Timeline'),
            SpotlessCard(
              child: Column(children: [
                const TimelineTile(title: 'Booked', subtitle: '22 Sep, 14:21', state: TimelineState.done),
                const TimelineTile(title: 'Accepted by Lucy', subtitle: '22 Sep, 14:47', state: TimelineState.current),
                TimelineTile(title: 'Done — rate & tip', state: TimelineState.future, isLast: true, onTap: () {}),
              ]),
            ),

            label('Settings group'),
            SettingsGroup(label: 'Your details', children: [
              SettingsRow(icon: LucideIcons.user, title: 'Full name', subtitle: 'Liam Customer', onTap: () {}),
              PillSwitchRow(
                icon: LucideIcons.bell,
                title: 'Booking updates',
                subtitle: 'Push & email',
                value: _switch,
                onChanged: (v) => setState(() => _switch = v),
              ),
              SettingsRow(
                icon: LucideIcons.logOut,
                title: 'Log out',
                iconBackground: s.redSoft,
                iconColor: s.red,
                titleColor: s.red,
                onTap: () {},
              ),
            ]),

            label('Empty state'),
            SpotlessCard(
              child: EmptyState(
                icon: LucideIcons.calendarX,
                title: 'No past cleans',
                message: 'Once a clean is done it will show up here.',
                actionLabel: 'Book a clean',
                onAction: () {},
              ),
            ),

            label('Buttons & inputs'),
            FilledButton(onPressed: () {}, child: const Text('Primary')),
            const SizedBox(height: 10),
            OutlinedButton(onPressed: () {}, child: const Text('Outlined')),
            const SizedBox(height: 10),
            const TextField(decoration: InputDecoration(labelText: 'Full name', hintText: 'Your name')),

            label('Sticky bottom bar'),
            StickyBottomBar(child: FilledButton(onPressed: () {}, child: const Text('Continue'))),

            label('Bottom navigation'),
            CleanerNavBar(index: _navIndex, onSelected: (i) => setState(() => _navIndex = i), scheduleBadge: 2),

            label('Entrance motion'),
            for (var i = 0; i < 3; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: FadeSlideIn(index: i, child: SpotlessCard(child: Text('Staggered card ${i + 1}'))),
              ),
          ],
        ),
      ),
    );
  }
}
