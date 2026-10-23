// lib/screens/home/home_placeholder_screen.dart
import 'package:flutter/material.dart';

/// Temporary screen shown after login. It is replaced by the real home
/// screen ("Adaugă ore", coordinator and admin screens) later.
class HomePlaceholderScreen extends StatelessWidget {
  final String accountStatus;

  const HomePlaceholderScreen({super.key, required this.accountStatus});

  @override
  Widget build(BuildContext context) {
    final text = accountStatus == 'pending'
        ? 'Contul tău așteaptă aprobarea unui administrator.'
        : 'Autentificare reușită.';

    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 16),
          ),
        ),
      ),
    );
  }
}
