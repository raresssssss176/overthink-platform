// lib/screens/admin/join_requests_tab.dart
import 'package:flutter/material.dart';

import '../../services/joins_api.dart';
import '../../widgets/auth_widgets.dart';

class JoinRequestsTab extends StatefulWidget {
  const JoinRequestsTab({super.key});

  @override
  State<JoinRequestsTab> createState() => _JoinRequestsTabState();
}

class _JoinRequestsTabState extends State<JoinRequestsTab> {
  List<JoinRequestItem>? _items;
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
    final result = await JoinsApi.pending();
    if (!mounted) return;
    setState(() {
      if (result.isSuccess) {
        _items = result.value;
      } else {
        _error = result.message;
      }
    });
  }

  Future<void> _approve(JoinRequestItem r) async {
    setState(() => _busy = true);
    final result = await JoinsApi.approve(r.id);
    if (!mounted) return;
    setState(() => _busy = false);
    _show(result.isSuccess ? 'Voluntarul a fost adăugat în departament.' : result.message!);
    if (result.isSuccess) _load();
  }

  Future<void> _reject(JoinRequestItem r) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Motivul respingerii', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          maxLines: 2,
          style: const TextStyle(color: Colors.white),
          decoration: authInputDecoration('Motiv (opțional)'),
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
    if (reason == null) return;

    setState(() => _busy = true);
    final result = await JoinsApi.reject(r.id, reason);
    if (!mounted) return;
    setState(() => _busy = false);
    _show(result.isSuccess ? 'Cererea a fost respinsă.' : result.message!);
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
    if (_items == null) {
      return const Center(child: CircularProgressIndicator(color: Colors.red));
    }
    if (_items!.isEmpty) {
      return const Center(
        child: Text('Nu există cereri de adăugare în departamente.',
            style: TextStyle(color: Colors.white54)),
      );
    }

    return AbsorbPointer(
      absorbing: _busy,
      child: RefreshIndicator(
        color: Colors.red,
        onRefresh: _load,
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: _items!.length,
          itemBuilder: (context, index) {
            final r = _items![index];
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.userName,
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('Departament: ${r.departmentName}',
                      style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  Text('Cerută de: ${r.requestedByName}',
                      style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                          onPressed: () => _approve(r),
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
                          onPressed: () => _reject(r),
                          child: const Text('Respinge'),
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
    );
  }
}