import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class InfoPage extends StatefulWidget {
  const InfoPage({super.key});

  @override
  State<InfoPage> createState() => _InfoPageState();
}

class _InfoPageState extends State<InfoPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  Map<String, dynamic>? userData;
  bool isLoading = true;

  // Controllers for text fields
  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _licenseNumberController = TextEditingController();
  final TextEditingController _licenseExpiryController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchUserData();
  }

  Future<void> _fetchUserData() async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        final doc = await _firestore.collection('users').doc(user.uid).get();
        if (doc.exists) {
          setState(() {
            userData = doc.data()!;
            isLoading = false;
            
            // Pre-fill the text controllers with existing data
            _fullNameController.text = userData?['fullName'] ?? '';
            _emailController.text = userData?['email'] ?? '';
            _phoneController.text = userData?['phone'] ?? '';
            _licenseNumberController.text = userData?['driverLicenseInfo'] ?? '';
            
            // Format dates if they exist
            if (userData?['createdAt'] != null) {
              final createdAt = DateTime.parse(userData!['createdAt']);
              _licenseExpiryController.text = "${createdAt.year + 2}-${createdAt.month.toString().padLeft(2, '0')}-${createdAt.day.toString().padLeft(2, '0')}";
            }
          });
        } else {
          setState(() {
            isLoading = false;
          });
        }
      }
    } catch (e) {
      print("Error fetching user data: $e");
      setState(() {
        isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Failed to load user data"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _updateUserData() async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        await _firestore.collection('users').doc(user.uid).update({
          'fullName': _fullNameController.text,
          'email': _emailController.text,
          'phone': _phoneController.text,
          'driverLicenseInfo': _licenseNumberController.text,
          'updatedAt': DateTime.now().toIso8601String(),
        });

        // Refresh the data
        await _fetchUserData();
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Information updated successfully"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print("Error updating user data: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Failed to update information"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showEditDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 0,
              backgroundColor: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.edit_document,
                        size: 48,
                        color: Color(0xFF3B82F6),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        "Edit Information",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildEditField("Full Name", _fullNameController),
                      _buildEditField("Email", _emailController),
                      _buildEditField("Phone", _phoneController),
                      _buildEditField("License Number", _licenseNumberController),
                      _buildEditField("License Expiry", _licenseExpiryController, isDate: true),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                Navigator.of(context).pop();
                              },
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                side: const BorderSide(color: Color(0xFF3B82F6)),
                              ),
                              child: const Text(
                                "Cancel",
                                style: TextStyle(
                                  color: Color(0xFF3B82F6),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                _updateUserData();
                                Navigator.of(context).pop();
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF3B82F6),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text(
                                "Save",
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildEditField(String label, TextEditingController controller, {bool isDate = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF3B82F6)),
              ),
              suffixIcon: isDate ? IconButton(
                icon: const Icon(Icons.calendar_today, size: 20),
                onPressed: () async {
                  final DateTime? picked = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now(),
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) {
                    controller.text = "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
                  }
                },
              ) : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF64748B),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF1E293B),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return "${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}";
    } catch (e) {
      return dateString;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF3B82F6),
        foregroundColor: Colors.white,
        title: const Text(
          "Info",
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        elevation: 0,
        actions: [
          if (!isLoading && userData != null)
            IconButton(
              onPressed: () {
                _showEditDialog();
              },
              icon: const Icon(Icons.edit),
            ),
        ],
      ),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF3B82F6)),
              ),
            )
          : SingleChildScrollView(
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
                          children: [
                            CircleAvatar(
                              radius: 50,
                              backgroundColor:
                                  const Color(0xFF3B82F6).withOpacity(0.1),
                              child: const Icon(
                                Icons.person,
                                color: Color(0xFF3B82F6),
                                size: 50,
                              ),
                            ),
                            const SizedBox(height: 20),
                            _buildInfoItem("Full Name", userData?['fullName'] ?? "Not provided"),
                            _buildInfoItem("Driver ID", userData?['driverId'] ?? "Not provided"),
                            _buildInfoItem("Email", userData?['email'] ?? "Not provided"),
                            _buildInfoItem("Phone", userData?['phone'] ?? "Not provided"),
                            _buildInfoItem("License Number", userData?['driverLicenseInfo'] ?? "Not provided"),
                            _buildInfoItem("License Expiry", userData?['createdAt'] != null 
                                ? _formatDate("${DateTime.parse(userData!['createdAt']).year + 2}-${DateTime.parse(userData!['createdAt']).month.toString().padLeft(2, '0')}-${DateTime.parse(userData!['createdAt']).day.toString().padLeft(2, '0')}")
                                : "Not provided"),
                            _buildInfoItem("Employment Date", userData?['createdAt'] != null 
                                ? _formatDate(userData!['createdAt']) 
                                : "Not provided"),
                            _buildInfoItem("Status", userData?['status'] != null 
                                ? userData!['status'].toString().toUpperCase() 
                                : "UNKNOWN"),
                            const SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () {
                                  _showEditDialog();
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF3B82F6),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: 0,
                                ),
                                child: const Text(
                                  "Edit Information",
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
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
}