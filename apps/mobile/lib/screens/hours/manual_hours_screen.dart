// lib/screens/hours/manual_hours_screen.dart
import 'package:flutter/material.dart';

import '../../services/api_service.dart' show ApiResult;
import '../../services/hours_api.dart';
import '../../widgets/auth_widgets.dart';

const String _newTaskValue = '__new_task__';
const String _otherEventValue = '__other_event__';

class ManualHoursScreen extends StatefulWidget {
  const ManualHoursScreen({super.key});

  @override
  State<ManualHoursScreen> createState() => _ManualHoursScreenState();
}

class _ManualHoursScreenState extends State<ManualHoursScreen> {
  List<DepartmentOption>? _departments;
  List<EventOption>? _events;
  List<TaskOption> _tasks = [];
  String? _loadError;

  String? _departmentId;
  String? _eventChoice; // event id, _otherEventValue, or null
  String? _taskChoice; // task id, _newTaskValue, or null (no task)
  DateTime _date = _today();
  int _hours = 1;
  bool _loadingTasks = false;
  bool _saving = false;

  final _eventTitleController = TextEditingController();
  final _newTaskController = TextEditingController();
  final _mentionsController = TextEditingController();

  static DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  @override
  void initState() {
    super.initState();
    _loadBase();
  }

  @override
  void dispose() {
    _eventTitleController.dispose();
    _newTaskController.dispose();
    _mentionsController.dispose();
    super.dispose();
  }

  void _show(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _loadBase() async {
    setState(() => _loadError = null);
    final ApiResult<List<DepartmentOption>> deps = await HoursApi.myDepartments();
    final ApiResult<List<EventOption>> events = await HoursApi.events();
    if (!mounted) return;
    setState(() {
      if (deps.isSuccess && events.isSuccess) {
        _departments = deps.value;
        _events = events.value;
        if (_departments!.length == 1) {
          _departmentId = _departments!.first.id;
        }
      } else {
        _loadError = deps.message ?? events.message;
      }
    });
  }

  Future<void> _loadTasks(String eventId) async {
    setState(() => _loadingTasks = true);
    final result = await HoursApi.tasks(eventId);
    if (!mounted) return;
    setState(() {
      _loadingTasks = false;
      _tasks = result.isSuccess ? result.value! : [];
    });
    if (!result.isSuccess) {
      _show(result.message!);
    }
  }

  void _onEventChanged(String? value) {
    setState(() {
      _eventChoice = value;
      _tasks = [];
      _taskChoice = null;
    });
    if (value != null && value != _otherEventValue) {
      _loadTasks(value);
    }
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

  static String _isoDate(DateTime d) {
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  static String _displayDate(DateTime d) {
    return '${d.day.toString().padLeft(2, '0')}.'
        '${d.month.toString().padLeft(2, '0')}.${d.year}';
  }

  Future<void> _submit() async {
    if (_departmentId == null) {
      _show('Alege departamentul.');
      return;
    }
    if (_eventChoice == null) {
      _show('Alege evenimentul.');
      return;
    }
    final isOtherEvent = _eventChoice == _otherEventValue;
    final eventTitle = _eventTitleController.text.trim();
    if (isOtherEvent && eventTitle.length < 2) {
      _show('Scrie numele evenimentului (minim 2 caractere).');
      return;
    }
    final isNewTask = _taskChoice == _newTaskValue;
    final newTaskName = _newTaskController.text.trim();
    if (isNewTask && newTaskName.length < 2) {
      _show('Scrie numele task-ului (minim 2 caractere).');
      return;
    }

    setState(() => _saving = true);
    final mentions = _mentionsController.text.trim();
    final result = await HoursApi.submitManual(
      departmentId: _departmentId!,
      eventId: isOtherEvent ? null : _eventChoice,
      newEventTitle: isOtherEvent ? eventTitle : null,
      taskId: (_taskChoice != null && !isNewTask) ? _taskChoice : null,
      newTaskName: isNewTask ? newTaskName : null,
      workDate: _isoDate(_date),
      hours: _hours,
      mentions: mentions.isEmpty ? null : mentions,
    );
    if (!mounted) return;
    setState(() => _saving = false);

    if (result.isSuccess) {
      _show('Orele au fost trimise spre aprobare.');
      Navigator.of(context).pop(true);
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
        title: const Text('Adaugă manual'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loadError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_loadError!, style: const TextStyle(color: Colors.white70)),
            TextButton(
              onPressed: _loadBase,
              child: const Text('Încearcă din nou', style: TextStyle(color: Colors.redAccent)),
            ),
          ],
        ),
      );
    }
    if (_departments == null || _events == null) {
      return const Center(child: CircularProgressIndicator(color: Colors.red));
    }

    final noEvents = _events!.isEmpty;
    final isOtherEvent = _eventChoice == _otherEventValue;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Department
        if (_departments!.isEmpty)
          const _Notice(text: 'Nu ești înscris în niciun departament. Cere unui coordonator să te adauge.')
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
            onChanged: (value) => setState(() => _departmentId = value),
          ),
        const SizedBox(height: 16),

