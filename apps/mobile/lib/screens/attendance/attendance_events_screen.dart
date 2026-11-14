// lib/screens/attendance/attendance_events_screen.dart
import 'package:flutter/material.dart';

import '../../services/attendance_api.dart';
import 'event_roster_screen.dart';

class AttendanceEventsScreen extends StatefulWidget {
  const AttendanceEventsScreen({super.key});

  @override
  State<AttendanceEventsScreen> createState() => _AttendanceEventsScreenState();
}

class _AttendanceEventsScreenState extends State<AttendanceEventsScreen> {
  List<AttendanceEvent>? _events;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    final result = await AttendanceApi.todayEvents();
    if (!mounted) return;
    setState(() {
      if (result.isSuccess) {
        _events = result.value;
      } else {
        _error = result.message;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: const Text('Absențe · Azi'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
              TextButton(
                onPressed: _load,
                child: const Text('Încearcă din nou', style: TextStyle(color: Colors.redAccent)),
              ),
            ],
          ),
        ),
      );
    }
    if (_events == null) {
      return const Center(child: CircularProgressIndicator(color: Colors.red));
    }
    if (_events!.isEmpty) {
      return RefreshIndicator(
        color: Colors.red,
        onRefresh: _load,
        child: ListView(
          children: const [
            SizedBox(height: 160),
            Center(
              child: Text(
                'Nu există evenimente programate astăzi.',
                style: TextStyle(color: Colors.white54),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: Colors.red,
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _events!.length,
        itemBuilder: (context, index) {
          final e = _events![index];
          final depts = e.departments.isEmpty ? 'Club' : e.departments.join(', ');
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Material(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () async {
                  final updated = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) => EventRosterScreen(eventId: e.id, eventTitle: e.title),
                    ),
                  );
                  if (updated == true) _load();
                },
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              e.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(depts, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                            const SizedBox(height: 6),
                            Text(
                              '${e.markedParticipants} / ${e.totalParticipants} marcați',
                              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: Colors.white38),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}