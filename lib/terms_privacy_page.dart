import 'package:flutter/material.dart';

class TermsPrivacyPage extends StatelessWidget {
  const TermsPrivacyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF3B82F6),
        foregroundColor: Colors.white,
        title: const Text(
          "Terms & Privacy",
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const SizedBox(height: 24),
              
              Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Colors.white, Color(0xFFFAFBFF)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 20,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Terms of Service",
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildTermsSection(
                        "1. Acceptance of Terms",
                        "By using this cargo delivery application, you agree to comply with and be bound by these terms and conditions.",
                      ),
                      _buildTermsSection(
                        "2. User Responsibilities",
                        "Users are responsible for maintaining the confidentiality of their account information and for all activities under their account.",
                      ),
                      _buildTermsSection(
                        "3. Service Availability",
                        "We strive to maintain service availability but do not guarantee uninterrupted access to the application.",
                      ),
                      
                      const SizedBox(height: 32),
                      
                      const Text(
                        "Privacy Policy",
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildTermsSection(
                        "Data Collection",
                        "We collect information necessary to provide delivery services, including location data, delivery details, and user preferences.",
                      ),
                      _buildTermsSection(
                        "Data Usage",
                        "Your data is used to improve service quality, track deliveries, and provide customer support. We do not sell personal information to third parties.",
                      ),
                      _buildTermsSection(
                        "Data Security",
                        "We implement industry-standard security measures to protect your personal information and delivery data.",
                      ),
                      
                      const SizedBox(height: 32),
                      
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3B82F6).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF3B82F6).withOpacity(0.2)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  color: const Color(0xFF3B82F6),
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  "Last Updated",
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF3B82F6),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              "These terms and privacy policy were last updated on January 15, 2024. We may update these terms periodically, and users will be notified of significant changes.",
                              style: TextStyle(
                                fontSize: 14,
                                color: Color(0xFF1E293B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTermsSection(String title, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF64748B),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
