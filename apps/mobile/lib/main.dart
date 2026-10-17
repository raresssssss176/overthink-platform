// lib/main.dart
import 'package:flutter/material.dart';
import 'screens/auth/login_screen.dart';

void main() {
  runApp(const OverthinkApp());
}

class OverthinkApp extends StatelessWidget {
  const OverthinkApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Overthink',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.red,
        fontFamily: 'Roboto',
      ),
      home: const LoginScreen(),
    );
  }
}