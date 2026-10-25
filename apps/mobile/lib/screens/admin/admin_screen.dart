// lib/screens/admin/admin_screen.dart
import 'package:flutter/material.dart';

import '../../services/admin_api.dart';
import '../../widgets/auth_widgets.dart';
import 'member_detail_screen.dart';

class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
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
              Tab(text: 'Cereri'),
              Tab(text: 'Voluntari'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _RequestsTab(),
            _MembersTab(),
          ],
        ),
      ),
    );
  }
}

/// Opens the member detail page and reloads the list if something changed.
Future<void> _openDetail(BuildContext context, String userId, VoidCallback onChanged) async {
  final changed = await Navigator.of(context).push<bool>(
    MaterialPageRoute(builder: (_) => MemberDetailScreen(userId: userId)),
  );
  if (changed == true) onChanged();
}

/// Lowercase and without Romanian diacritics, so "ioană" matches "ioana".
String normalizeForSearch(String input) {
  return input
      .toLowerCase()
      .replaceAll('ă', 'a')
      .replaceAll('â', 'a')
      .replaceAll('î', 'i')
      .replaceAll('ș', 's')
      .replaceAll('ş', 's')
      .replaceAll('ț', 't')
      .replaceAll('ţ', 't')
      .trim();
}

// ---------- Cereri: only names until the user taps ----------

class _RequestsTab extends StatefulWidget {
  const _RequestsTab();

  @override
  State<_RequestsTab> createState() => _RequestsTabState();
}

class _RequestsTabState extends State<_RequestsTab> {
  List<PendingItem>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    final result = await AdminApi.fetchPendingItems();
    if (!mounted) return;
    setState(() {
      if (result.isSuccess) {
        _items = result.value;
      } else {
        _error = result.message;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return _ErrorView(message: _error!, onRetry: _load);
    }
    if (_items == null) {
      return const Center(child: CircularProgressIndicator(color: Colors.red));
    }
    if (_items!.isEmpty) {
      return const _EmptyView(text: 'Nu există cereri în așteptare.');
    }

    return RefreshIndicator(
      color: Colors.red,
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _items!.length,
        itemBuilder: (context, index) {
          final item = _items![index];
          return _NameTile(
            title: '${item.lastName} ${item.firstName}',
            trailing: item.overdue
                ? const Text('Întârziată', style: TextStyle(color: Colors.redAccent, fontSize: 12))
                : null,
            onTap: () => _openDetail(context, item.userId, _load),
          );
        },
      ),
    );
  }
}

// ---------- Voluntari: active members with search ----------

class _MembersTab extends StatefulWidget {
  const _MembersTab();

  @override
  State<_MembersTab> createState() => _MembersTabState();
}

class _MembersTabState extends State<_MembersTab> {
  List<MemberSummary>? _members;
  String? _error;
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

  Future<void> _load() async {
    setState(() => _error = null);
    final result = await AdminApi.fetchMembers();
    if (!mounted) return;
    setState(() {
      if (result.isSuccess) {
        _members = result.value;
      } else {
        _error = result.message;
      }
    });
  }

  /// Matches the typed text against first name and last name, in both orders.
  List<MemberSummary> _filtered() {
    final query = normalizeForSearch(_query);
    if (query.isEmpty) return _members!;
    return _members!.where((m) {
      final fullName = normalizeForSearch('${m.lastName} ${m.firstName}');
      final reversed = normalizeForSearch('${m.firstName} ${m.lastName}');
      return fullName.contains(query) || reversed.contains(query);
    }).toList();
  }

  String _roleLabel(MemberSummary m) {
    if (m.isAdmin) return 'Administrator';
    if (m.isCoordinator) return 'Coordonator';
    return 'Voluntar';
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return _ErrorView(message: _error!, onRetry: _load);
    }
    if (_members == null) {
      return const Center(child: CircularProgressIndicator(color: Colors.red));
    }

    final results = _filtered();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: TextField(
            controller: _searchController,
            style: const TextStyle(color: Colors.white),
            onChanged: (value) => setState(() => _query = value),
            decoration: InputDecoration(
              hintText: 'Caută după nume',
              hintStyle: const TextStyle(color: Colors.white38),
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
              filled: true,
              fillColor: Colors.black26,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: const BorderSide(color: Colors.red),
              ),
            ),
          ),
        ),
        Expanded(
          child: _members!.isEmpty
              ? const _EmptyView(text: 'Nu există voluntari activi.')
              : results.isEmpty
              ? const _EmptyView(text: 'Niciun voluntar nu corespunde căutării.')
              : RefreshIndicator(
            color: Colors.red,
            onRefresh: _load,
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              itemCount: results.length,
              itemBuilder: (context, index) {
                final m = results[index];
                final subtitle = m.coordinatedDepartments.isEmpty
                    ? _roleLabel(m)
                    : '${_roleLabel(m)} · ${m.coordinatedDepartments.join(', ')}';
                return _NameTile(
                  title: '${m.lastName} ${m.firstName}',
                  subtitle: subtitle,
                  onTap: () => _openDetail(context, m.id, _load),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

// ---------- shared small widgets ----------

class _NameTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback onTap;

  const _NameTile({required this.title, this.subtitle, this.trailing, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(color: Colors.white, fontSize: 16)),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(subtitle!, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right, color: Colors.white38),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
          TextButton(
            onPressed: onRetry,
            child: const Text('Încearcă din nou', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  final String text;

  const _EmptyView({required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54)),
      ),
    );
  }
}