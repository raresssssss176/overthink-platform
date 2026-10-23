// lib/screens/auth/register_screen.dart
import 'package:flutter/material.dart';

import '../../data/school_options.dart';
import '../../services/api_service.dart';
import '../../widgets/auth_widgets.dart';
import 'verify_email_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _lastNameController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _birthDateController = TextEditingController();
  final _otherSchoolController = TextEditingController();
  final _localityController = TextEditingController();
  final _phoneController = TextEditingController();
  final _acronymController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  DateTime? _birthDate;
  String? _selectedSchool;
  final Set<String> _selectedDepartmentIds = {};
  bool _acceptedPrivacy = false;
  bool _isLoading = false;

  List<Department>? _departments;
  String? _departmentsError;

  @override
  void initState() {
    super.initState();
    _loadDepartments();
  }

  @override
  void dispose() {
    _lastNameController.dispose();
    _firstNameController.dispose();
    _emailController.dispose();
    _birthDateController.dispose();
    _otherSchoolController.dispose();
    _localityController.dispose();
    _phoneController.dispose();
    _acronymController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _show(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _loadDepartments() async {
    setState(() => _departmentsError = null);
    final result = await ApiService.fetchDepartments();
    if (!mounted) return;
    setState(() {
      if (result.isSuccess) {
        _departments = result.value;
      } else {
        _departmentsError = result.message;
      }
    });
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(now.year - 16, now.month, now.day),
      firstDate: DateTime(1950),
      lastDate: now.subtract(const Duration(days: 1)),
    );
    if (picked != null) {
      setState(() {
        _birthDate = picked;
        _birthDateController.text = _formatIsoDate(picked);
      });
    }
  }

  static String _formatIsoDate(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  /// The school as it will be sent: the dropdown value, or the typed name when "Altul" is chosen.
  String _resolvedSchool() {
    if (_selectedSchool == null) return '';
    if (isOtherSchool(_selectedSchool)) return _otherSchoolController.text.trim();
    return _selectedSchool!;
  }

  /// Removes spaces and dashes, so "0741 951 139" becomes "0741951139".
  String _normalizedPhone() {
    return _phoneController.text.replaceAll(RegExp(r'[\s\-]'), '');
  }

  /// Returns the first validation error in Romanian, or null when the form is valid.
  String? _validate() {
    if (_lastNameController.text.trim().isEmpty || _firstNameController.text.trim().isEmpty) {
      return 'Completează numele și prenumele.';
    }
    final email = _emailController.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return 'Introdu o adresă de email validă.';
    }
    if (_birthDate == null) {
      return 'Alege data nașterii.';
    }
    if (_resolvedSchool().isEmpty) {
      return 'Alege liceul sau scrie numele lui.';
    }
    if (_localityController.text.trim().isEmpty) {
      return 'Completează localitatea.';
    }
    if (!RegExp(r'^\+?[0-9]{8,15}$').hasMatch(_normalizedPhone())) {
      return 'Telefonul trebuie să aibă între 8 și 15 cifre.';
    }
    final acronym = _acronymController.text.trim();
    if (acronym.isEmpty || acronym.length > 30) {
      return 'Acronimul trebuie să aibă între 1 și 30 de caractere.';
    }
    if (_selectedDepartmentIds.isEmpty) {
      return 'Alege cel puțin un departament.';
    }
    if (_passwordController.text.length < 10) {
      return 'Parola trebuie să aibă cel puțin 10 caractere.';
    }
    if (_passwordController.text != _confirmPasswordController.text) {
      return 'Parolele nu se potrivesc.';
    }
    if (!_acceptedPrivacy) {
      return 'Trebuie să accepți informările de confidențialitate.';
    }
    return null;
  }

  Future<void> _handleRegister() async {
    final error = _validate();
    if (error != null) {
      _show(error);
      return;
    }

    final email = _emailController.text.trim();
    setState(() => _isLoading = true);
    final result = await ApiService.registerUser(
      firstName: _firstNameController.text.trim(),
      lastName: _lastNameController.text.trim(),
      email: email,
      password: _passwordController.text,
      birthDate: _formatIsoDate(_birthDate!),
      school: _resolvedSchool(),
      locality: _localityController.text.trim(),
      phone: _normalizedPhone(),
      acronym: _acronymController.text.trim(),
      departmentIds: _selectedDepartmentIds.toList(),
      acceptedPrivacyPolicy: _acceptedPrivacy,
    );
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result.isSuccess) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => VerifyEmailScreen(email: email)),
      );
    } else {
      _show(result.message!);
    }
  }

  Widget _buildDepartments() {
    if (_departmentsError != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_departmentsError!, style: const TextStyle(color: Colors.redAccent)),
          TextButton(
            onPressed: _loadDepartments,
            child: const Text('Încearcă din nou', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      );
    }
    if (_departments == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator(color: Colors.red)),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final d in _departments!)
          FilterChip(
            label: Text(d.name),
            selected: _selectedDepartmentIds.contains(d.id),
            selectedColor: Colors.red,
            checkmarkColor: Colors.white,
            labelStyle: TextStyle(
              color: _selectedDepartmentIds.contains(d.id) ? Colors.white : Colors.white70,
            ),
            backgroundColor: Colors.black26,
            onSelected: (selected) {
              setState(() {
                if (selected) {
                  _selectedDepartmentIds.add(d.id);
                } else {
                  _selectedDepartmentIds.remove(d.id);
                }
              });
            },
          ),
      ],
    );
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
              const SizedBox(height: 20),
              const OverthinkLogo(),
              const SizedBox(height: 40),
              AuthCard(
                title: 'Creează un cont',
                children: [
                  AuthTextField(label: 'Nume', controller: _lastNameController),
                  AuthTextField(label: 'Prenume', controller: _firstNameController),
                  AuthTextField(
                    label: 'Email',
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                  ),
                  AuthTextField(
                    label: 'Data nașterii',
                    controller: _birthDateController,
                    readOnly: true,
                    onTap: _pickBirthDate,
                    hint: 'AAAA-LL-ZZ',
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedSchool,
                    isExpanded: true,
                    dropdownColor: const Color(0xFF2A2A2A),
                    style: const TextStyle(color: Colors.white),
                    decoration: authInputDecoration('Liceul'),
                    items: [
                      for (final s in schoolOptions)
                        DropdownMenuItem(
                          value: s,
                          child: Text(s, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (value) => setState(() => _selectedSchool = value),
                  ),
                  const SizedBox(height: 16),
                  if (isOtherSchool(_selectedSchool))
                    AuthTextField(label: 'Scrie numele liceului', controller: _otherSchoolController),
                  AuthTextField(label: 'Localitatea', controller: _localityController),
                  AuthTextField(
                    label: 'Telefon',
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                  ),
                  AuthTextField(
                    label: 'Acronim',
                    controller: _acronymController,
                    hint: 'Porecla cu care vrei să fii strigat',
                  ),
                  const Text(
                    'Departamente',
                    style: TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  _buildDepartments(),
                  const SizedBox(height: 16),
                  AuthTextField(label: 'Parola', controller: _passwordController, obscure: true),
                  AuthTextField(
                    label: 'Confirmare parolă',
                    controller: _confirmPasswordController,
                    obscure: true,
                  ),
                  Row(
                    children: [
                      Checkbox(
                        value: _acceptedPrivacy,
                        activeColor: Colors.red,
                        onChanged: (value) => setState(() => _acceptedPrivacy = value ?? false),
                      ),
                      const Expanded(
                        child: Text(
                          'Sunt de acord cu informările de confidențialitate.',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  AuthButton(
                    label: 'Înregistrare',
                    loading: _isLoading,
                    onPressed: _handleRegister,
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
