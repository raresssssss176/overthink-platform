// lib/screens/admin/member_detail_screen.dart
import 'package:flutter/material.dart';

import '../../services/admin_api.dart';
import '../../services/api_service.dart';

class MemberDetailScreen extends StatefulWidget {
  final String userId;

  const MemberDetailScreen({super.key, required this.userId});

  @override
  State<MemberDetailScreen> createState() => _MemberDetailScreenState();
}

class _MemberDetailScreenState extends State<MemberDetailScreen> {
  MemberDetails? _details;
  List<Department> _allDepartments = [];
  String? _error;
  String? _selectedDepartmentId;
  bool _busy = false;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _show(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _load() async {
    setState(() => _error = null);
    final result = await AdminApi.fetchMemberDetails(widget.userId);
    final departments = await ApiService.fetchDepartments();
    if (!mounted) return;
    setState(() {
      if (departments.isSuccess) {
        _allDepartments = departments.value!;
      }
      if (result.isSuccess) {
        _details = result.value;
        final options = _promotionOptions;
        _selectedDepartmentId = options.isNotEmpty ? options.first.id : null;
      } else {
        _error = result.message;
      }
    });
  }

  /// Admins can be promoted on any department. Volunteers only on their own departments.
  List<DepartmentRef> get _promotionOptions {
    final d = _details;
    if (d == null) return const [];
    if (d.isAdmin) {
      return _allDepartments.map((x) => DepartmentRef(id: x.id, name: x.name)).toList();
    }
    return d.departments;
  }

  /// Runs one action, shows the result, then reloads or closes the page.
  Future<void> _perform(
      Future<ApiResult<bool>> Function() action,
      String successMessage, {
        bool closeScreen = false,
      }) async {
    setState(() => _busy = true);
    final result = await action();
    if (!mounted) return;
    setState(() => _busy = false);

    if (!result.isSuccess) {
      _show(result.message!);
      return;
    }
    _show(successMessage);
    _changed = true;
    if (closeScreen) {
      Navigator.of(context).pop(true);
    } else {
      await _load();
    }
  }

  Future<String?> _askRejectReason() async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Motivul respingerii', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          maxLines: 3,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'Motiv (minim 3 caractere)',
            labelStyle: TextStyle(color: Colors.white54),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Anulează', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Respinge', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    controller.dispose();
    return reason;
  }

