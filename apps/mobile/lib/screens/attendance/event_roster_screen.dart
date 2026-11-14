// lib/screens/attendance/event_roster_screen.dart
import 'package:flutter/material.dart';

import '../../services/attendance_api.dart';
import '../../widgets/auth_widgets.dart';

class EventRosterScreen extends StatefulWidget {
  final String eventId;
  final String eventTitle;

  const EventRosterScreen({
    super.key,
    required this.eventId,
    required this.eventTitle,
  });

  @override
  State<EventRosterScreen> createState() => _EventRosterScreenState();
}

class _EventRosterScreenState extends State<EventRosterScreen> {
  EventRoster? _roster;
  final Map<String, String> _statuses = {};
  final _searchController = TextEditingController();
  String _query = '';
  String? _error;
  bool _saving = false;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _show(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _load() async {
    setState(() => _error = null);
    final result = await AttendanceApi.roster(widget.eventId);
    if (!mounted) return;
    setState(() {
      if (result.isSuccess) {
        _roster = result.value;
        _statuses
          ..clear()
          ..addEntries(
            _roster!.participants.map((p) => MapEntry(p.userId, p.attendanceStatus)),
          );
      } else {
        _error = result.message;
      }
    });
  }

  String _normalize(String input) => input
      .toLowerCase()
      .replaceAll('ă', 'a')
      .replaceAll('â', 'a')
      .replaceAll('î', 'i')
      .replaceAll('ș', 's')
      .replaceAll('ş', 's')
      .replaceAll('ț', 't')
      .replaceAll('ţ', 't')
      .trim();

  List<RosterParticipant> _filtered() {
    final all = _roster!.participants;
    final q = _normalize(_query);
    if (q.isEmpty) return all;
    return all.where((p) {
      final name = _normalize('${p.lastName} ${p.firstName}');
      final reversed = _normalize('${p.firstName} ${p.lastName}');
      final acronym = _normalize(p.acronym ?? '');
      return name.contains(q) || reversed.contains(q) || acronym.contains(q);
    }).toList();
  }

  void _toggleStatus(String userId, String chosen) {
    setState(() {
      final current = _statuses[userId] ?? 'unknown';
      _statuses[userId] = (current == chosen) ? 'unknown' : chosen;
    });
  }

  void _markRemainingPresent() {
    setState(() {
      for (final p in _roster!.participants) {
        if ((_statuses[p.userId] ?? 'unknown') == 'unknown') {
          _statuses[p.userId] = 'present';
        }
      }
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final result = await AttendanceApi.saveRoster(widget.eventId, _statuses);
    if (!mounted) return;
    setState(() => _saving = false);

    if (result.isSuccess) {
      _show('Prezența a fost salvată.');
      Navigator.of(context).pop(true);
    } else {
      _show(result.message!);
    }
  }

  Future<void> _exportExcel() async {
    setState(() => _exporting = true);
    final result = await AttendanceApi.exportXlsx(widget.eventId);
    if (!mounted) return;
    setState(() => _exporting = false);

    if (result.isSuccess) {
      _show('Fișier salvat: ${result.value}');
    } else {
      _show(result.message!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: Text(_roster?.eventTitle ?? widget.eventTitle),
        actions: [
          if (_roster != null)
            IconButton(
              tooltip: 'Exportă Excel (.xlsx)',
              onPressed: _exporting ? null : _exportExcel,
              icon: _exporting
                  ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
                  : const Icon(Icons.download_outlined),
            ),
        ],
      ),
      body: _buildBody(),
      bottomNavigationBar: _roster == null
          ? null
          : SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: AuthButton(
            label: 'Salvează prezența',
            loading: _saving,
            onPressed: _saving ? null : _save,
          ),
        ),
      ),
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
    if (_roster == null) {
      return const Center(child: CircularProgressIndicator(color: Colors.red));
    }

    final presentCount = _statuses.values.where((v) => v == 'present').length;
    final absentCount = _statuses.values.where((v) => v == 'absent').length;
    final excusedCount = _statuses.values.where((v) => v == 'excused').length;
    final unknownCount = _statuses.values.where((v) => v == 'unknown').length;
    final visible = _filtered();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _CounterChip(label: 'Prezenți', count: presentCount, color: Colors.green),
              _CounterChip(label: 'Absenți', count: absentCount, color: Colors.redAccent),
              _CounterChip(label: 'Motivați', count: excusedCount, color: Colors.orange),
              _CounterChip(label: 'Nemarcați', count: unknownCount, color: Colors.white54),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            controller: _searchController,
            style: const TextStyle(color: Colors.white),
            onChanged: (v) => setState(() => _query = v),
            decoration: authInputDecoration('Caută voluntar sau acronim').copyWith(
              prefixIcon: const Icon(Icons.search, color: Colors.white54),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                icon: const Icon(Icons.clear, color: Colors.white54),
                onPressed: () {
                  _searchController.clear();
                  setState(() => _query = '');
                },
              ),
            ),
          ),
        ),
        if (unknownCount > 0)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _markRemainingPresent,
                icon: const Icon(Icons.done_all, size: 18, color: Colors.green),
                label: Text(
                  'Marchează restul ($unknownCount) prezenți',
                  style: const TextStyle(color: Colors.green, fontSize: 13),
                ),
              ),
            ),
          ),
        Expanded(
          child: visible.isEmpty
              ? const Center(
            child: Text(
              'Niciun voluntar găsit.',
              style: TextStyle(color: Colors.white54),
            ),
          )
              : ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            itemCount: visible.length,
            itemBuilder: (context, index) {
              final p = visible[index];
              final status = _statuses[p.userId] ?? 'unknown';
              final acronym = (p.acronym != null && p.acronym!.isNotEmpty)
                  ? ' (${p.acronym})'
                  : '';
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${p.lastName} ${p.firstName}$acronym',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (p.departments.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        p.departments.join(', '),
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _StatusButton(
                            label: 'Prezent',
                            selected: status == 'present',
                            color: Colors.green,
                            onTap: () => _toggleStatus(p.userId, 'present'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _StatusButton(
                            label: 'Absent',
                            selected: status == 'absent',
                            color: Colors.redAccent,
                            onTap: () => _toggleStatus(p.userId, 'absent'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _StatusButton(
                            label: 'Motivat',
                            selected: status == 'excused',
                            color: Colors.orange,
                            onTap: () => _toggleStatus(p.userId, 'excused'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CounterChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _CounterChip({required this.label, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          '$count',
          style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
      ],
    );
  }
}

class _StatusButton extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _StatusButton({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.25) : Colors.black26,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? color : Colors.white12,
            width: selected ? 1.5 : 1,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: selected ? color : Colors.white70,
            fontSize: 12,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}