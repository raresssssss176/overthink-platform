// lib/screens/shared/review_tab.dart
import 'package:flutter/material.dart';

import '../../services/ops_api.dart';
import '../../widgets/auth_widgets.dart';

class ReviewTab extends StatefulWidget {
  const ReviewTab({super.key});

  @override
  State<ReviewTab> createState() => _ReviewTabState();
}

class _ReviewTabState extends State<ReviewTab> {
  List<ReviewEntry>? _items;
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
    final result = await OpsApi.reviewQueue();
    if (!mounted) return;
    setState(() {
      if (result.isSuccess) {
        _items = result.value;
      } else {
        _error = result.message;
      }
    });
  }

  Future<void> _approve(ReviewEntry e) async {
    setState(() => _busy = true);
    final result = await OpsApi.approve(e.id);
    if (!mounted) return;
    setState(() => _busy = false);
    _show(result.isSuccess ? 'Orele au fost aprobate.' : result.message!);
    if (result.isSuccess) _load();
  }

  Future<void> _reject(ReviewEntry e) async {
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
          decoration: authInputDecoration('Motiv (minim 3 caractere)'),
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
    if (reason == null || reason.isEmpty) return;
    if (reason.length < 3) {
      _show('Motivul trebuie să aibă cel puțin 3 caractere.');
      return;
    }

    setState(() => _busy = true);
    final result = await OpsApi.reject(e.id, reason);
    if (!mounted) return;
    setState(() => _busy = false);
    _show(result.isSuccess ? 'Orele au fost respinse.' : result.message!);
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
        child: Text('Nu există ore în așteptare.', style: TextStyle(color: Colors.white54)),
      );
    }

    return RefreshIndicator(
      color: Colors.red,
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _items!.length,
        itemBuilder: (context, index) {
          final e = _items![index];
          final task = e.taskName == null ? '' : ' · ${e.taskName}';
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
                Text(e.memberName ?? '-',
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('${e.eventTitle}$task',
                    style: const TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 2),
                Text(
                  '${e.workDate} · ${e.hours} h · ${e.departmentName ?? '-'}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                if (e.description.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(e.description, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                        onPressed: _busy ? null : () => _approve(e),
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
                        onPressed: _busy ? null : () => _reject(e),
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
    );
  }
}