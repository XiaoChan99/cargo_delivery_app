import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:firebase_auth/firebase_auth.dart'; // Add this import

class LoadingScreen extends StatefulWidget {
  const LoadingScreen({Key? key}) : super(key: key);

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen> with SingleTickerProviderStateMixin {
  bool _hasError = false;
  String _errorMessage = '';
  late AnimationController _controller;
  late Animation<double> _animation;
  final FirebaseAuth _auth = FirebaseAuth.instance; // Add Firebase Auth

  @override
  void initState() {
    super.initState();
    
    // Initialize animation controller
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    
    _animation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    ));
    
    _initializeApp();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _initializeApp() async {
    try {
      // Start animation
      _controller.forward();
      
      // Add a small delay to ensure Flutter is fully initialized
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Check if user is already logged in
      await _checkUserAuthentication();
    } catch (e) {
      print('Error in loading screen: $e');
      setState(() {
        _hasError = true;
        _errorMessage = e.toString();
      });
      
      // Fallback navigation after error
      await Future.delayed(const Duration(seconds: 2));
      _navigateBasedOnAuth();
    }
  }

  Future<void> _checkUserAuthentication() async {
    try {
      // Check if user is signed in
      final user = _auth.currentUser;
      
      if (user != null) {
        // User is logged in, navigate to home page
        print('User is logged in, navigating to home page');
        _navigateToHome();
      } else {
        // User is not logged in, navigate to landing page
        print('User is not logged in, navigating to landing page');
        _navigateToLanding();
      }
    } catch (e) {
      print('Error checking authentication: $e');
      // On error, navigate to landing page
      _navigateToLanding();
    }
  }

  void _navigateBasedOnAuth() {
    final user = _auth.currentUser;
    if (user != null) {
      _navigateToHome();
    } else {
      _navigateToLanding();
    }
  }

  void _navigateToLanding() {
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/');
    }
  }

  void _navigateToHome() {
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/home');
    }
  }

  Widget _buildErrorView() {
    return FadeTransition(
      opacity: _animation,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFFECACA)),
            ),
            child: const Icon(
              Icons.error_outline_rounded,
              color: Color(0xFFDC2626),
              size: 64,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Loading Error',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
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
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _initializeApp,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3B82F6),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Try Again',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingAnimation() {
    return FadeTransition(
      opacity: _animation,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Lottie animation with fallback
          _buildLottieAnimation(),
          const SizedBox(height: 32),
          const Text(
            "CARGO EXPRESS",
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1E40AF),
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            "Port Congestion Management",
            style: TextStyle(
              fontSize: 14,
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 32),
          Container(
            width: 40,
            height: 40,
            padding: const EdgeInsets.all(8),
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(
                const Color(0xFF3B82F6).withOpacity(0.8),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Loading...',
            style: TextStyle(
              fontSize: 14,
              color: Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLottieAnimation() {
    try {
      return Container(
        width: 200,
        height: 200,
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(100),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Lottie.asset(
          'assets/animations/loading_animation.json',
          width: 180,
          height: 180,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return _buildFallbackAnimation();
          },
        ),
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
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFF0F9FF),
            Color(0xFFE0F2FE),
          ],
        ),
        borderRadius: BorderRadius.circular(100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Animated background circles
          Positioned(
            top: 20,
            left: 20,
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFF3B82F6).withOpacity(0.1),
                  width: 2,
                ),
              ),
            ),
          ),
          // Main icon
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3B82F6),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF3B82F6).withOpacity(0.3),
                        blurRadius: 15,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.local_shipping_rounded,
                    size: 40,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  "Delivery",
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
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