// lib/screens/hours/add_hours_menu_screen.dart
import 'package:flutter/material.dart';

import 'manual_hours_screen.dart';

class AddHoursMenuScreen extends StatelessWidget {
  const AddHoursMenuScreen({super.key});

  void _show(BuildContext context, String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: const Text('Adaugă ore'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _OptionCard(
              icon: Icons.edit_calendar_outlined,
              title: 'Adaugă manual',
              subtitle: 'Completezi tu departamentul, evenimentul, data și orele',
              onTap: () async {
                final submitted = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(builder: (_) => const ManualHoursScreen()),
                );
                if (submitted == true && context.mounted) {
                  Navigator.of(context).pop(true);
                }
              },
            ),
            const SizedBox(height: 16),
            _OptionCard(
              icon: Icons.qr_code_2,
              title: 'Adaugă cu cod',
              subtitle: 'Introduci codul primit de la coordonator',
              // Placeholder until shared codes are built on the backend.
              onTap: () => _show(context, 'Adăugarea cu cod va fi disponibilă în curând.'),
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _OptionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1E1E1E),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Icon(icon, color: Colors.red, size: 36),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 13)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white38),
            ],
          ),
        ),
      ),
    );
  }
}