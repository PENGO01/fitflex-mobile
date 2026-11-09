import 'package:flutter/material.dart';

import '../components/components.dart';
import '../design_tokens.dart';
import '../tone_theme.dart';
import '../i18n.dart';
import '../models.dart';
import '../formatters.dart';

/// `2099-05-04` → `Mon 4 May` (localized short names).
String formatScheduleDate(BuildContext context, String isoDate) {
  final d = DateTime.tryParse(isoDate);
  if (d == null) return isoDate;
  const weekdays = [
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
    'sunday',
  ];
  return '${context.tr('cal.day.${weekdays[d.weekday - 1]}')} ${d.day} '
      '${context.tr('cal.monthShort.${d.month}')}';
}

/// Key used by [AvailabilityCalendar.selected].
String scheduleSlotKey(String date, String slot) => '$date|$slot';

/// A trainer's dated calendar (EAT): month header, a horizontal date strip
/// with open-slot counts, and the day's hourly slots grouped into morning /
/// afternoon / evening.
///
/// Members pass [onSlotTap] to pick available slots ([selected] holds the
/// picked `date|slot` keys). The trainer's own view sets [showBookings] to
/// list who booked each taken slot.
class AvailabilityCalendar extends StatefulWidget {
  const AvailabilityCalendar({
    super.key,
    required this.days,
    this.selected = const {},
    this.onSlotTap,
    this.showBookings = false,
  });

  final List<ScheduleDay> days;
  final Set<String> selected;
  final void Function(ScheduleDay day, ScheduleSlot slot)? onSlotTap;
  final bool showBookings;

  @override
  State<AvailabilityCalendar> createState() => _AvailabilityCalendarState();
}

class _AvailabilityCalendarState extends State<AvailabilityCalendar> {
  late int _index = _firstOpenIndex();
  final _strip = ScrollController();

  static const _tileWidth = 58.0;
  static const _tileGap = 8.0;

  int _firstOpenIndex() {
    final i = widget.days.indexWhere((d) => d.openCount > 0);
    return i < 0 ? 0 : i;
  }

