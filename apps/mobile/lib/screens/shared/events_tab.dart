// lib/screens/shared/events_tab.dart
import 'package:flutter/material.dart';

import '../../services/events_api.dart';
import '../../widgets/auth_widgets.dart';

String _isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _displayDate(String iso) {
  final d = DateTime.parse(iso);
  return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
}

DateTime _today() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

class EventsTab extends StatefulWidget {
  const EventsTab({super.key});

  @override
  State<EventsTab> createState() => _EventsTabState();
}

class _EventsTabState extends State<EventsTab> {
  List<EventDepartment>? _departments;
  List<ManagedEvent>? _events;
  String? _loadError;

  final _titleController = TextEditingController();
  final Set<String> _selectedDepartmentIds = {};
  DateTime _date = _today();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  void _show(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _loadAll() async {
    setState(() => _loadError = null);
    final deps = await EventsApi.departments();
    final events = await EventsApi.manage();
    if (!mounted) return;
    setState(() {
      if (deps.isSuccess && events.isSuccess) {
        _departments = deps.value;
        _events = events.value;
      } else {
        _loadError = deps.message ?? events.message;
      }
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2024),
      lastDate: _today().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _date = DateTime(picked.year, picked.month, picked.day));
    }
  }

  Future<void> _create() async {
    final title = _titleController.text.trim();
    if (title.length < 2) {
      _show('Scrie numele evenimentului (minim 2 caractere).');
      return;
    }
    if (_selectedDepartmentIds.isEmpty) {
      _show('Alege cel puțin un departament.');
      return;
    }

    setState(() => _saving = true);
    final result = await EventsApi.create(
      title: title,
      startsOn: _isoDate(_date),
      departmentIds: _selectedDepartmentIds.toList(),
    );
    if (!mounted) return;
    setState(() => _saving = false);

    if (result.isSuccess) {
      _titleController.clear();
      setState(() => _selectedDepartmentIds.clear());
      _show('Evenimentul a fost adăugat.');
      _loadAll();
    } else {
      _show(result.message!);
    }
  }

  Future<void> _cancel(ManagedEvent e) async {
    setState(() => _saving = true);
    final result = await EventsApi.cancel(e.id);
    if (!mounted) return;
    setState(() => _saving = false);
    _show(result.isSuccess ? 'Evenimentul a fost anulat.' : result.message!);
    if (result.isSuccess) _loadAll();
  }

  @override
  Widget build(BuildContext context) {
    if (_loadError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_loadError!, style: const TextStyle(color: Colors.white70)),
            TextButton(
              onPressed: _loadAll,
              child: const Text('Încearcă din nou', style: TextStyle(color: Colors.redAccent)),
            ),
          ],
        ),
      );
    }
    if (_departments == null || _events == null) {
      return const Center(child: CircularProgressIndicator(color: Colors.red));
    }

    return RefreshIndicator(
      color: Colors.red,
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(20)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Eveniment nou',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                if (_departments!.isEmpty)
                  const Text('Nu ai departamente pentru care să adaugi evenimente.',
                      style: TextStyle(color: Colors.white54))
                else ...[
                  AuthTextField(label: 'Numele evenimentului', controller: _titleController),
                  InkWell(
                    onTap: _pickDate,
                    borderRadius: BorderRadius.circular(15),
                    child: InputDecorator(
                      decoration: authInputDecoration('Data'),
                      child: Text(_displayDate(_isoDate(_date)), style: const TextStyle(color: Colors.white)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Departamente', style: TextStyle(color: Colors.white54, fontSize: 13)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final d in _departments!)
                        FilterChip(
                          label: Text(d.name),
                          selected: _selectedDepartmentIds.contains(d.id),
                          selectedColor: Colors.red,
                          checkmarkColor: Colors.white,
                          backgroundColor: Colors.black26,
                          labelStyle: TextStyle(
                            color: _selectedDepartmentIds.contains(d.id) ? Colors.white : Colors.white70,
                          ),
                          onSelected: (selected) => setState(() {
                            if (selected) {
                              _selectedDepartmentIds.add(d.id);
                            } else {
                              _selectedDepartmentIds.remove(d.id);
                            }
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  AuthButton(
                    label: 'Adaugă eveniment',
                    loading: _saving,
                    onPressed: _saving ? null : _create,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text('Evenimente',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (_events!.isEmpty)
            const Text('Nu există evenimente.', style: TextStyle(color: Colors.white54))
          else
            for (final e in _events!) _eventTile(e),
        ],
      ),
    );
  }

  Widget _eventTile(ManagedEvent e) {
    final cancelled = e.status == 'cancelled';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  e.title,
                  style: TextStyle(
                    color: cancelled ? Colors.white38 : Colors.white,
                    fontWeight: FontWeight.bold,
                    decoration: cancelled ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
              if (cancelled)
                const Text('Anulat', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${_displayDate(e.eventDate)} · ${e.departments.join(', ')}'
                '${e.creatorName == null ? '' : ' · ${e.creatorName}'}',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          if (e.canCancel)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _saving ? null : () => _cancel(e),
                child: const Text('Anulează evenimentul', style: TextStyle(color: Colors.redAccent)),
              ),
            ),
        ],
      ),
    );
  }
}