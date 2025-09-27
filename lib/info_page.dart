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
  String? profileImageUrl;

  // Controllers for text fields
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _licenseNumberController = TextEditingController();
  final TextEditingController _licenseExpiryController = TextEditingController();

  // Helper method to convert dynamic date values to DateTime
  DateTime? _parseDate(dynamic dateValue) {
    if (dateValue == null) return null;
    
    if (dateValue is Timestamp) {
      return dateValue.toDate();
    } else if (dateValue is String) {
      try {
        return DateTime.parse(dateValue);
      } catch (e) {
        return null;
      }
    }
    return null;
  }

  // Helper method to format DateTime to string
  String _formatDateToString(DateTime? date) {
    if (date == null) return '';
    return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
  }

  @override
  void initState() {
    super.initState();
    _fetchUserData();
  }

  @override
  void dispose() {
    // Dispose all controllers to prevent memory leaks
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _licenseNumberController.dispose();
    _licenseExpiryController.dispose();
    super.dispose();
  }

  Future<void> _fetchUserData() async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        final doc = await _firestore.collection('Couriers').doc(user.uid).get();
        if (doc.exists) {
          // Use mounted check before setting state
          if (!mounted) return;
          
          setState(() {
            userData = doc.data()!;
            
            // Get profile image URL from Firestore document
            profileImageUrl = userData?['profileImageUrl']?.toString() ?? 
                            userData?['photoURL']?.toString() ?? 
                            userData?['profile_image']?.toString() ?? 
                            userData?['imageUrl']?.toString();
          });
          
          // Pre-fill the text controllers with existing data
          _firstNameController.text = userData?['first_name']?.toString() ?? '';
          _lastNameController.text = userData?['last_name']?.toString() ?? '';
          _emailController.text = userData?['email']?.toString() ?? '';
          _phoneController.text = userData?['phone']?.toString() ?? '';
          _licenseNumberController.text = userData?['license_number']?.toString() ?? userData?['driverLicenseInfo']?.toString() ?? '';
          
          // Handle date fields properly
          final createdAt = _parseDate(userData?['created_at'] ?? userData?['createdAt']);
          final licenseExpiry = _parseDate(userData?['license_expiry']);
          
          if (licenseExpiry != null) {
            _licenseExpiryController.text = _formatDateToString(licenseExpiry);
          } else if (createdAt != null) {
            // Calculate expiry as 2 years from creation
            final expiryDate = DateTime(createdAt.year + 2, createdAt.month, createdAt.day);
            _licenseExpiryController.text = _formatDateToString(expiryDate);
          }

          if (!mounted) return;
          setState(() {
            isLoading = false;
          });
        } else {
          if (!mounted) return;
          setState(() {
            isLoading = false;
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("No courier data found"),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      }
    } catch (e) {
      print("Error fetching user data: $e");
      if (!mounted) return;
      setState(() {
        isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed to load courier data: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _updateUserData() async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        // Parse the license expiry date
        DateTime? licenseExpiry;
        try {
          if (_licenseExpiryController.text.isNotEmpty) {
            licenseExpiry = DateTime.parse(_licenseExpiryController.text);
          }
        } catch (e) {
          print("Error parsing license expiry date: $e");
        }

        final updateData = {
          'first_name': _firstNameController.text.trim(),
          'last_name': _lastNameController.text.trim(),
          'email': _emailController.text.trim(),
          'phone': _phoneController.text.trim(),
          'license_number': _licenseNumberController.text.trim(),
          'updated_at': FieldValue.serverTimestamp(),
        };

        // Only add license_expiry if it's a valid date
        if (licenseExpiry != null) {
          updateData['license_expiry'] = Timestamp.fromDate(licenseExpiry);
        }

        await _firestore.collection('Couriers').doc(user.uid).update(updateData);

        // Refresh the data
        await _fetchUserData();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Information updated successfully"),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      print("Error updating courier data: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed to update information: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
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
                      _buildEditField("First Name", _firstNameController),
                      _buildEditField("Last Name", _lastNameController),
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
                    controller.text = _formatDateToString(picked);
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
              value.isEmpty ? "Not provided" : value,
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

  String _formatDisplayDate(dynamic dateValue) {
    final date = _parseDate(dateValue);
    if (date == null) return "Not provided";
    return "${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}";
  }

  String _getLicenseExpiry() {
    final licenseExpiry = _parseDate(userData?['license_expiry']);
    if (licenseExpiry != null) {
      return _formatDateToString(licenseExpiry);
    }
    
    final createdAt = _parseDate(userData?['created_at'] ?? userData?['createdAt']);
    if (createdAt != null) {
      final expiryDate = DateTime(createdAt.year + 2, createdAt.month, createdAt.day);
      return _formatDateToString(expiryDate);
    }
    
    return "Not provided";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF3B82F6),
        foregroundColor: Colors.white,
        title: const Text(
          "Courier Information",
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
                            // Profile Image with fallback to default avatar
                            CircleAvatar(
                              radius: 50,
                              backgroundColor: const Color(0xFF3B82F6).withOpacity(0.1),
                              backgroundImage: profileImageUrl != null && profileImageUrl!.isNotEmpty
                                  ? NetworkImage(profileImageUrl!)
                                  : null,
                              child: profileImageUrl == null || profileImageUrl!.isEmpty
                                  ? const Icon(
                                      Icons.person,
                                      color: Color(0xFF3B82F6),
                                      size: 50,
                                    )
                                  : null,
                            ),
                            const SizedBox(height: 20),
                            _buildInfoItem("First Name", userData?['first_name']?.toString() ?? ""),
                            _buildInfoItem("Last Name", userData?['last_name']?.toString() ?? ""),
                            _buildInfoItem("Courier ID", userData?['driverId']?.toString() ?? userData?['courierId']?.toString() ?? ""),
                            _buildInfoItem("Email", userData?['email']?.toString() ?? ""),
                            _buildInfoItem("Phone", userData?['phone']?.toString() ?? ""),
                            _buildInfoItem("License Number", userData?['license_number']?.toString() ?? userData?['driverLicenseInfo']?.toString() ?? ""),
                            _buildInfoItem("License Expiry", _getLicenseExpiry()),
                            _buildInfoItem("Employment Date", _formatDisplayDate(userData?['created_at'] ?? userData?['createdAt'])),
                            _buildInfoItem("Status", userData?['status']?.toString().toUpperCase() ?? "UNKNOWN"),
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