// lib/screens/auth/verify_email_screen.dart
import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../widgets/auth_widgets.dart';
import 'login_screen.dart';

class VerifyEmailScreen extends StatefulWidget {
  final String email;

  const VerifyEmailScreen({super.key, required this.email});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  final _codeController = TextEditingController();
  bool _isLoading = false;
  bool _isResending = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  void _show(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _handleVerify() async {
    final code = _codeController.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      _show('Introdu codul de 6 cifre din email.');
      return;
    }

    setState(() => _isLoading = true);
    final result = await ApiService.verifyEmail(widget.email, code);
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result.isSuccess) {
      _show('Email verificat cu succes! Așteaptă aprobarea unui administrator.');
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    } else {
      _show(result.message!);
    }
  }

  Future<void> _handleResend() async {
    setState(() => _isResending = true);
    final result = await ApiService.resendVerification(widget.email);
    if (!mounted) return;
    setState(() => _isResending = false);

    if (result.isSuccess) {
      _show('Dacă adresa există, vei primi un cod nou pe email.');
    } else {
      _show(result.message!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 40),
              const OverthinkLogo(),
              const SizedBox(height: 60),
              AuthCard(
                title: 'Verificare email',
                children: [
                  Text(
                    'Am trimis un cod pe adresa\n${widget.email}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _codeController,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 24, letterSpacing: 8),
                    decoration: authInputDecoration('Cod', hint: '000000'),
                  ),
                  const SizedBox(height: 24),
                  AuthButton(
                    label: 'Verifică contul',
                    loading: _isLoading,
                    onPressed: _handleVerify,
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton(
                      onPressed: _isResending ? null : _handleResend,
                      child: Text(
                        _isResending ? 'Se trimite...' : 'Nu ai primit codul? Trimite din nou',
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
