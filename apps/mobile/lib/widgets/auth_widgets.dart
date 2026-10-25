// lib/widgets/auth_widgets.dart
import 'package:flutter/material.dart';

InputDecoration authInputDecoration(String label, {String? hint}) {
  return InputDecoration(
    labelText: label,
    hintText: hint,
    hintStyle: const TextStyle(color: Colors.white24),
    labelStyle: const TextStyle(color: Colors.white54),
    filled: true,
    fillColor: Colors.black26,
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(15),
      borderSide: const BorderSide(color: Colors.transparent),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(15),
      borderSide: const BorderSide(color: Colors.red),
    ),
  );
}

/// The club logo from assets/images/logo.png (white letters, transparent background).
class OverthinkLogo extends StatelessWidget {
  final double height;

  const OverthinkLogo({super.key, this.height = 48});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/logo.png',
      height: height,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) => const Text(
        'OVERTHINK',
        style: TextStyle(color: Colors.red, fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 2),
      ),
    );
  }
}

class AuthCard extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const AuthCard({super.key, required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          ...children,
        ],
      ),
    );
  }
}

class AuthTextField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool obscure;
  final bool readOnly;
  final VoidCallback? onTap;
  final TextInputType? keyboardType;
  final String? hint;

  const AuthTextField({
    super.key,
    required this.label,
    required this.controller,
    this.obscure = false,
    this.readOnly = false,
    this.onTap,
    this.keyboardType,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        readOnly: readOnly,
        onTap: onTap,
        keyboardType: keyboardType,
        style: const TextStyle(color: Colors.white),
        decoration: authInputDecoration(label, hint: hint),
      ),
    );
  }
}

class AuthButton extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback? onPressed;

  const AuthButton({super.key, required this.label, this.loading = false, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.red,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        ),
        onPressed: loading ? null : onPressed,
        child: loading
            ? const CircularProgressIndicator(color: Colors.white)
            : Text(label, style: const TextStyle(fontSize: 18, color: Colors.white)),
      ),
    );
  }
}
/// Large logo that fills the width of the screen, used as the header of the auth screens.
class OverthinkHero extends StatelessWidget {
  final double widthFactor;

  const OverthinkHero({super.key, this.widthFactor = 1.0});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Image.asset(
          'assets/images/logo.png',
          width: constraints.maxWidth * widthFactor,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => const Text(
            'OVERTHINK',
            style: TextStyle(color: Colors.red, fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 2),
          ),
        );
      },
    );
  }
}