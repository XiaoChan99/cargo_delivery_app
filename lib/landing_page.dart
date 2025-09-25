import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage>
    with TickerProviderStateMixin {
  late AnimationController _floatingController;
  late AnimationController _pulseController;
  late AnimationController _fadeController;
  late Animation<double> _floatingAnimation;
  late Animation<double> _pulseAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _floatingController = AnimationController(
      duration: const Duration(seconds: 4),
      vsync: this,
    )..repeat(reverse: true);
    
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..forward();

    _floatingAnimation = Tween<double>(
      begin: -15.0,
      end: 15.0,
    ).animate(CurvedAnimation(
      parent: _floatingController,
      curve: Curves.easeInOut,
    ));

    _pulseAnimation = Tween<double>(
      begin: 0.95,
      end: 1.05,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    ));
  }

  @override
  void dispose() {
    _floatingController.dispose();
    _pulseController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isSmallScreen = screenWidth < 768;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0A0E27),
              Color(0xFF162447),
              Color(0xFF1F4E79),
              Color(0xFF0A0E27),
            ],
            stops: [0.0, 0.3, 0.7, 1.0],
          ),
        ),
        child: Stack(
          children: [
            // Animated background elements
            ...List.generate(30, (index) => _buildFloatingParticle(index)),

            // Grid overlay
            Opacity(
              opacity: 0.03,
              child: SvgPicture.string(
                _modernGridPattern,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
              ),
            ),

            // Glassmorphism elements
            Positioned(
              top: screenHeight * 0.1,
              right: -100,
              child: _buildGlassMorphismCircle(200, Colors.cyan),
            ),
            Positioned(
              bottom: screenHeight * 0.15,
              left: -80,
              child: _buildGlassMorphismCircle(160, Colors.blue),
            ),
            Positioned(
              top: screenHeight * 0.4,
              left: screenWidth * 0.2,
              child: _buildGlassMorphismCircle(120, Colors.teal),
            ),

            // Centered login container
            Center(
              child: SingleChildScrollView(
                child: _buildCTASection(theme, isSmallScreen),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFloatingParticle(int index) {
    final random = (index * 17) % 100;
    final size = 3.0 + (random % 5);
    final left = (random * 5.3) % MediaQuery.of(context).size.width;
    final top = ((random * 7.1) % MediaQuery.of(context).size.height);
    
    return AnimatedBuilder(
      animation: _floatingController,
      builder: (context, child) {
        return Positioned(
          left: left,
          top: top + (_floatingAnimation.value * (0.5 + (random % 10) * 0.1)),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.1 + (random % 20) * 0.01),
              boxShadow: [
                BoxShadow(
                  color: Colors.cyan.withOpacity(0.2),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildGlassMorphismCircle(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color.withOpacity(0.15),
            color.withOpacity(0.08),
            Colors.transparent,
          ],
          stops: [0.0, 0.5, 1.0],
        ),
        border: Border.all(
          color: color.withOpacity(0.15),
          width: 1.5,
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, bool isSmallScreen) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            ScaleTransition(
              scale: _pulseAnimation,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF00D4FF), Color(0xFF0099CC)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00D4FF).withOpacity(0.4),
                      blurRadius: 25,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: SvgPicture.string(
                  _modernLogoSvg,
                  width: 32,
                  height: 32,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Text(
              "PORTFLOW",
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: 3.0,
                fontSize: isSmallScreen ? 20 : 24,
                shadows: [
                  Shadow(
                    color: const Color(0xFF00D4FF).withOpacity(0.6),
                    blurRadius: 15,
                  ),
                ],
              ),
            ),
          ],
        ),
        if (!isSmallScreen)
          Row(
            children: [
              TextButton(
                onPressed: () {},
                child: Text(
                  "Features",
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton(
                onPressed: () {},
                child: Text(
                  "Solutions",
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton(
                onPressed: () {},
                child: Text(
                  "Pricing",
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(25),
                  border: Border.all(color: Colors.white.withOpacity(0.2)),
                ),
                child: Text(
                  "BETA",
                  style: TextStyle(
                    color: const Color(0xFF00D4FF),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          )
        else
          IconButton(
            onPressed: () {},
            icon: Icon(Icons.menu, color: Colors.white),
          ),
      ],
    );
  }

  Widget _buildHeroSection(ThemeData theme, double screenWidth, bool isSmallScreen) {
    return Column(
      children: [
        // Main illustration with floating effect
        AnimatedBuilder(
          animation: _floatingAnimation,
          builder: (context, child) {
            return Transform.translate(
              offset: Offset(0, _floatingAnimation.value),
              child: Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.white.withOpacity(0.08),
                      Colors.white.withOpacity(0.03),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.15),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00D4FF).withOpacity(0.15),
                      blurRadius: 50,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: SvgPicture.string(
                  _ultraModernPortSvg,
                  width: isSmallScreen ? screenWidth * 0.85 : 500,
                ),
              ),
            );
          },
        ),
        
        const SizedBox(height: 50),
        
        // Animated headline
        FadeTransition(
          opacity: _fadeAnimation,
          child: Column(
            children: [
              Text(
                "Intelligent Port Management",
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineLarge?.copyWith(
                  fontWeight: FontWeight.w300,
                  color: const Color(0xFF00D4FF),
                  fontSize: isSmallScreen ? 24 : 32,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 8),
              ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [Color(0xFF00D4FF), Color(0xFF00FF94), Colors.white],
                  stops: [0.0, 0.5, 1.0],
                ).createShader(bounds),
                child: Text(
                  "Optimize Operations",
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    height: 1.2,
                    fontSize: isSmallScreen ? 36 : 48,
                    letterSpacing: 1,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF00D4FF).withOpacity(0.25),
                      const Color(0xFF0099CC).withOpacity(0.15),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: const Color(0xFF00D4FF).withOpacity(0.4)),
                ),
                child: Text(
                  "AI-POWERED • REAL-TIME • PREDICTIVE ANALYTICS",
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: const Color(0xFF00D4FF),
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.5,
                    fontSize: isSmallScreen ? 11 : 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFeaturesSection(ThemeData theme, double screenWidth, bool isSmallScreen) {
    final features = [
      {
        'icon': Icons.analytics_outlined,
        'title': 'Predictive Analytics',
        'description': 'AI-driven insights to forecast congestion patterns and optimize resource allocation',
        'color': const Color(0xFF00D4FF),
      },
      {
        'icon': Icons.speed_outlined,
        'title': 'Real-time Optimization',
        'description': 'Dynamic scheduling and route optimization based on live port conditions',
        'color': const Color(0xFF00FF94),
      },
      {
        'icon': Icons.inventory_2_outlined,
        'title': 'Smart Logistics',
        'description': 'Automated cargo tracking and management with IoT integration',
        'color': const Color(0xFFFF6B6B),
      },
      {
        'icon': Icons.visibility_outlined,
        'title': 'Complete Visibility',
        'description': 'End-to-end supply chain transparency with real-time status updates',
        'color': const Color(0xFFFFD93D),
      },
    ];

    return Column(
      children: [
        Text(
          "Revolutionizing Maritime Operations",
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: Colors.white,
            fontSize: isSmallScreen ? 24 : 32,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          "Advanced technology for efficient port management and congestion reduction",
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withOpacity(0.7),
            fontSize: isSmallScreen ? 16 : 18,
          ),
        ),
        const SizedBox(height: 50),
        Wrap(
          spacing: 24,
          runSpacing: 24,
          alignment: WrapAlignment.center,
          children: features.map((feature) => _buildFeatureCard(
            feature['icon'] as IconData,
            feature['title'] as String,
            feature['description'] as String,
            feature['color'] as Color,
            isSmallScreen,
          )).toList(),
        ),
      ],
    );
  }

  Widget _buildFeatureCard(IconData icon, String title, String description, Color color, bool isSmallScreen) {
    return TweenAnimationBuilder<double>(
      duration: Duration(milliseconds: 800 + (title.hashCode % 500)),
      tween: Tween<double>(begin: 0.0, end: 1.0),
      builder: (context, value, child) {
        return Transform.scale(
          scale: 0.8 + (0.2 * value),
          child: Opacity(
            opacity: value,
            child: Container(
              width: isSmallScreen ? 280 : 300,
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withOpacity(0.1),
                    Colors.white.withOpacity(0.03),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: color.withOpacity(0.4),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.15),
                    blurRadius: 25,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [color.withOpacity(0.25), color.withOpacity(0.1)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: color.withOpacity(0.3),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Icon(icon, color: color, size: 32),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    title,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    description,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 15,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatsSection(ThemeData theme, bool isSmallScreen) {
    final stats = [
      {'value': '50%', 'label': 'Congestion Reduction'},
      {'value': '30%', 'label': 'Faster Turnaround'},
      {'value': '99.9%', 'label': 'System Uptime'},
      {'value': '24/7', 'label': 'Real-time Monitoring'},
    ];

    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF00D4FF).withOpacity(0.08),
            Colors.transparent,
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF00D4FF).withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(
            "Proven Results",
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: Colors.white,
              fontSize: isSmallScreen ? 20 : 24,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            "Industry-leading performance metrics from our global deployments",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: isSmallScreen ? 14 : 16,
            ),
          ),
          const SizedBox(height: 40),
          Wrap(
            spacing: 40,
            runSpacing: 40,
            alignment: WrapAlignment.spaceEvenly,
            children: stats.map((stat) => Column(
              children: [
                ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [Color(0xFF00D4FF), Color(0xFF00FF94)],
                  ).createShader(bounds),
                  child: Text(
                    stat['value']!,
                    style: TextStyle(
                      fontSize: isSmallScreen ? 32 : 42,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  stat['label']!,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: isSmallScreen ? 14 : 16,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            )).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildCTASection(ThemeData theme, bool isSmallScreen) {
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white.withOpacity(0.1),
            Colors.white.withOpacity(0.03),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white.withOpacity(0.15)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 50,
            spreadRadius: 5,
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            "Ready to Transform Your Operations?",
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: Colors.white,
              fontSize: isSmallScreen ? 24 : 32,
            ),
            textAlign: TextAlign.center,
          ),
          
          const SizedBox(height: 16),
          
          Text(
            "Join leading ports worldwide using Port Congestion Delivery App to optimize their operations",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: isSmallScreen ? 16 : 18,
            ),
          ),
          
          const SizedBox(height: 40),
          
          // Google Sign In button with glassmorphism
          Container(
            width: isSmallScreen ? double.infinity : 400,
            height: 56,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.white.withOpacity(0.2),
                  Colors.white.withOpacity(0.08),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.25)),
            ),
            child: ElevatedButton(
              onPressed: () {
                // TODO: Implement Google OAuth
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SvgPicture.string(_googleSvg, height: 24),
                  const SizedBox(width: 16),
                  const Text(
                    "Continue with Google",
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 20),
          
          // Divider
          Row(
            children: [
              Expanded(child: Divider(color: Colors.white.withOpacity(0.3))),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  "or",
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Expanded(child: Divider(color: Colors.white.withOpacity(0.3))),
            ],
          ),
          
          const SizedBox(height: 20),
          
          // Primary CTA button with glowing effect
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _pulseAnimation.value,
                child: Container(
                  width: isSmallScreen ? double.infinity : 400,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF00D4FF), Color(0xFF0099CC)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00D4FF).withOpacity(0.5),
                        blurRadius: 25,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pushNamed(context, '/login');
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      "Login",
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          
          const SizedBox(height: 24),
          
          TextButton(
            onPressed: () {
              Navigator.pushNamed(context, '/register');
            },
            child: RichText(
              text: TextSpan(
                text: "New to Port Congestion Delivery App? ",
                style: TextStyle(color: Colors.white.withOpacity(0.7)),
                children: [
                  TextSpan(
                    text: "Create Account",
                    style: TextStyle(
                      color: const Color(0xFF00D4FF),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(ThemeData theme) {
    return Column(
      children: [
        Divider(color: Colors.white.withOpacity(0.15), thickness: 1),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              "© 2025 Port Congestion Management• Next-Generation Maritime Intelligence",
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.white.withOpacity(0.5),
                fontSize: 12,
              ),
            ),
            Row(
              children: [
                IconButton(
                  onPressed: () {},
                  icon: Icon(Icons.language, color: Colors.white.withOpacity(0.7), size: 20),
                ),
                IconButton(
                  onPressed: () {},
                  icon: Icon(Icons.help_outline, color: Colors.white.withOpacity(0.7), size: 20),
                ),
                IconButton(
                  onPressed: () {},
                  icon: Icon(Icons.mail_outline, color: Colors.white.withOpacity(0.7), size: 20),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

// Enhanced SVG constants
const String _ultraModernPortSvg = '''
<svg viewBox="0 0 600 350" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <!-- Enhanced gradients -->
    <linearGradient id="skyGradient" x1="0%" y1="0%" x2="0%" y2="100%">
      <stop offset="0%" stop-color="#0A0E27" />
      <stop offset="50%" stop-color="#162447" />
      <stop offset="100%" stop-color="#1F4E79" />
    </linearGradient>
    
    <linearGradient id="waterGradient" x1="0%" y1="0%" x2="0%" y2="100%">
      <stop offset="0%" stop-color="#006994" />
      <stop offset="50%" stop-color="#0080B8" />
      <stop offset="100%" stop-color="#00A8E6" />
    </linearGradient>
    
    <linearGradient id="shipGradient" x1="0%" y1="0%" x2="0%" y2="100%">
      <stop offset="0%" stop-color="#2C3E50" />
      <stop offset="100%" stop-color="#34495E" />
    </linearGradient>
    
    <linearGradient id="craneGradient" x1="0%" y1="0%" x2="0%" y2="100%">
      <stop offset="0%" stop-color="#00D4FF" />
      <stop offset="100%" stop-color="#0099CC" />
    </linearGradient>
    
    <linearGradient id="containerGlow" x1="0%" y1="0%" x2="100%" y2="0%">
      <stop offset="0%" stop-color="#00FF94" />
      <stop offset="50%" stop-color="#00D4FF" />
      <stop offset="100%" stop-color="#FF6B6B" />
    </linearGradient>
    <!-- ...existing code... -->

    <!-- Add filters for glowing effects -->
    <filter id="glow" x="-50%" y="-50%" width="200%" height="200%">
      <feGaussianBlur in="SourceGraphic" stdDeviation="5" />
    </filter>
    
    <!-- Add patterns for modern tech look -->
    <pattern id="grid" x="0" y="0" width="20" height="20" patternUnits="userSpaceOnUse">
      <path d="M 20 0 L 0 0 0 20" fill="none" stroke="#00D4FF" stroke-width="0.5" opacity="0.3"/>
    </pattern>
  </defs>
  
  <!-- Background -->
  <rect width="600" height="350" fill="url(#skyGradient)"/>
  <rect width="600" height="150" y="200" fill="url(#waterGradient)"/>
  
  <!-- Grid overlay -->
  <rect width="600" height="350" fill="url(#grid)" opacity="0.1"/>
  
  <!-- Port infrastructure -->
  <g transform="translate(50, 100)">
    <!-- Modern crane with animation -->
    <path d="M 100 0 L 100 200 L 300 200" stroke="url(#craneGradient)" stroke-width="8" fill="none"/>
    <path d="M 100 50 L 250 50" stroke="url(#craneGradient)" stroke-width="6" fill="none"/>
    
    <!-- Smart containers with glow -->
    <g filter="url(#glow)">
      <rect x="180" y="150" width="40" height="30" fill="url(#containerGlow)"/>
      <rect x="230" y="150" width="40" height="30" fill="url(#containerGlow)"/>
      <rect x="200" y="120" width="40" height="30" fill="url(#containerGlow)"/>
    </g>
    
    <!-- Digital elements -->
    <circle cx="100" cy="30" r="5" fill="#00FF94" opacity="0.8">
      <animate attributeName="opacity" values="0.8;0.3;0.8" dur="2s" repeatCount="indefinite"/>
    </circle>
    <circle cx="250" cy="50" r="5" fill="#00D4FF" opacity="0.8">
      <animate attributeName="opacity" values="0.8;0.3;0.8" dur="2s" repeatCount="indefinite"/>
    </circle>
  </g>
</svg>
''';

const String _modernGridPattern = '''
<svg width="100" height="100" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <pattern id="modernGrid" x="0" y="0" width="50" height="50" patternUnits="userSpaceOnUse">
      <line x1="0" y1="0" x2="50" y2="0" stroke="#fff" stroke-width="0.5" opacity="0.2"/>
      <line x1="0" y1="0" x2="0" y2="50" stroke="#fff" stroke-width="0.5" opacity="0.2"/>
    </pattern>
  </defs>
  <rect width="100" height="100" fill="url(#modernGrid)"/>
</svg>
''';

const String _modernLogoSvg = '''
<svg viewBox="0 0 50 50" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="logoGradient" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#ffffff"/>
      <stop offset="100%" stop-color="#f0f0f0"/>
    </linearGradient>
  </defs>
  <!-- Abstract port symbol -->
  <path d="M10 25 L25 10 L40 25 L25 40 Z" fill="url(#logoGradient)" stroke="none"/>
  <circle cx="25" cy="25" r="5" fill="#00D4FF">
    <animate attributeName="r" values="5;6;5" dur="2s" repeatCount="indefinite"/>
  </circle>
  <!-- Digital wave lines -->
  <path d="M15 30 Q25 20 35 30" stroke="#00D4FF" stroke-width="2" fill="none"/>
  <path d="M15 35 Q25 25 35 35" stroke="#00D4FF" stroke-width="2" fill="none" opacity="0.5"/>
</svg>
''';

const String _googleSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48" width="24px" height="24px">
  <path fill="#FFC107" d="M43.611,20.083H42V20H24v8h11.303c-1.649,4.657-6.08,8-11.303,8c-6.627,0-12-5.373-12-12
    s5.373-12,12-12c3.059,0,5.842,1.154,7.961,3.039l5.657-5.657C34.046,6.053,29.268,4,24,4C12.955,4,4,12.955,4,24s8.955,20,20,20
    s20-8.955,20-20C44,22.659,43.862,21.35,43.611,20.083z"/>
  <path fill="#FF3D00" d="M6.306,14.691l6.571,4.819C14.655,15.108,18.961,12,24,12c3.059,0,5.842,1.154,7.961,3.039l5.657-5.657
    C34.046,6.053,29.268,4,24,4C16.318,4,9.656,8.337,6.306,14.691z"/>
  <path fill="#4CAF50" d="M24,44c5.166,0,9.86-1.977,13.409-5.192l-6.19-5.238C29.211,35.091,26.715,36,24,36
    c-5.202,0-9.619-3.317-11.283-7.946l-6.522,5.025C9.505,39.556,16.227,44,24,44z"/>
  <path fill="#1976D2" d="M43.611,20.083H42V20H24v8h11.303c-0.792,2.237-2.231,4.166-4.087,5.571
    c0.001-0.001,0.002-0.001,0.003-0.002l6.19,5.238C36.971,39.205,44,34,44,24C44,22.659,43.862,21.35,43.611,20.083z"/>
</svg>
''';
