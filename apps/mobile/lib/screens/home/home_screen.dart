// lib/screens/home/home_screen.dart
import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../widgets/auth_widgets.dart';
import '../admin/admin_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  CurrentUser? _user;
  String? _loadError;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    final result = await ApiService.getMe();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (result.isSuccess) {
        _user = result.value;
      } else {
        _loadError = result.message;
      }
    });
  }

  void _show(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _openSection(String title) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => _SectionScreen(title: title)),
    );
  }

  void _openAdmin() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AdminScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
      ),
      body: SafeArea(child: _buildBody()),
      bottomNavigationBar: _loading || _loadError != null ? null : _buildNavBar(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Colors.red));
    }
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_loadError!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _loadUser,
                child: const Text('Încearcă din nou', style: TextStyle(color: Colors.redAccent)),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        // Large club logo at the top of the screen.
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: OverthinkHero(widthFactor: 1.0),
        ),
        const SizedBox(height: 16),
        Text(
          'Salut, ${_user!.firstName}!',
          style: const TextStyle(color: Colors.white70, fontSize: 16),
        ),
        Expanded(
          child: Center(
            child: SizedBox(
              width: 240,
              height: 64,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
                ),
                // TODO: the hours form is built with the hours backend.
                onPressed: () => _show('Adăugarea orelor va fi disponibilă în curând.'),
                child: const Text(
                  'ADAUGĂ ORE',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNavBar() {
    final isAdmin = _user!.isAdmin;
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _NavItem(
            icon: Icons.history,
            label: 'Istoric',
            onTap: () => _openSection('Istoric'),
          ),
          _NavItem(
            icon: Icons.person_outline,
            label: 'Profil',
            onTap: () => _openSection('Profil'),
          ),
          _NavItem(
            icon: Icons.settings_outlined,
            label: 'Setări',
            onTap: () => _openSection('Setări'),
          ),
          // Visible only to administrators.
          if (isAdmin)
            _NavItem(
              icon: Icons.admin_panel_settings_outlined,
              label: 'Admin',
              onTap: _openAdmin,
            ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _NavItem({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
      ),
    );
  }
}

/// Temporary page for sections that are not built yet.
class _SectionScreen extends StatelessWidget {
  final String title;

  const _SectionScreen({required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: Text(title),
      ),
      body: const Center(
        child: Text('În lucru.', style: TextStyle(color: Colors.white54)),
      ),
    );
  }
}