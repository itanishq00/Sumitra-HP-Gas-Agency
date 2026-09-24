import 'package:flutter/material.dart';

void main() {
  runApp(const GasSevaApp());
}

class GasSevaApp extends StatelessWidget {
  const GasSevaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sumitra HP Gas',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.red,
        scaffoldBackgroundColor: const Color(0xFFFFD6D6),
      ),
      home: const Scaffold(
        body: Center(
          child: Text('Sumitra HP Gas Agency'),
        ),
      ),
    );
  }
}
