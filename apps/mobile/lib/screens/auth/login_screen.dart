// lib/screens/auth/login_screen.dart
import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../widgets/auth_widgets.dart';
import '../home/home_screen.dart';
import 'register_screen.dart';
import 'verify_email_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _show(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _handleLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      _show('Completează emailul și parola.');
      return;
    }

    setState(() => _isLoading = true);
    final result = await ApiService.login(email, password);
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result.isSuccess) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
      return;
    }

    // The account exists but the e-mail code was never entered: send the user to verification.
    if (result.statusCode == 403 && result.detail == 'E-mail not verified') {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => VerifyEmailScreen(email: email)),
      );
      return;
    }

    _show(result.message!);
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
              const SizedBox(height: 8),
              const OverthinkHero(),
              const SizedBox(height: 32),
              AuthCard(
                title: 'Autentificare',
                children: [
                  AuthTextField(
                    label: 'Email',
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                  ),
                  AuthTextField(
                    label: 'Parola',
                    controller: _passwordController,
                    obscure: true,
                  ),
                  const SizedBox(height: 14),
                  AuthButton(
                    label: 'Intră în cont',
                    loading: _isLoading,
                    onPressed: _handleLogin,
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const RegisterScreen()),
                      ),
                      child: const Text(
                        'Nu ai cont? Înregistrează-te',
                        style: TextStyle(color: Colors.redAccent),
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
