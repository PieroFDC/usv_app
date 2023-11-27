import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'pages/start_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      systemNavigationBarColor: Color(0xFF252525), // navigation bar color
      statusBarColor: Colors.transparent, // status bar color
    ));
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Flutter Demo',
      home: StartPage(),
    );
  }
}
