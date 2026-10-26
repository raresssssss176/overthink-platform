// lib/screens/shared/codes_tab.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/hours_api.dart';
import '../../services/ops_api.dart';
import '../../widgets/auth_widgets.dart';

String _isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _displayDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

String _hhmm(DateTime utc) {
  final d = utc.toLocal();
  return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

DateTime _today() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

class CodesTab extends StatefulWidget {
  const CodesTab({super.key});

  @override
  State<CodesTab> createState() => _CodesTabState();
}

class _CodesTabState extends State<CodesTab> {
  List<CreatorDepartment>? _departments;
  List<EventOption>? _events;
  List<TaskOption> _tasks = [];
  List<CodeItem>? _codes;
  String? _loadError;

  String? _departmentId;
  String? _eventId;
  String? _taskId;
  DateTime _date = _today();
  int _hours = 1;
  bool _creating = false;
  bool _loadingTasks = false;

  final _descriptionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  void _show(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _loadAll() async {
    setState(() => _loadError = null);
    final deps = await OpsApi.creatorDepartments();
    final events = await HoursApi.events();
    final codes = await OpsApi.myCodes();
    if (!mounted) return;
    setState(() {
      if (deps.isSuccess) {
        _departments = deps.value;
        if (_departments!.length == 1) _departmentId = _departments!.first.id;
      } else {
        _loadError = deps.message;
      }
      if (events.isSuccess) {
        _events = events.value;
      } else {
        _loadError ??= events.message;
      }
      if (codes.isSuccess) {
        _codes = codes.value;
      } else {
        _loadError ??= codes.message;
      }
    });
  }

  Future<void> _reloadCodes() async {
    final codes = await OpsApi.myCodes();
    if (!mounted) return;
    setState(() {
      if (codes.isSuccess) {
        _codes = codes.value;
      } else {
        _show(codes.message!);
      }
    });
  }

  Future<void> _onEventChanged(String? value) async {
    setState(() {
      _eventId = value;
      _taskId = null;
      _tasks = [];
    });
    if (value == null) return;
    setState(() => _loadingTasks = true);
    final result = await HoursApi.tasks(value);
    if (!mounted) return;
    setState(() {
      _loadingTasks = false;
      _tasks = result.isSuccess ? result.value! : [];
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2024),
      lastDate: _today(),
    );
    if (picked != null) {
      setState(() => _date = DateTime(picked.year, picked.month, picked.day));
    }
  }

  Future<void> _generate() async {
    if (_departmentId == null) {
      _show('Alege departamentul.');
      return;
    }
    if (_eventId == null) {
      _show('Alege evenimentul.');
      return;
    }
    setState(() => _creating = true);
    final description = _descriptionController.text.trim();
    final result = await OpsApi.createCode(
      departmentId: _departmentId!,
      eventId: _eventId!,
      taskId: _taskId,
      workDate: _isoDate(_date),
      hours: _hours,
      description: description.isEmpty ? null : description,
    );
    if (!mounted) return;
    setState(() => _creating = false);

    if (!result.isSuccess) {
      _show(result.message!);
      return;
    }
    _descriptionController.clear();
    await _showCode(result.value!);
    _reloadCodes();
  }

  Future<void> _showCode(CreatedCode code) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Cod generat', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${code.hours} ${code.hours == 1 ? 'oră' : 'ore'} · ${code.eventTitle} · ${code.departmentName}',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            Center(
              child: SelectableText(
                code.code,
                style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 1),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Valabil până la ${_hhmm(code.expiresAt)} (15 minute). '
                  'Poate fi folosit de mai mulți voluntari. Se afișează o singură dată.',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code.code));
              ScaffoldMessenger.of(dialogContext).showSnackBar(
                const SnackBar(content: Text('Codul a fost copiat.')),
              );
            },
            child: const Text('Copiază', style: TextStyle(color: Colors.redAccent)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Închide', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }

  Future<void> _cancel(CodeItem item) async {
    setState(() => _creating = true);
    final result = await OpsApi.cancelCode(item.id);
    if (!mounted) return;
    setState(() => _creating = false);
    _show(result.isSuccess ? 'Codul a fost anulat.' : result.message!);
    if (result.isSuccess) _reloadCodes();
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
    if (_departments == null || _events == null || _codes == null) {
      return const Center(child: CircularProgressIndicator(color: Colors.red));
    }

    return RefreshIndicator(
      color: Colors.red,
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _panel(
            title: 'Cod nou',
            children: [
              if (_departments!.isEmpty)
                const Text('Nu ai departamente pentru care să generezi coduri.',
                    style: TextStyle(color: Colors.white54))
              else
                DropdownButtonFormField<String>(
                  initialValue: _departmentId,
                  isExpanded: true,
                  dropdownColor: const Color(0xFF2A2A2A),
                  style: const TextStyle(color: Colors.white),
                  decoration: authInputDecoration('Departament'),
                  items: [
                    for (final d in _departments!) DropdownMenuItem(value: d.id, child: Text(d.name)),
                  ],
                  onChanged: (v) => setState(() => _departmentId = v),
                ),
              const SizedBox(height: 12),
              if (_events!.isEmpty)
                const Text('Nu există evenimente publicate.', style: TextStyle(color: Colors.white54))
              else
                DropdownButtonFormField<String>(
                  initialValue: _eventId,
                  isExpanded: true,
                  dropdownColor: const Color(0xFF2A2A2A),
                  style: const TextStyle(color: Colors.white),
                  decoration: authInputDecoration('Eveniment'),
                  items: [
                    for (final e in _events!) DropdownMenuItem(value: e.id, child: Text(e.title)),
                  ],
                  onChanged: _onEventChanged,
                ),
              const SizedBox(height: 12),
              if (_eventId != null)
                DropdownButtonFormField<String?>(
                  key: ValueKey('task-$_eventId'),
                  initialValue: _taskId,
                  isExpanded: true,
                  dropdownColor: const Color(0xFF2A2A2A),
                  style: const TextStyle(color: Colors.white),
                  decoration: authInputDecoration(_loadingTasks ? 'Se încarcă...' : 'Task (opțional)'),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Fără task')),
                    for (final t in _tasks) DropdownMenuItem<String?>(value: t.id, child: Text(t.name)),
                  ],
                  onChanged: (v) => setState(() => _taskId = v),
                ),
              if (_eventId != null) const SizedBox(height: 12),
              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(15),
                child: InputDecorator(
                  decoration: authInputDecoration('Data'),
                  child: Text(_displayDate(_date), style: const TextStyle(color: Colors.white)),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: _hours,
                isExpanded: true,
                dropdownColor: const Color(0xFF2A2A2A),
                style: const TextStyle(color: Colors.white),
                decoration: authInputDecoration('Nr. de ore'),
                items: [
                  for (var h = 1; h <= 12; h++)
                    DropdownMenuItem(value: h, child: Text('$h ${h == 1 ? 'oră' : 'ore'}')),
                ],
                onChanged: (v) => setState(() => _hours = v ?? _hours),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _descriptionController,
                maxLines: 2,
                style: const TextStyle(color: Colors.white),
                decoration: authInputDecoration('Mențiuni (opțional)'),
              ),
              const SizedBox(height: 16),
              AuthButton(
                label: 'Generează cod',
                loading: _creating,
                onPressed: _creating || _departments!.isEmpty ? null : _generate,
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('Codurile mele', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          if (_codes!.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Nu ai generat încă niciun cod.', style: TextStyle(color: Colors.white54)),
            )
          else
            for (final c in _codes!) _codeTile(c),
        ],
      ),
    );
  }

  Widget _panel({required String title, required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _codeTile(CodeItem c) {
    final (label, color) = switch (c.state) {
      'active' => ('Activ', Colors.green),
      'cancelled' => ('Anulat', Colors.redAccent),
      _ => ('Expirat', Colors.grey),
    };
    final task = c.taskName == null ? '' : ' · ${c.taskName}';
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
                child: Text('${c.eventTitle}$task',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${c.departmentName} · ${c.hours} h · ${c.workDate} · '
                '${c.redemptions} ${c.redemptions == 1 ? 'folosire' : 'folosiri'}'
                '${c.state == 'active' ? ' · expiră la ${_hhmm(c.expiresAt)}' : ''}',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          if (c.state == 'active')
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _creating ? null : () => _cancel(c),
                child: const Text('Anulează codul', style: TextStyle(color: Colors.redAccent)),
              ),
            ),
        ],
      ),
    );
  }
}