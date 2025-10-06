import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

class LoadingScreen extends StatefulWidget {
  const LoadingScreen({Key? key}) : super(key: key);

  @override
  _LoadingScreenState createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen> {
  bool _hasError = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      // Add a small delay to ensure Flutter is fully initialized
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Navigate to appropriate screen
      _navigateToNextScreen();
    } catch (e) {
      print('Error in loading screen: $e');
      setState(() {
        _hasError = true;
        _errorMessage = e.toString();
      });
      
      // Fallback navigation after error
      await Future.delayed(const Duration(seconds: 2));
      _navigateToLanding();
    }
  }

  void _navigateToNextScreen() {
    // Simple navigation without Firebase checks to avoid JS errors
    Future.delayed(const Duration(seconds: 3), () {
      _navigateToLanding();
    });
  }

  void _navigateToLanding() {
    Navigator.pushReplacementNamed(context, '/');
  }

  void _navigateToHome() {
    Navigator.pushReplacementNamed(context, '/home');
  }

  Widget _buildErrorView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(
          Icons.error_outline,
          color: Colors.red,
          size: 64,
        ),
        const SizedBox(height: 20),
        const Text(
          'Loading Error',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1E40AF),
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            _errorMessage.isNotEmpty 
                ? _errorMessage 
                : 'An error occurred while loading the app',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF64748B),
            ),
          ),
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: _initializeApp,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF3B82F6),
            foregroundColor: Colors.white,
          ),
          child: const Text('Retry'),
        ),
      ],
    );
  }

  Widget _buildLoadingAnimation() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Fallback if Lottie fails
        _buildLottieAnimation(),
        const SizedBox(height: 20),
        const Text(
          'Port Congestion Management',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1E40AF),
          ),
        ),
        const SizedBox(height: 10),
        const CircularProgressIndicator(
          color: Color(0xFF3B82F6),
        ),
        const SizedBox(height: 10),
        const Text(
          'Loading...',
          style: TextStyle(
            fontSize: 14,
            color: Color(0xFF64748B),
          ),
        ),
      ],
    );
  }

  Widget _buildLottieAnimation() {
    try {
      return Lottie.asset(
        'assets/animations/loading_animation.json',
        width: 200,
        height: 200,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          return _buildFallbackAnimation();
        },
      );
    } catch (e) {
      return _buildFallbackAnimation();
    }
  }

  Widget _buildFallbackAnimation() {
    return Container(
      width: 200,
      height: 200,
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(100),
      ),
      child: const Icon(
        Icons.local_shipping,
        size: 80,
        color: Color(0xFF3B82F6),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: _hasError ? _buildErrorView() : _buildLoadingAnimation(),
        ),
      ),
    );
  }
}