// lib/screens/coordinator/coordinator_screen.dart
import 'package:flutter/material.dart';

import '../../services/admin_api.dart' show MemberDetails, MemberSummary, formatHours;
import '../../services/ops_api.dart';
import '../../widgets/auth_widgets.dart';
import '../shared/codes_tab.dart';
import '../shared/review_tab.dart';
import '../shared/events_tab.dart';

const Map<String, String> permissionLabels = {
  'calendar.create': 'Creează evenimente în calendar',
  'attendance.mark': 'Pune absențe la evenimente',
};

class CoordinatorScreen extends StatelessWidget {
  const CoordinatorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          elevation: 0,
          centerTitle: true,
          title: const OverthinkLogo(height: 28),
          bottom: const TabBar(
            indicatorColor: Colors.red,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white54,
            tabs: [
              Tab(text: 'Echipa'),
              Tab(text: 'Ore'),
              Tab(text: 'Coduri'),
              Tab(text: 'Evenimente'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _TeamTab(),
            ReviewTab(),
            CodesTab(),
            EventsTab(),
          ],
        ),
      ),
    );
  }
}

class _TeamTab extends StatefulWidget {
  const _TeamTab();

  @override
  State<_TeamTab> createState() => _TeamTabState();
}

class _TeamTabState extends State<_TeamTab> {
  List<MemberSummary>? _team;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    final result = await OpsApi.myTeam();
    if (!mounted) return;
    setState(() {
      if (result.isSuccess) {
        _team = result.value;
      } else {
        _error = result.message;
      }
    });
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
    if (_team == null) {
      return const Center(child: CircularProgressIndicator(color: Colors.red));
    }
    if (_team!.isEmpty) {
      return const Center(
        child: Text('Echipa ta este goală.', style: TextStyle(color: Colors.white54)),
      );
    }

    return RefreshIndicator(
      color: Colors.red,
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _team!.length,
        itemBuilder: (context, index) {
          final m = _team![index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Material(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => CoordinatorMemberScreen(userId: m.id)),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('${m.lastName} ${m.firstName}',
                            style: const TextStyle(color: Colors.white, fontSize: 16)),
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

/// Volunteer page for a coordinator: hours totals and permissions.
/// Hours are approved in the "Ore" tab.
class CoordinatorMemberScreen extends StatefulWidget {
  final String userId;

  const CoordinatorMemberScreen({super.key, required this.userId});

  @override
  State<CoordinatorMemberScreen> createState() => _CoordinatorMemberScreenState();
}

class _CoordinatorMemberScreenState extends State<CoordinatorMemberScreen> {
  MemberDetails? _details;
  List<GrantItem>? _grants;
  String? _error;
  bool _busy = false;

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
    final details = await OpsApi.memberDetails(widget.userId);
    final grants = await OpsApi.memberGrants(widget.userId);
    if (!mounted) return;
    setState(() {
      if (details.isSuccess && grants.isSuccess) {
        _details = details.value;
        _grants = grants.value;
      } else {
        _error = details.message ?? grants.message;
      }
    });
  }

  Future<void> _grant() async {
    String selected = permissionLabels.keys.first;
    final chosen = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: const Text('Acordă permisiune', style: TextStyle(color: Colors.white)),
          content: DropdownButtonFormField<String>(
            initialValue: selected,
            isExpanded: true,
            dropdownColor: const Color(0xFF2A2A2A),
            style: const TextStyle(color: Colors.white),
            decoration: authInputDecoration('Permisiune'),
            items: [
              for (final e in permissionLabels.entries)
                DropdownMenuItem(value: e.key, child: Text(e.value)),
            ],
            onChanged: (v) => setDialogState(() => selected = v ?? selected),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Anulează', style: TextStyle(color: Colors.white70)),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(selected),
              child: const Text('Acordă (48 h)', style: TextStyle(color: Colors.redAccent)),
            ),
          ],
        ),
      ),
    );
    if (chosen == null) return;

    setState(() => _busy = true);
    final result = await OpsApi.grantPermission(widget.userId, chosen);
    if (!mounted) return;
    setState(() => _busy = false);
    _show(result.isSuccess ? 'Permisiunea a fost acordată.' : result.message!);
    if (result.isSuccess) _load();
  }

  Future<void> _revoke(GrantItem g) async {
    setState(() => _busy = true);
    final result = await OpsApi.revokeGrant(g.id);
    if (!mounted) return;
    setState(() => _busy = false);
    _show(result.isSuccess ? 'Permisiunea a fost revocată.' : result.message!);
    if (result.isSuccess) _load();
  }

  @override
  Widget build(BuildContext context) {
    final d = _details;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: Text(d == null ? 'Voluntar' : '${d.lastName} ${d.firstName}'),
      ),
      body: _error != null
          ? Center(child: Text(_error!, style: const TextStyle(color: Colors.white70)))
          : d == null
          ? const Center(child: CircularProgressIndicator(color: Colors.red))
          : AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _panel(
              title: 'Ore',
              children: [
                _hoursRow('Aprobate', formatHours(d.hours.approvedMinutes), Colors.green),
                _hoursRow('În așteptare', formatHours(d.hours.pendingMinutes), Colors.orange),
                _hoursRow('Respinse', formatHours(d.hours.rejectedMinutes), Colors.redAccent),
                const SizedBox(height: 8),
                const Text(
                  'Orele în așteptare se aprobă din tab-ul Ore.',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _panel(
              title: 'Permisiuni',
              children: [
                if (_grants == null || _grants!.isEmpty)
                  const Text('Nu are permisiuni active.', style: TextStyle(color: Colors.white54))
                else
                  for (final g in _grants!)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(permissionLabels[g.permission] ?? g.permission,
                                    style: const TextStyle(color: Colors.white)),
                                Text(
                                  'Expiră: ${g.expiresAt.toLocal().day.toString().padLeft(2, '0')}.'
                                      '${g.expiresAt.toLocal().month.toString().padLeft(2, '0')} '
                                      '${g.expiresAt.toLocal().hour.toString().padLeft(2, '0')}:'
                                      '${g.expiresAt.toLocal().minute.toString().padLeft(2, '0')}',
                                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: () => _revoke(g),
                            child: const Text('Revocă', style: TextStyle(color: Colors.redAccent)),
                          ),
                        ],
                      ),
                    ),
                const SizedBox(height: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  onPressed: _grant,
                  child: const Text('Acordă permisiune', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ],
        ),
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

  Widget _hoursRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(color: Colors.white70))),
          Text('$value h', style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16)),
        ],
      ),
    );
  }
}