        // Event: the published events, plus "Altul" which is always available.
        if (noEvents) ...[
          const _Notice(
            text: 'Nu există evenimente publicate. Alege „Altul” și scrie numele evenimentului.',
          ),
          const SizedBox(height: 12),
        ],
        DropdownButtonFormField<String>(
          initialValue: _eventChoice,
          isExpanded: true,
          dropdownColor: const Color(0xFF2A2A2A),
          style: const TextStyle(color: Colors.white),
          decoration: authInputDecoration('Eveniment'),
          items: [
            for (final e in _events!) DropdownMenuItem(value: e.id, child: Text(e.title)),
            const DropdownMenuItem(value: _otherEventValue, child: Text('Altul')),
          ],
          onChanged: _onEventChanged,
        ),
        const SizedBox(height: 16),

        // Typed event name, only for "Altul"
        if (isOtherEvent) ...[
          AuthTextField(label: 'Numele evenimentului', controller: _eventTitleController),
        ],

        // Task (for a listed event, or a typed one)
        if (_eventChoice != null) ...[
          DropdownButtonFormField<String?>(
            key: ValueKey('task-$_eventChoice'),
            initialValue: _taskChoice,
            isExpanded: true,
            dropdownColor: const Color(0xFF2A2A2A),
            style: const TextStyle(color: Colors.white),
            decoration: authInputDecoration(_loadingTasks ? 'Se încarcă task-urile...' : 'Task'),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Fără task')),
              if (!isOtherEvent)
                for (final t in _tasks) DropdownMenuItem<String?>(value: t.id, child: Text(t.name)),
              const DropdownMenuItem<String?>(value: _newTaskValue, child: Text('+ Scrie un task nou')),
            ],
            onChanged: _loadingTasks ? null : (value) => setState(() => _taskChoice = value),
          ),
          const SizedBox(height: 16),
        ],

        if (_taskChoice == _newTaskValue) ...[
          AuthTextField(label: 'Numele task-ului', controller: _newTaskController),
        ],

        // Date
        InkWell(
          onTap: _pickDate,
          borderRadius: BorderRadius.circular(15),
          child: InputDecorator(
            decoration: authInputDecoration('Data'),
            child: Text(_displayDate(_date), style: const TextStyle(color: Colors.white)),
          ),
        ),
        const SizedBox(height: 16),

        // Hours (whole hours only)
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
          onChanged: (value) => setState(() => _hours = value ?? _hours),
        ),
        const SizedBox(height: 16),

        // Mentions (optional)
        TextField(
          controller: _mentionsController,
          maxLines: 3,
          style: const TextStyle(color: Colors.white),
          decoration: authInputDecoration('Mențiuni (opțional)'),
        ),
        const SizedBox(height: 24),

        AuthButton(
          label: 'Trimite',
          loading: _saving,
          onPressed: _saving ? null : _submit,
        ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  final String text;

  const _Notice({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Text(text, style: const TextStyle(color: Colors.white54)),
    );
  }
}