  Future<void> _rejectRequest(String requestId) async {
    final reason = await _askRejectReason();
    if (reason == null || reason.isEmpty) return;
    if (reason.length < 3) {
      _show('Motivul trebuie să aibă cel puțin 3 caractere.');
      return;
    }
    await _perform(
          () => ApiService.rejectRequest(requestId, reason),
      'Cererea a fost respinsă.',
      closeScreen: true,
    );
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Ștergi contul?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Contul și datele lui de autentificare vor fi șterse. Această acțiune nu poate fi anulată.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Anulează', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Șterge', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _perform(
          () => AdminApi.deleteMember(widget.userId),
      'Contul a fost șters.',
      closeScreen: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final details = _details;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: Text(details == null ? 'Detalii' : '${details.lastName} ${details.firstName}'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(_changed),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.white70)),
            TextButton(
              onPressed: _load,
              child: const Text('Încearcă din nou', style: TextStyle(color: Colors.redAccent)),
            ),
          ],
        ),
      );
    }
    final d = _details;
    if (d == null) {
      return const Center(child: CircularProgressIndicator(color: Colors.red));
    }

    return AbsorbPointer(
      absorbing: _busy,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _card(
            title: 'Date personale',
            children: [
              _InfoRow(label: 'Email', value: d.email),
              _InfoRow(label: 'Telefon', value: d.phone),
              _InfoRow(label: 'Acronim', value: d.acronym),
              _InfoRow(label: 'Data nașterii', value: d.birthDate),
              _InfoRow(label: 'Liceul', value: d.school),
              _InfoRow(label: 'Localitatea', value: d.locality),
              _InfoRow(label: 'Sex', value: d.gender),
              _InfoRow(label: 'Stare cont', value: _statusLabel(d)),
            ],
          ),
          const SizedBox(height: 12),
          _card(
            title: 'Departamente',
            children: [
              if (d.departments.isEmpty)
                const Text('-', style: TextStyle(color: Colors.white54))
              else
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final dept in d.departments)
                      Chip(
                        label: Text(dept.name),
                        backgroundColor: Colors.black26,
                        labelStyle: const TextStyle(color: Colors.white, fontSize: 12),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 12),
          _card(
            title: 'Ore',
            children: [
              _HoursRow(label: 'Aprobate', minutes: d.hours.approvedMinutes, color: Colors.green),
              _HoursRow(label: 'În așteptare', minutes: d.hours.pendingMinutes, color: Colors.orange),
              _HoursRow(label: 'Respinse', minutes: d.hours.rejectedMinutes, color: Colors.redAccent),
            ],
          ),
          const SizedBox(height: 20),
          ..._actions(d),
        ],
      ),
    );
  }

  String _statusLabel(MemberDetails d) {
    if (d.isAdmin) {
      return d.isCoordinator ? 'Administrator, coordonator' : 'Administrator';
    }
    switch (d.accountStatus) {
      case 'active':
        return d.isCoordinator ? 'Coordonator' : 'Voluntar activ';
      case 'pending':
        return 'În așteptarea aprobării';
      case 'rejected':
        return 'Respins';
      case 'email_unverified':
        return 'Email neverificat';
      default:
        return d.accountStatus;
    }
  }

  List<Widget> _actions(MemberDetails d) {
    final widgets = <Widget>[];

    // Pending registration: approve or reject.
    if (d.canDecideRequest) {
      widgets.add(Row(
        children: [
          Expanded(
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              onPressed: _busy
                  ? null
                  : () => _perform(
                    () => ApiService.approveRequest(d.membershipRequestId!),
                'Cererea a fost aprobată.',
                closeScreen: true,
              ),
              child: const Text('Aprobă', style: TextStyle(color: Colors.white)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.redAccent,
                side: const BorderSide(color: Colors.redAccent),
              ),
              onPressed: _busy ? null : () => _rejectRequest(d.membershipRequestId!),
              child: const Text('Respinge'),
            ),
          ),
        ],
      ));
      widgets.add(const SizedBox(height: 12));
    }

    // Active member (volunteer or administrator) who is not a coordinator yet: promote.
    if (d.isActive && !d.isCoordinator) {
      final options = _promotionOptions;
      widgets.add(_card(
        title: 'Promovare la coordonator',
        children: [
          if (options.isEmpty)
            const Text(
              'Nu există departamente disponibile.',
              style: TextStyle(color: Colors.white54),
            )
          else ...[
            DropdownButtonFormField<String>(
              initialValue: _selectedDepartmentId,
              isExpanded: true,
              dropdownColor: const Color(0xFF2A2A2A),
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Departament',
                labelStyle: TextStyle(color: Colors.white54),
                filled: true,
                fillColor: Colors.black26,
              ),
              items: [
                for (final dept in options)
                  DropdownMenuItem(value: dept.id, child: Text(dept.name)),
              ],
              onChanged: (value) => setState(() => _selectedDepartmentId = value),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: _busy || _selectedDepartmentId == null
                  ? null
                  : () => _perform(
                    () => AdminApi.promote(d.id, _selectedDepartmentId!),
                'Membrul a fost promovat la coordonator.',
              ),
              child: const Text('Promovează', style: TextStyle(color: Colors.white)),
            ),
          ],
        ],
      ));
      widgets.add(const SizedBox(height: 12));
    }

    // Coordinator (volunteer or administrator): demote.
    if (d.isActive && d.isCoordinator) {
      widgets.add(OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.orangeAccent,
          side: const BorderSide(color: Colors.orangeAccent),
        ),
        onPressed: _busy
            ? null
            : () => _perform(
              () => AdminApi.demote(d.id),
          'Coordonatorul a fost demotat la voluntar.',
        ),
        child: const Text('Demotează la voluntar'),
      ));
      widgets.add(const SizedBox(height: 12));
    }

    // Anyone except administrators can be deleted.
    if (!d.isAdmin) {
      widgets.add(OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.redAccent,
          side: const BorderSide(color: Colors.redAccent),
        ),
        onPressed: _busy ? null : _confirmDelete,
        child: const Text('Șterge contul'),
      ));
    } else {
      widgets.add(const Text(
        'Conturile de administrator nu pot fi șterse de aici.',
        style: TextStyle(color: Colors.white54),
        textAlign: TextAlign.center,
      ));
    }

    return widgets;
  }

  Widget _card({required String title, required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String? value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13)),
          ),
          Expanded(
            child: Text(
              value == null || value!.isEmpty ? '-' : value!,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _HoursRow extends StatelessWidget {
  final String label;
  final int minutes;
  final Color color;

  const _HoursRow({required this.label, required this.minutes, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(color: Colors.white70))),
          Text(
            '${formatHours(minutes)} h',
            style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ],
      ),
    );
  }
}