// lib/screens/coordinator/all_volunteers_tab.dart
import 'package:flutter/material.dart';

import '../../services/joins_api.dart';
import '../../widgets/auth_widgets.dart';

class AllVolunteersTab extends StatefulWidget {
  const AllVolunteersTab({super.key});

  @override
  State<AllVolunteersTab> createState() => _AllVolunteersTabState();
}

class _AllVolunteersTabState extends State<AllVolunteersTab> {
  Overview? _overview;
  String? _error;
  bool _busy = false;
  final _searchController = TextEditingController();
  String _query = '';

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
    final result = await JoinsApi.overview();
    if (!mounted) return;
    setState(() {
      if (result.isSuccess) {
        _overview = result.value;
      } else {
        _error = result.message;
      }
    });
  }

  String _normalize(String s) => s
      .toLowerCase()
      .replaceAll('ă', 'a')
      .replaceAll('â', 'a')
      .replaceAll('î', 'i')
      .replaceAll('ș', 's')
      .replaceAll('ț', 't')
      .trim();

  List<VolunteerRow> _filtered() {
    final all = _overview!.volunteers;
    final q = _normalize(_query);
    if (q.isEmpty) return all;
    return all.where((v) {
      final name = _normalize('${v.lastName} ${v.firstName}');
      final reversed = _normalize('${v.firstName} ${v.lastName}');
      return name.contains(q) || reversed.contains(q);
    }).toList();
  }

  /// Picks one of the coordinator's departments, then sends the request.
  Future<void> _askToJoin(VolunteerRow v) async {
    final mine = _overview!.myDepartments;
    if (mine.isEmpty) {
      _show('Nu coordonezi niciun departament.');
      return;
    }
    String chosen = mine.first.id;
    final dept = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: Text('Cere adăugarea lui ${v.firstName}',
              style: const TextStyle(color: Colors.white)),
          content: DropdownButtonFormField<String>(
            initialValue: chosen,
            isExpanded: true,
            dropdownColor: const Color(0xFF2A2A2A),
            style: const TextStyle(color: Colors.white),
            decoration: authInputDecoration('Departament'),
            items: [
              for (final d in mine) DropdownMenuItem(value: d.id, child: Text(d.name)),
            ],
            onChanged: (value) => setDialogState(() => chosen = value ?? chosen),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Anulează', style: TextStyle(color: Colors.white70)),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(chosen),
              child: const Text('Trimite cererea', style: TextStyle(color: Colors.redAccent)),
            ),
          ],
        ),
      ),
    );
    if (dept == null) return;

    setState(() => _busy = true);
    final result = await JoinsApi.requestJoin(v.id, dept);
    if (!mounted) return;
    setState(() => _busy = false);
    _show(result.isSuccess ? 'Cererea a fost trimisă administratorului.' : result.message!);
    if (result.isSuccess) _load();
  }

  @override
  Widget build(BuildContext context) {
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
    if (_overview == null) {
      return const Center(child: CircularProgressIndicator(color: Colors.red));
    }

    final list = _filtered();
    return AbsorbPointer(
      absorbing: _busy,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white),
              onChanged: (value) => setState(() => _query = value),
              decoration: authInputDecoration('Caută după nume'),
            ),
          ),
          Expanded(
            child: list.isEmpty
                ? const Center(
              child: Text('Niciun voluntar nu corespunde căutării.',
                  style: TextStyle(color: Colors.white54)),
            )
                : RefreshIndicator(
              color: Colors.red,
              onRefresh: _load,
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                itemCount: list.length,
                itemBuilder: (context, index) => _tile(list[index]),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(VolunteerRow v) {
    final myDeptIds = _overview!.myDepartments.map((d) => d.id).toSet();
    final hasPending = v.pendingDepartmentIds.any(myDeptIds.contains);

    final String statusText;
    final Color statusColor;
    if (v.inMyDepartments) {
      statusText = 'În departamentul tău';
      statusColor = Colors.green;
    } else if (hasPending) {
      statusText = 'Cerere în așteptare';
      statusColor = Colors.orange;
    } else {
      statusText = '';
      statusColor = Colors.white54;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('${v.lastName} ${v.firstName}',
                    style: const TextStyle(color: Colors.white, fontSize: 16)),
              ),
              if (statusText.isNotEmpty)
                Text(statusText, style: TextStyle(color: statusColor, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            v.departments.isEmpty ? 'Fără departament' : v.departments.join(', '),
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          if (!v.inMyDepartments && !hasPending)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => _askToJoin(v),
                child: const Text('Cere adăugare', style: TextStyle(color: Colors.redAccent)),
              ),
            ),
        ],
      ),
    );
  }
}