// lib/screens/auth/register_screen.dart
import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import 'verify_email_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({Key? key}) : super(key: key);

  @override
  _RegisterScreenState createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  bool _acceptedTerms = false;
  bool _isLoading = false;

  final _numeController = TextEditingController();
  final _prenumeController = TextEditingController();
  final _emailController = TextEditingController();
  final _dataNasteriiController = TextEditingController();
  final _liceulController = TextEditingController();
  final _localitateaController = TextEditingController();
  final _parolaController = TextEditingController();
  final _confirmareParolaController = TextEditingController();

  void _handleRegister() async {
    if (!_acceptedTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Trebuie să accepți informările de confidențialitate!')),
      );
      return;
    }
    if (_parolaController.text != _confirmareParolaController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Parolele nu se potrivesc!')),
      );
      return;
    }

    setState(() => _isLoading = true);

    final bool success = await ApiService.registerUser(
      firstName: _prenumeController.text,
      lastName: _numeController.text,
      email: _emailController.text,
      birthDate: _dataNasteriiController.text,
      school: _liceulController.text,
      locality: _localitateaController.text,
      password: _parolaController.text,
      acceptedPrivacyPolicy: _acceptedTerms,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (success) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VerifyEmailScreen(email: _emailController.text),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Eroare la înregistrare. Verifică datele introduse!')),
      );
    }
  }

  @override
  void dispose() {
    _numeController.dispose();
    _prenumeController.dispose();
    _emailController.dispose();
    _dataNasteriiController.dispose();
    _liceulController.dispose();
    _localitateaController.dispose();
    _parolaController.dispose();
    _confirmareParolaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 20),
              const Text(
                'OVERTHINK',
                style: TextStyle(
                  color: Colors.red,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 40),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Creează un cont',
                      style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 20),
                    _buildTextField(label: 'Nume', controller: _numeController),
                    _buildTextField(label: 'Prenume', controller: _prenumeController),
                    _buildTextField(
                      label: 'Email',
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                    ),
                    _buildTextField(label: 'Data nașterii (YYYY-MM-DD)', controller: _dataNasteriiController),
                    _buildTextField(label: 'Liceul', controller: _liceulController),
                    _buildTextField(label: 'Localitatea', controller: _localitateaController),
                    _buildTextField(label: 'Parola', controller: _parolaController, obscureText: true),
                    _buildTextField(
                      label: 'Confirmare Parolă',
                      controller: _confirmareParolaController,
                      obscureText: true,
                    ),
                    Row(
                      children: [
                        Checkbox(
                          value: _acceptedTerms,
                          activeColor: Colors.red,
                          onChanged: (val) => setState(() => _acceptedTerms = val ?? false),
                        ),
                        const Expanded(
                          child: Text(
                            'Sunt de acord cu informările de confidențialitate.',
                            style: TextStyle(color: Colors.white70, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                        ),
                        onPressed: _isLoading ? null : _handleRegister,
                        child: _isLoading
                            ? const CircularProgressIndicator(color: Colors.white)
                            : const Text(
                          'Înregistrare',
                          style: TextStyle(fontSize: 18, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    bool obscureText = false,
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
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
        ),
      ),
    );
  }
}