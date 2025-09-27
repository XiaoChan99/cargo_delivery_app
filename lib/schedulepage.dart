import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'homepage.dart';
import 'live_location_page.dart';
import 'container_details_page.dart';
import 'status_update_page.dart';
import 'livemap_page.dart';
import 'settings_page.dart';
import 'dart:convert';
import 'dart:typed_data';

class SchedulePage extends StatefulWidget {
  const SchedulePage({super.key});

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  Map<String, dynamic>? _userData;
  Uint8List? _cachedAvatarImage;
  String _licenseNumber = ''; // This will store the license number
  bool _isLoading = true;

  // Precompute today's date range for Firestore query
  late DateTime _startOfDay;
  late DateTime _endOfDay;

  @override
  void initState() {
    super.initState();
    _initDateRange();
    _loadUserData();
  }

  void _initDateRange() {
    final now = DateTime.now();
    _startOfDay = DateTime(now.year, now.month, now.day);
    _endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59);
  }

  Future<void> _loadUserData() async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        // Only check if user is a courier (remove shipper check)
        final courierDoc = await _firestore.collection('Couriers').doc(user.uid).get();
        
        if (courierDoc.exists) {
          final data = courierDoc.data() as Map<String, dynamic>;
          await _processUserData(data, 'courier');
          return;
        }
        
        // If user not found in couriers collection
        print('User not found in Couriers collection');
      }
    } catch (e) {
      print('Error loading user data: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _processUserData(Map<String, dynamic> data, String role) async {
    Uint8List? decodedImage;
    
    if (data['profile_image_base64'] != null && data['profile_image_base64'].toString().isNotEmpty) {
      try {
        decodedImage = await _decodeImage(data['profile_image_base64']);
        print('Profile image decoded successfully');
      } catch (e) {
        print('Failed to decode profile image: $e');
      }
    } else {
      print('No profile image data found or profile image is empty');
    }

    setState(() {
      _userData = data;
      _cachedAvatarImage = decodedImage;
      _licenseNumber = data['license_number'] ?? 'N/A'; // Get license number instead of role
    });
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'scheduled':
        return const Color(0xFF10B981);
      case 'in progress':
        return const Color(0xFFF59E0B);
      case 'delayed':
        return const Color(0xFFEF4444);
      case 'delivered':
        return const Color(0xFF10B981);
      case 'pending':
        return const Color(0xFF64748B);
      default:
        return const Color(0xFF64748B);
    }
  }

  String _formatTime(Timestamp timestamp) {
    final date = timestamp.toDate();
    final hour = date.hour % 12;
    final period = date.hour >= 12 ? 'PM' : 'AM';
    return '${hour == 0 ? 12 : hour}:${date.minute.toString().padLeft(2, '0')} $period';
  }

  String _formatDate(Timestamp timestamp) {
    final date = timestamp.toDate();
    final months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    final weekdays = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
    ];
    return '${weekdays[date.weekday - 1]} ${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  Future<Uint8List> _decodeImage(String imageData) async {
    try {
      // Handle different image data formats
      if (imageData.startsWith('data:image')) {
        // Data URI format: data:image/png;base64,...
        final commaIndex = imageData.indexOf(',');
        if (commaIndex != -1) {
          final base64Data = imageData.substring(commaIndex + 1);
          return base64Decode(base64Data);
        }
      }
      
      // Assume it's plain base64
      return base64Decode(imageData);
    } catch (e) {
      print('Error decoding image: $e');
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Use placeholders while loading
    final firstName = _userData?['first_name'] ?? 'First Name';
    final lastName = _userData?['last_name'] ?? 'Last Name';
    final fullName = _userData != null ? '$firstName $lastName' : 'Loading User...';
    final hasAvatarImage = _cachedAvatarImage != null && _cachedAvatarImage!.isNotEmpty;
    final licenseNumber = _licenseNumber.isNotEmpty ? _licenseNumber : 'Loading license...'; // Display license number

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                children: [
                  // Header with user info
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 30, 16, 20),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF1E40AF), Color(0xFF3B82F6)],
                      ),
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(16),
                        bottomRight: Radius.circular(16),
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                // Avatar with profile picture from database
                                hasAvatarImage
                                    ? CircleAvatar(
                                        radius: 20,
                                        backgroundImage: MemoryImage(_cachedAvatarImage!),
                                        backgroundColor: Colors.transparent,
                                      )
                                    : CircleAvatar(
                                        radius: 20,
                                        backgroundColor: Colors.white.withOpacity(0.2),
                                        child: const Icon(Icons.person, color: Colors.white, size: 20),
                                      ),
                                const SizedBox(width: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      fullName,
                                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
                                    ),
                                    Text(
                                      "License: $licenseNumber", // Display license number instead of role
                                      style: const TextStyle(fontSize: 12, color: Colors.white70),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          "Today's Schedule",
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Today's Schedule Section
                  StreamBuilder<QuerySnapshot>(
                    stream: _firestore
                        .collection('schedules')
                        .where('driverId', isEqualTo: _auth.currentUser?.uid)
                        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(_startOfDay))
                        .where('date', isLessThanOrEqualTo: Timestamp.fromDate(_endOfDay))
                        .orderBy('date')
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return _buildLoadingScheduleCards(2); // Optimistic UI
                      }

                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return _buildNoSchedule();
                      }

                      final schedules = snapshot.data!.docs;
                      final firstSchedule = schedules.first.data() as Map<String, dynamic>;
                      final scheduleDate = firstSchedule['date'] as Timestamp;

                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [Colors.white, Color(0xFFFAFBFF)]),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 20, offset: const Offset(0, 4)),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _formatDate(scheduleDate),
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF1E293B)),
                            ),
                            const SizedBox(height: 20),
                            ...schedules.map((doc) {
                              final schedule = doc.data() as Map<String, dynamic>;
                              return Column(
                                children: [
                                  _buildScheduleEntry(
                                    context,
                                    _formatTime(schedule['date'] as Timestamp),
                                    schedule['containerNo'] ?? 'N/A',
                                    schedule['pickupLocation'] ?? 'N/A',
                                    schedule['destination'] ?? 'N/A',
                                    schedule['status'] ?? 'pending',
                                    _getStatusColor(schedule['status'] ?? 'pending'),
                                    doc.id,
                                  ),
                                  const SizedBox(height: 16),
                                ],
                              );
                            }),
                          ],
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 16),

                  // Delivery History Section
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Colors.white, Color(0xFFFAFBFF)]),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 20, offset: const Offset(0, 4)),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              "Delivery History",
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF1E293B)),
                            ),
                            TextButton(
                              onPressed: () {},
                              child: const Text(
                                "View All",
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF3B82F6)),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        StreamBuilder<QuerySnapshot>(
                          stream: _firestore
                              .collection('delivery_history')
                              .where('driverId', isEqualTo: _auth.currentUser?.uid)
                              .orderBy('date', descending: true)
                              .limit(3)
                              .snapshots(),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState == ConnectionState.waiting) {
                              return _buildHistorySkeletons(2);
                            }

                            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                              return const Text(
                                'No delivery history',
                                style: TextStyle(color: Color(0xFF64748B)),
                              );
                            }

                            final history = snapshot.data!.docs;

                            return Column(
                              children: history.map((doc) {
                                final delivery = doc.data() as Map<String, dynamic>;
                                return Column(
                                  children: [
                                    _buildHistoryEntry(
                                      _formatDate(delivery['date'] as Timestamp),
                                      delivery['containerNo'] ?? 'N/A',
                                      '${delivery['pickupLocation']} → ${delivery['destination']}',
                                      delivery['status'] ?? 'delivered',
                                      _getStatusColor(delivery['status'] ?? 'delivered'),
                                    ),
                                    if (history.last != doc) const SizedBox(height: 12),
                                  ],
                                );
                              }).toList(),
                            );
                          },
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 100),
                ],
              ),
            ),
      bottomNavigationBar: _buildBottomNavigation(context, 1),
    );
  }

  // SKELETON UI HELPERS

  Widget _buildLoadingScheduleCards(int count) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Colors.white, Color(0xFFFAFBFF)]),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 20, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        children: List.generate(count, (index) => _buildSkeletonScheduleCard()),
      ),
    );
  }

  Widget _buildSkeletonScheduleCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(height: 16, width: 60, color: Colors.grey[300]),
              Container(height: 16, width: 80, color: Colors.grey[300]),
            ],
          ),
          const SizedBox(height: 8),
          Container(height: 16, width: 100, color: Colors.grey[300]),
          const SizedBox(height: 4),
          Container(height: 12, width: 120, color: Colors.grey[300]),
          Container(height: 12, width: 100, color: Colors.grey[300]),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Container(height: 36, color: Colors.grey[300]),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(height: 36, color: Colors.grey[300]),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHistorySkeletons(int count) {
    return Column(
      children: List.generate(count, (index) {
        return Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(height: 12, width: 80, color: Colors.grey[300]),
                        const SizedBox(height: 4),
                        Container(height: 14, width: 100, color: Colors.grey[300]),
                        const SizedBox(height: 2),
                        Container(height: 12, width: 140, color: Colors.grey[300]),
                      ],
                    ),
                  ),
                  Container(height: 16, width: 70, color: Colors.grey[300]),
                ],
              ),
            ),
            if (index < count - 1) const SizedBox(height: 12),
          ],
        );
      }),
    );
  }

  Widget _buildNoSchedule() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Colors.white, Color(0xFFFAFBFF)]),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 20, offset: const Offset(0, 4)),
        ],
      ),
      child: const Text(
        'No schedules for today',
        style: TextStyle(fontSize: 16, color: Color(0xFF64748B)),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildScheduleEntry(BuildContext context, String time, String container, String pickup, String destination, String status, Color statusColor, String scheduleId) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                time,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
              ),
              Row(
                children: [
                  Container(width: 8, height: 8, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text(
                    status,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: statusColor),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            container,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
          ),
          const SizedBox(height: 4),
          Text(
            pickup,
            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
          Text(
            destination,
            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF3B82F6),
                    side: const BorderSide(color: Color(0xFF3B82F6)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  onPressed: () {
                    Widget destinationPage;
                    if (status.toLowerCase() == "in progress") {
                      destinationPage = LiveLocationPage(
                        containerNo: container,
                        time: time,
                        pickup: pickup,
                        destination: destination,
                        status: status,
                      );
                    } else if (status.toLowerCase() == "scheduled" || status.toLowerCase() == "pending") {
                      destinationPage = ContainerDetailsPage(
                        containerNo: container,
                        time: time,
                        pickup: pickup,
                        destination: destination,
                        status: status,
                        // Pass Firestore doc id if available for deliveryDocId, else null
                      );
                    } else if (status.toLowerCase() == "delayed") {
                      destinationPage = StatusUpdatePage(
                        containerNo: container,
                        time: time,
                        pickup: pickup,
                        destination: destination,
                        currentStatus: status,
                      );
                    } else {
                      destinationPage = ContainerDetailsPage(
                        containerNo: container,
                        time: time,
                        pickup: pickup,
                        destination: destination,
                        status: status,
                      );
                    }
                    Navigator.push(context, MaterialPageRoute(builder: (context) => destinationPage));
                  },
                  child: const Text("View", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              ),
              if (status.toLowerCase() == "delayed") ...[
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3B82F6),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => StatusUpdatePage(
                            containerNo: container,
                            time: time,
                            pickup: pickup,
                            destination: destination,
                            currentStatus: status,
                          ),
                        ),
                      );
                    },
                    child: const Text("Status Update", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
  Widget _buildHistoryEntry(String date, String container, String route, String status, Color statusColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(date, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                const SizedBox(height: 4),
                Text(container, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1E293B))),
                const SizedBox(height: 2),
                Text(route, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
              ],
            ),
          ),
          Row(
            children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text(status, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: statusColor)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNavigation(BuildContext context, int currentIndex) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, -4)),
        ],
      ),
      child: BottomNavigationBar(
        currentIndex: currentIndex,
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        selectedItemColor: const Color(0xFF3B82F6),
        unselectedItemColor: const Color(0xFF64748B),
        selectedFontSize: 12,
        unselectedFontSize: 12,
        onTap: (index) {
          switch (index) {
            case 0:
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const HomePage()));
              break;
            case 1:
              break;
            case 2:
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LiveMapPage()));
              break;
            case 3:
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const SettingsPage()));
              break;
          }
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), activeIcon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.schedule_outlined), activeIcon: Icon(Icons.schedule), label: 'Schedule'),
          BottomNavigationBarItem(icon: Icon(Icons.map_outlined), activeIcon: Icon(Icons.map), label: 'Live Map'),
          BottomNavigationBarItem(icon: Icon(Icons.settings_outlined), activeIcon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}