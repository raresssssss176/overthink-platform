// lib/screens/calendar/calendar_screen.dart
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../services/calendar_api.dart';

DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  final Map<DateTime, List<CalendarEvent>> _byDay = {};
  DateTime _focused = _dayOnly(DateTime.now());
  DateTime? _selected = _dayOnly(DateTime.now());
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadVisible(_focused);
  }

  /// Loads the visible month plus a week on each side, so the days from the
  /// neighbouring months shown in the grid also get their markers.
  Future<void> _loadVisible(DateTime month) async {
    final first = DateTime(month.year, month.month, 1);
    final last = DateTime(month.year, month.month + 1, 0);
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await CalendarApi.events(
      first.subtract(const Duration(days: 7)),
      last.add(const Duration(days: 7)),
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (result.isSuccess) {
        _byDay.clear();
        for (final e in result.value!) {
          _byDay.putIfAbsent(_dayOnly(e.date), () => []).add(e);
        }
      } else {
        _error = result.message;
      }
    });
  }

  List<CalendarEvent> _eventsOn(DateTime day) => _byDay[_dayOnly(day)] ?? const [];

  @override
  Widget build(BuildContext context) {
    final selectedEvents = _selected == null ? const <CalendarEvent>[] : _eventsOn(_selected!);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: const Text('Calendar'),
      ),
      body: Stack(
        children: [
          // Faded club logo in the background, as in the sketch.
          Positioned.fill(
            child: Center(
              child: Opacity(
                opacity: 0.06,
                child: Image.asset('assets/images/logo.png', width: 280, fit: BoxFit.contain),
              ),
            ),
          ),
          Column(
            children: [
              if (_loading)
                const LinearProgressIndicator(color: Colors.red, backgroundColor: Colors.transparent),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                ),
              TableCalendar<CalendarEvent>(
                firstDay: DateTime(2024, 1, 1),
                lastDay: DateTime(2030, 12, 31),
                focusedDay: _focused,
                startingDayOfWeek: StartingDayOfWeek.monday,
                selectedDayPredicate: (day) => _selected != null && isSameDay(_selected, day),
                eventLoader: _eventsOn,
                onDaySelected: (selected, focused) {
                  setState(() {
                    _selected = _dayOnly(selected);
                    _focused = focused;
                  });
                },
                onPageChanged: (focused) {
                  _focused = focused;
                  _loadVisible(focused);
                },
                headerStyle: const HeaderStyle(
                  formatButtonVisible: false,
                  titleCentered: true,
                  titleTextStyle: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                  leftChevronIcon: Icon(Icons.chevron_left, color: Colors.white),
                  rightChevronIcon: Icon(Icons.chevron_right, color: Colors.white),
                ),
                daysOfWeekStyle: const DaysOfWeekStyle(
                  weekdayStyle: TextStyle(color: Colors.white54),
                  weekendStyle: TextStyle(color: Colors.white54),
                ),
                calendarStyle: CalendarStyle(
                  outsideDaysVisible: false,
                  defaultTextStyle: const TextStyle(color: Colors.white),
                  weekendTextStyle: const TextStyle(color: Colors.white70),
                  todayDecoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.35),
                    shape: BoxShape.circle,
                  ),
                  selectedDecoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                  markerDecoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
                ),
              ),
              const Divider(color: Colors.white12, height: 1),
              Expanded(child: _dayList(selectedEvents)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dayList(List<CalendarEvent> events) {
    if (_selected == null) {
      return const Center(child: Text('Selectează o zi.', style: TextStyle(color: Colors.white54)));
    }
    if (events.isEmpty) {
      return const Center(
        child: Text('Nu există evenimente în această zi.', style: TextStyle(color: Colors.white54)),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          '${events.length} ${events.length == 1 ? 'eveniment' : 'evenimente'}',
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
        const SizedBox(height: 8),
        for (final e in events)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.title,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 4),
                Text(
                  e.departments.isEmpty ? 'Club' : e.departments.join(', '),
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
      ],
    );
  }
}