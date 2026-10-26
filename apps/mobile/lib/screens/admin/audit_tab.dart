// lib/screens/admin/audit_tab.dart
import 'package:flutter/material.dart';

import '../../services/audit_api.dart';

/// Colour and label for each category of logged action.
class _CategoryStyle {
  final String label;
  final Color color;
  const _CategoryStyle(this.label, this.color);
}

const Map<String, _CategoryStyle> _categories = {
  'coordinator': _CategoryStyle('Coordonatori', Color(0xFFAB47BC)),
  'permission': _CategoryStyle('Permisiuni', Color(0xFFFFA726)),
  'hours': _CategoryStyle('Ore', Color(0xFF66BB6A)),
  'account': _CategoryStyle('Conturi', Color(0xFF42A5F5)),
  'other': _CategoryStyle('Altele', Color(0xFF9E9E9E)),
};

enum AuditSort {
  newest('Cele mai noi'),
  oldest('Cele mai vechi'),
  action('După acțiune'),
  actor('După cine a făcut');

  final String label;
  const AuditSort(this.label);
}

class AuditTab extends StatefulWidget {
  const AuditTab({super.key});

  @override
  State<AuditTab> createState() => _AuditTabState();
}

class _AuditTabState extends State<AuditTab> {
  List<AuditEntry>? _entries;
  String? _error;
  AuditSort _sort = AuditSort.newest;
  final Set<String> _selectedCategories = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    final result = await AuditApi.fetchLogs();
    if (!mounted) return;
    setState(() {
      if (result.isSuccess) {
        _entries = result.value;
      } else {
        _error = result.message;
      }
    });
  }

  List<AuditEntry> _visibleEntries() {
    final list = _entries!
        .where((e) => _selectedCategories.isEmpty || _selectedCategories.contains(e.category))
        .toList();
    switch (_sort) {
      case AuditSort.newest:
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case AuditSort.oldest:
        list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        break;
      case AuditSort.action:
        list.sort((a, b) => a.description.compareTo(b.description));
        break;
      case AuditSort.actor:
        list.sort((a, b) => (a.actorName ?? '').compareTo(b.actorName ?? ''));
        break;
    }
    return list;
  }

  String _formatDate(DateTime value) {
    final d = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)}.${d.year} ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
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
      );
    }
    if (_entries == null) {
      return const Center(child: CircularProgressIndicator(color: Colors.red));
    }

    final visible = _visibleEntries();

    return RefreshIndicator(
      color: Colors.red,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Sorting
          DropdownButtonFormField<AuditSort>(
            initialValue: _sort,
            isExpanded: true,
            dropdownColor: const Color(0xFF2A2A2A),
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Sortează',
              labelStyle: TextStyle(color: Colors.white54),
              filled: true,
              fillColor: Colors.black26,
            ),
            items: [
              for (final s in AuditSort.values) DropdownMenuItem(value: s, child: Text(s.label)),
            ],
            onChanged: (value) => setState(() => _sort = value ?? _sort),
          ),
          const SizedBox(height: 12),

          // Category filters
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in _categories.entries)
                FilterChip(
                  label: Text(entry.value.label),
                  selected: _selectedCategories.contains(entry.key),
                  selectedColor: entry.value.color.withValues(alpha: 0.35),
                  checkmarkColor: entry.value.color,
                  backgroundColor: Colors.black26,
                  labelStyle: const TextStyle(color: Colors.white70, fontSize: 12),
                  side: BorderSide(color: entry.value.color.withValues(alpha: 0.6)),
                  onSelected: (selected) => setState(() {
                    if (selected) {
                      _selectedCategories.add(entry.key);
                    } else {
                      _selectedCategories.remove(entry.key);
                    }
                  }),
                ),
            ],
          ),
          const SizedBox(height: 16),

          Text(
            '${visible.length} intrări',
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
          const SizedBox(height: 8),

          if (visible.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Nicio intrare nu corespunde filtrelor.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54),
              ),
            )
          else
            for (final e in visible) _LogCard(entry: e, dateText: _formatDate(e.createdAt)),
        ],
      ),
    );
  }
}

class _LogCard extends StatelessWidget {
  final AuditEntry entry;
  final String dateText;

  const _LogCard({required this.entry, required this.dateText});

  @override
  Widget build(BuildContext context) {
    final style = _categories[entry.category] ?? _categories['other']!;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: style.color, width: 4)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  entry.description,
                  style: TextStyle(color: style.color, fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
              Text(dateText, style: const TextStyle(color: Colors.white38, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'De: ${entry.actorName ?? 'sistem'}',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          if (entry.targetName != null)
            Text(
              'Pentru: ${entry.targetName}',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
        ],
      ),
    );
  }
}