  @override
  void didUpdateWidget(covariant AvailabilityCalendar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_index >= widget.days.length) _index = 0;
  }

  @override
  void dispose() {
    _strip.dispose();
    super.dispose();
  }

  void _select(int index) {
    setState(() => _index = index);
    if (_strip.hasClients) {
      _strip.animateTo(
        (index * (_tileWidth + _tileGap) - 80).clamp(
          0.0,
          _strip.position.maxScrollExtent,
        ),
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.days.isEmpty) {
      return FFEmptyState(title: context.tr('cal.noHours'));
    }
    final day = widget.days[_index];
    final date = DateTime.tryParse(day.date);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (date != null)
          Text(
            '${context.tr('cal.month.${date.month}')} ${date.year}',
            key: const Key('calendar-month'),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        const SizedBox(height: FFTokens.spacingSm),
        SizedBox(
          height: 92,
          child: ListView.separated(
            key: const Key('calendar-date-strip'),
            controller: _strip,
            scrollDirection: Axis.horizontal,
            itemCount: widget.days.length,
            separatorBuilder: (_, _) => const SizedBox(width: _tileGap),
            itemBuilder: (context, i) => _DateTile(
              day: widget.days[i],
              isToday: i == 0,
              selected: i == _index,
              width: _tileWidth,
              onTap: () => _select(i),
            ),
          ),
        ),
        const SizedBox(height: FFTokens.spacingMd),
        if (day.slots.isEmpty ||
            (widget.onSlotTap != null && day.openCount == 0))
          _emptyDay(context, day)
        else
          ..._slotGroups(context, day),
        const SizedBox(height: FFTokens.spacingSm),
        _Legend(showSelected: widget.onSlotTap != null),
        if (widget.showBookings) ..._bookings(context, day),
      ],
    );
  }

  Widget _emptyDay(BuildContext context, ScheduleDay day) {
    final next = widget.days
        .skip(_index + 1)
        .where((d) => d.openCount > 0)
        .firstOrNull;
    return FFCard(
      key: const Key('calendar-empty-day'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr(day.slots.isEmpty ? 'cal.dayOff' : 'cal.dayFull'),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (next != null)
            FFButton(
              key: const Key('calendar-next-available'),
              label: context
                  .tr('cal.nextAvailable')
                  .replaceAll('{date}', formatScheduleDate(context, next.date)),
              onPressed: () => _select(widget.days.indexOf(next)),
              variant: FFButtonVariant.ghost,
              size: FFButtonSize.sm,
              icon: Icons.arrow_forward,
            ),
        ],
      ),
    );
  }

  List<Widget> _slotGroups(BuildContext context, ScheduleDay day) {
    int hour(ScheduleSlot s) => int.tryParse(s.slot.split(':').first) ?? 0;
    final groups = {
      'cal.morning': day.slots.where((s) => hour(s) < 12).toList(),
      'cal.afternoon': day.slots
          .where((s) => hour(s) >= 12 && hour(s) < 17)
          .toList(),
      'cal.evening': day.slots.where((s) => hour(s) >= 17).toList(),
    };
    return [
      for (final entry in groups.entries)
        if (entry.value.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              context.tr(entry.key),
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 360 ? 4 : 3;
              const gap = 8.0;
              final width =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: entry.value
                    .map(
                      (slot) => SizedBox(
                        width: width,
                        child: _SlotTile(
                          day: day,
                          slot: slot,
                          selected: widget.selected.contains(
                            scheduleSlotKey(day.date, slot.slot),
                          ),
                          showMember: widget.showBookings,
                          onTap: widget.onSlotTap == null || !slot.isAvailable
                              ? null
                              : () => widget.onSlotTap!(day, slot),
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
          const SizedBox(height: FFTokens.spacingMd),
        ],
    ];
  }

  List<Widget> _bookings(BuildContext context, ScheduleDay day) {
    final booked = day.slots.where((s) => s.isBooked).toList();
    return [
      FFSectionTitle(context.tr('cal.bookedSessions')),
      if (booked.isEmpty)
        Text(
          context.tr('cal.noBookings'),
          style: Theme.of(context).textTheme.bodySmall,
        )
      else
        ...booked.map(
          (s) => FFActionTile(
            key: Key('calendar-booking-${day.date}-${s.slot}'),
            icon: Icons.person_outline,
            title: s.memberName ?? context.tr('trainer.member'),
            subtitle:
                '${context.localSlotTime(s.slot)}–${context.localSlotTime(_slotEnd(s.slot))}'
                '${s.bookingStatus == 'payment_pending' ? ' · ${context.tr('cal.awaitingPayment')}' : ''}',
            onTap: () {},
          ),
        ),
    ];
  }
}

/// `09:00` → `10:00` (sessions are one hour).
String _slotEnd(String slot) {
  final parts = slot.split(':');
  final h = int.tryParse(parts.first) ?? 0;
  return '${((h + 1) % 24).toString().padLeft(2, '0')}:${parts.length > 1 ? parts[1] : '00'}';
}

class _DateTile extends StatelessWidget {
  const _DateTile({
    required this.day,
    required this.isToday,
    required this.selected,
    required this.width,
    required this.onTap,
  });

  final ScheduleDay day;
  final bool isToday;
  final bool selected;
  final double width;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final date = DateTime.tryParse(day.date);
    final open = day.openCount;
    final fg = selected ? scheme.onPrimary : scheme.onSurface;
    final label = formatScheduleDate(context, day.date);
    return Semantics(
      button: true,
      selected: selected,
      label:
          '$label, ${context.tr('cal.openCount').replaceAll('{n}', '$open')}',
      child: InkWell(
        key: Key('calendar-day-${day.date}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: width,
          decoration: BoxDecoration(
            color: selected ? scheme.primary : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
            border: isToday && !selected
                ? Border.all(color: scheme.primary, width: 1.5)
                : null,
          ),
          padding: const EdgeInsets.symmetric(vertical: 6),
          // Scales down instead of overflowing at large system text sizes.
          child: ExcludeSemantics(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    isToday
                        ? context.tr('cal.today')
                        : context.tr('cal.day.${day.weekday}'),
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: fg.withValues(alpha: .8),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${date?.day ?? ''}',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: fg,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      color: open > 0
                          ? (selected
                                ? scheme.onPrimary.withValues(alpha: .14)
                                : FFToneTheme.of(context).brand.bg)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      open > 0 ? '$open' : '–',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: selected
                            ? scheme.onPrimary
                            : (open > 0
                                  ? FFToneTheme.of(context).brand.fg
                                  : fg.withValues(alpha: .5)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SlotTile extends StatelessWidget {
  const _SlotTile({
    required this.day,
    required this.slot,
    required this.selected,
    required this.showMember,
    required this.onTap,
  });

  final ScheduleDay day;
  final ScheduleSlot slot;
  final bool selected;
  final bool showMember;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final booked = slot.isBooked;
    final past = slot.status == 'past';
    final Color bg;
    final Color fg;
    if (selected) {
      bg = scheme.primary;
      fg = scheme.onPrimary;
    } else if (booked) {
      bg = scheme.surfaceContainerHighest;
      fg = scheme.onSurface.withValues(alpha: .55);
    } else if (past) {
      bg = Colors.transparent;
      fg = scheme.onSurface.withValues(alpha: .35);
    } else {
      bg = scheme.surface;
      fg = FFToneTheme.of(context).brand.fg;
    }
    final state = selected
        ? context.tr('cal.selected')
        : booked
        ? context.tr('cal.booked')
        : past
        ? context.tr('cal.past')
        : context.tr('cal.available');
    return Semantics(
      button: onTap != null,
      selected: selected,
      label:
          '${formatScheduleDate(context, day.date)} ${context.localSlotTime(slot.slot)}–${context.localSlotTime(_slotEnd(slot.slot))}, $state',
      child: InkWell(
        key: Key('calendar-slot-${day.date}-${slot.slot}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? scheme.primary
                  : (booked || past)
                  ? scheme.outlineVariant.withValues(alpha: .5)
                  : FFToneTheme.of(context).brand.border,
            ),
          ),
          child: ExcludeSemantics(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  slot.slot,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: fg,
                    decoration: booked ? TextDecoration.lineThrough : null,
                  ),
                ),
                if (showMember && booked && slot.memberName != null)
                  Text(
                    slot.memberName!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: fg),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.showSelected});

  final bool showSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget item(Color fill, Color border, String key, {bool strike = false}) =>
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: border),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              context.tr(key),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                decoration: strike ? TextDecoration.lineThrough : null,
              ),
            ),
          ],
        );
    return Wrap(
      key: const Key('calendar-legend'),
      spacing: 12,
      runSpacing: 6,
      children: [
        item(
          scheme.surface,
          FFToneTheme.of(context).brand.border,
          'cal.available',
        ),
        if (showSelected) item(scheme.primary, scheme.primary, 'cal.selected'),
        item(
          scheme.surfaceContainerHighest,
          scheme.outlineVariant,
          'cal.booked',
          strike: true,
        ),
        item(Colors.transparent, scheme.outlineVariant, 'cal.past'),
      ],
    );
  }
}
