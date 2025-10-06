import 'package:flutter/material.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import 'login_page.dart';

class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> {
  final PageController _controller = PageController();
  bool isLastPage = false;
  int _currentPage = 0;

  // Page data with background images
  final List<OnboardingPage> _pages = [
    OnboardingPage(
      imagePath: "assets/images/page1.png",
    ),
    OnboardingPage(
      imagePath: "assets/images/page2.png",
    ),
    OnboardingPage(
      imagePath: "assets/images/page3.png",
    ),
  ];

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      setState(() {
        _currentPage = _controller.page?.round() ?? 0;
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _navigateToLogin() {
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => const LoginPage(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
        transitionDuration: Duration(milliseconds: 600),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background Image that covers screen without zooming
          PageView(
            controller: _controller,
            onPageChanged: (index) {
              setState(() => isLastPage = index == _pages.length - 1);
            },
            children: _pages.map((page) {
              return Container(
                width: double.infinity,
                height: double.infinity,
                child: Image.asset(
                  page.imagePath,
                  fit: BoxFit.cover, // Covers the entire screen
                  alignment: Alignment.center,
                  // This ensures the image scales properly without distortion
                  filterQuality: FilterQuality.high, // HD quality
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: Colors.grey[300],
                      child: Center(
                        child: Icon(
                          Icons.error_outline,
                          size: 50,
                          color: Colors.grey[600],
                        ),
                      ),
                    );
                  },
                ),
              );
            }).toList(),
          ),

          // Overlay with buttons and indicators
          SafeArea(
            child: Column(
              children: [
                // Header with skip button
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Empty space for logo/text that's already in the image
                      Container(),
                      
                      // Skip button - clean without background
                      AnimatedOpacity(
                        duration: Duration(milliseconds: 300),
                        opacity: isLastPage ? 0 : 1,
                        child: TextButton(
                          onPressed: _navigateToLogin,
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            foregroundColor: Colors.white,
                            backgroundColor: Colors.transparent,
                            elevation: 0,
                          ),
                          child: Text(
                            "Skip",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                              shadows: [
                                Shadow(
                                  blurRadius: 4,
                                  color: Colors.black.withOpacity(0.3),
                                  offset: Offset(1, 1),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Spacer to push controls to bottom
                Expanded(child: Container()),
                
                // Bottom section with indicator and navigation button
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                  child: Column(
                    children: [
                      // Page indicator
                      SmoothPageIndicator(
                        controller: _controller,
                        count: _pages.length,
                        effect: SlideEffect(
                          dotHeight: 10,
                          dotWidth: 10,
                          activeDotColor: Colors.white,
                          dotColor: Colors.white.withOpacity(0.3),
                          spacing: 10,
                        ),
                      ),
                      
                      SizedBox(height: 30),
                      
                      // Navigation button - clean without background
                      Row(
                        children: [
                          // Spacer to push button to right
                          Expanded(
                            child: Container(),
                          ),
                          
                          // Next/Let's Deliver button
                          Container(
                            width: 140,
                            height: 50,
                            child: TextButton(
                              onPressed: () {
                                if (isLastPage) {
                                  _navigateToLogin();
                                } else {
                                  _controller.nextPage(
                                    duration: const Duration(milliseconds: 500),
                                    curve: Curves.easeInOut,
                                  );
                                }
                              },
                              style: TextButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                elevation: 0,
                                padding: EdgeInsets.zero,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    isLastPage ? "Let's Deliver" : "Next",
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      letterSpacing: 0.5,
                                      shadows: [
                                        Shadow(
                                          blurRadius: 4,
                                          color: Colors.black.withOpacity(0.3),
                                          offset: Offset(1, 1),
                                        ),
                                      ],
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  AnimatedSwitcher(
                                    duration: Duration(milliseconds: 300),
                                    child: Icon(
                                      isLastPage ? Icons.rocket_launch : Icons.arrow_forward_ios_rounded,
                                      size: 18,
                                      color: Colors.white,
                                      key: ValueKey(isLastPage),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      
                      // Additional sign in option for last page
                      if (isLastPage) ...[
                        SizedBox(height: 20),
                        TextButton(
                          onPressed: _navigateToLogin,
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                            backgroundColor: Colors.transparent,
                          ),
                          child: Text(
                            "Already have an account? Sign In",
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Colors.white,
                              shadows: [
                                Shadow(
                                  blurRadius: 4,
                                  color: Colors.black.withOpacity(0.3),
                                  offset: Offset(1, 1),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class OnboardingPage {
  final String imagePath;

  OnboardingPage({
    required this.imagePath,
  });
}