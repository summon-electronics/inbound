import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'SplashScreen.dart';

class SplashTwo extends StatefulWidget {
  const SplashTwo({super.key});

  @override
  State<SplashTwo> createState() => _SplashTwoState();
}

class _SplashTwoState extends State<SplashTwo> {
  @override
  void initState() {
    super.initState();

    Future.delayed(const Duration(milliseconds: 4500), () {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const SplashScreen()),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Lottie.asset(
              'assets/Lottie/Search.json',
              width: 250,
              height: 250,
              fit: BoxFit.contain,
            ),
            Image.asset(
              'assets/images/inspection_genie.png',
              width: 200,
              height: 100,
            ),
          ],
        ),
      ),
    );
  }
}