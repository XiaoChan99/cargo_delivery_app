import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:convert';
class InfoPage extends StatefulWidget {
  const InfoPage({super.key});

  @override
  State<InfoPage> createState() => _InfoPageState();
}

class _InfoPageState extends State<InfoPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final ImagePicker _imagePicker = ImagePicker();
  
  Map<String, dynamic>? userData;
  bool isLoading = true;
  String? profileImageUrl;
  bool isUploadingImage = false;
  String deliveryStatus = 'Available'; // Default status
  int activeDeliveries = 0;

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

  // Enhanced method to fetch profile image with priority order
  String? _getProfileImageUrl(Map<String, dynamic>? data) {
    if (data == null) return null;
    
    // Priority order for profile image fields
    final List<String> imageFieldPriority = [
      'profileImageUrl',
      'photoURL',
      'profile_image',
      'imageUrl',
      'avatar',
      'profilePicture',
      'picture',
      'profile_image_base64', // Added for your database
    ];
    
    for (String field in imageFieldPriority) {
      final imageUrl = data[field]?.toString();
      if (imageUrl != null && imageUrl.isNotEmpty && imageUrl != 'null') {
        // Handle base64 images
        if (field == 'profile_image_base64' && imageUrl.startsWith('/9j/')) {
          return 'data:image/jpeg;base64,$imageUrl';
        }
        return imageUrl;
      }
    }
    
    // Fallback: Check if user has a photo URL in Firebase Auth
    final user = _auth.currentUser;
    if (user?.photoURL != null && user!.photoURL!.isNotEmpty) {
      return user.photoURL;
    }
    
    return null;
  }

  // Method to check delivery status from CargoDelivery collection
  Future<void> _checkDeliveryStatus() async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        // Query CargoDelivery for active deliveries for this courier
        final querySnapshot = await _firestore
            .collection('CargoDelivery')
            .where('courier_id', isEqualTo: user.uid)
            .where('status', whereIn: ['in-progress', 'accepted', 'picked-up', 'on-the-way'])
            .get();

        setState(() {
          activeDeliveries = querySnapshot.docs.length;
          deliveryStatus = activeDeliveries > 0 ? 'On Delivery' : 'Available';
        });

        // Update courier status in Firestore
        await _updateCourierStatus();
      }
    } catch (e) {
      print("Error checking delivery status: $e");
      setState(() {
        deliveryStatus = 'Available';
        activeDeliveries = 0;
      });
    }
  }

  // Update courier status in Firestore
  Future<void> _updateCourierStatus() async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        await _firestore.collection('Couriers').doc(user.uid).update({
          'status': deliveryStatus.toLowerCase(),
          'availability': deliveryStatus == 'On Delivery' ? 'busy' : 'available',
          'updated_at': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      print("Error updating courier status: $e");
    }
  }

  // Method to get status color
  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'available':
        return Colors.green;
      case 'on delivery':
        return Colors.orange;
      case 'offline':
        return Colors.grey;
      case 'pending approval':
        return Colors.amber;
      default:
        return Colors.blue;
    }
  }

  // Method to get status icon
  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'available':
        return Icons.check_circle;
      case 'on delivery':
        return Icons.local_shipping;
      case 'offline':
        return Icons.offline_bolt;
      case 'pending approval':
        return Icons.pending;
      default:
        return Icons.info;
    }
  }

  // Method to get delivery count badge
  Widget _getDeliveryBadge() {
    if (activeDeliveries == 0) return const SizedBox.shrink();
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.red,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        activeDeliveries.toString(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
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
            
            // Enhanced profile image fetching
            profileImageUrl = _getProfileImageUrl(userData);
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

          // Check delivery status
          await _checkDeliveryStatus();

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

  Future<void> _uploadProfileImage(File imageFile) async {
    try {
      setState(() {
        isUploadingImage = true;
      });

      final user = _auth.currentUser;
      if (user != null) {
        // Convert image to base64
        final bytes = await imageFile.readAsBytes();
        final base64Image = base64Encode(bytes);

        // Update Firestore with base64 image
        await _firestore.collection('Couriers').doc(user.uid).update({
          'profile_image_base64': base64Image,
          'updated_at': FieldValue.serverTimestamp(),
        });

        // Refresh data
        await _fetchUserData();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Profile image updated successfully"),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      print("Error uploading profile image: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed to upload profile image: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          isUploadingImage = false;
        });
      }
    }
  }

  Future<void> _pickImage() async {
    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 80,
      );

      if (pickedFile != null) {
        await _uploadProfileImage(File(pickedFile.path));
      }
    } catch (e) {
      print("Error picking image: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed to pick image: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showImageOptions() {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Choose from Gallery'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage();
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete),
                title: const Text('Remove Profile Picture'),
                onTap: () {
                  Navigator.pop(context);
                  _removeProfileImage();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _removeProfileImage() async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        await _firestore.collection('Couriers').doc(user.uid).update({
          'profile_image_base64': FieldValue.delete(),
          'updated_at': FieldValue.serverTimestamp(),
        });

        await _fetchUserData();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Profile image removed"),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      print("Error removing profile image: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed to remove profile image: $e"),
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

  Widget _buildInfoItem(String label, String value, {Color? valueColor, IconData? icon}) {
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
          if (icon != null) ...[
            Icon(
              icon,
              size: 18,
              color: valueColor ?? const Color(0xFF1E293B),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value.isEmpty ? "Not provided" : value,
                    style: TextStyle(
                      fontSize: 14,
                      color: valueColor ?? const Color(0xFF1E293B),
                      fontWeight: label == "Status" ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
                if (label == "Status" && activeDeliveries > 0) _getDeliveryBadge(),
              ],
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
    final statusColor = _getStatusColor(deliveryStatus);
    final statusIcon = _getStatusIcon(deliveryStatus);

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
                            // Enhanced Profile Image with upload functionality
                            Stack(
                              children: [
                                GestureDetector(
                                  onTap: _showImageOptions,
                                  child: CircleAvatar(
                                    radius: 50,
                                    backgroundColor: const Color(0xFF3B82F6).withOpacity(0.1),
                                    backgroundImage: profileImageUrl != null && profileImageUrl!.isNotEmpty
                                        ? (profileImageUrl!.startsWith('data:image/') 
                                            ? MemoryImage(base64Decode(profileImageUrl!.split(',').last))
                                            : NetworkImage(profileImageUrl!)) as ImageProvider?
                                        : null,
                                    child: isUploadingImage
                                        ? const CircularProgressIndicator(
                                            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF3B82F6)),
                                          )
                                        : profileImageUrl == null || profileImageUrl!.isEmpty
                                            ? const Icon(
                                                Icons.person,
                                                color: Color(0xFF3B82F6),
                                                size: 50,
                                              )
                                            : null,
                                  ),
                                ),
                                // Status indicator dot
                                Positioned(
                                  bottom: 4,
                                  right: 4,
                                  child: Container(
                                    width: 20,
                                    height: 20,
                                    decoration: BoxDecoration(
                                      color: statusColor,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                ),
                                // Edit icon overlay
                                Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: Container(
                                    width: 30,
                                    height: 30,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF3B82F6),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 2,
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.camera_alt,
                                      color: Colors.white,
                                      size: 14,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              "Tap to change photo",
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 20),
                            _buildInfoItem("First Name", userData?['first_name']?.toString() ?? ""),
                            _buildInfoItem("Last Name", userData?['last_name']?.toString() ?? ""),
                            _buildInfoItem("Email", userData?['email']?.toString() ?? ""),
                            _buildInfoItem("Phone", userData?['phone']?.toString() ?? ""),
                            _buildInfoItem("License Number", userData?['license_number']?.toString() ?? userData?['driverLicenseInfo']?.toString() ?? ""),
                            _buildInfoItem("License Expiry", _getLicenseExpiry()),
                            _buildInfoItem("Employment Date", _formatDisplayDate(userData?['created_at'] ?? userData?['createdAt'])),
                            _buildInfoItem(
                              "Status", 
                              deliveryStatus, 
                              valueColor: statusColor,
                              icon: statusIcon,
                            ),
                            if (activeDeliveries > 0) ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.local_shipping,
                                      color: Colors.orange[700],
                                      size: 16,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      "Active Deliveries: $activeDeliveries",
                                      style: TextStyle(
                                        color: Colors.orange[700],
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
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