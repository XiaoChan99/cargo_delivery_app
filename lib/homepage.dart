import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';
import 'schedulepage.dart';
import 'livemap_page.dart';
import 'settings_page.dart';
import 'container_details_page.dart';
import 'notifications_page.dart';
import 'live_location_page.dart';
import 'analytics_page.dart'; // Add analytics page import

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with AutoRefreshMixin {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  User? _currentUser;
  Map<String, dynamic> _userData = {};
  bool _isLoading = true;
  String? _errorMessage;
  
  // Notification badge state
  bool _hasUnreadNotifications = false;
  StreamSubscription? _notificationSubscription;

  // Image slider
  final PageController _pageController = PageController();
  final List<String> _sliderImages = [
    'https://images.unsplash.com/photo-1601055929638-63c8b8e7cdeb?w=800&auto=format&fit=crop&q=60&ixlib=rb-4.0.3',
    'https://images.unsplash.com/photo-1586528116311-ad8dd3c8310d?w=800&auto=format&fit=crop&q=60&ixlib=rb-4.0.3',
    'https://images.unsplash.com/photo-1556742111-a301076d9dab?w=800&auto=format&fit=crop&q=60&ixlib=rb-4.0.3',
  ];
  int _currentPage = 0;
  Timer? _autoSlideTimer;

  // Cargo Lists
  List<Map<String, dynamic>> _availableCargos = [];
  List<Map<String, dynamic>> _inProgressDeliveries = [];

  @override
  void initState() {
    super.initState();
    _currentUser = _auth.currentUser;
    if (_currentUser != null) {
      _loadData();
      setupCargoListener(_loadAvailableCargos);
      setupDeliveryListener(_currentUser!.uid, _loadInProgressDeliveries);
      _setupNotificationListener();
      _startAutoSlide();
    } else {
      _isLoading = false;
      _errorMessage = "User not authenticated";
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _autoSlideTimer?.cancel();
    _notificationSubscription?.cancel();
    super.dispose();
  }

  void _setupNotificationListener() {
    if (_currentUser == null) return;
    
    _notificationSubscription = _firestore
        .collection('Notifications')
        .where('userId', isEqualTo: _currentUser!.uid)
        .where('read', isEqualTo: false)
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        setState(() {
          _hasUnreadNotifications = snapshot.docs.isNotEmpty;
        });
      }
    });
  }

  void _startAutoSlide() {
    _autoSlideTimer?.cancel();
    _autoSlideTimer = Timer.periodic(const Duration(seconds: 5), (Timer timer) {
      if (_pageController.hasClients) {
        if (_currentPage < _sliderImages.length - 1) {
          _currentPage++;
        } else {
          _currentPage = 0;
        }
        _pageController.animateToPage(
          _currentPage,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  Future<void> _loadData() async {
    try {
      await Future.wait([
        _loadUserData(),
        _loadAvailableCargos(),
        _loadInProgressDeliveries(),
      ]);
    } catch (e) {
      setState(() {
        _errorMessage = "Error loading data: ${e.toString()}";
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // ...existing code...
  Future<void> _loadAvailableCargos() async {
    try {
      print('Loading available cargos...');
      
      QuerySnapshot cargoSnapshot = await _firestore
          .collection('Cargo')
          .orderBy('created_at', descending: true)
          .get();

      QuerySnapshot deliverySnapshot = await _firestore
          .collection('CargoDelivery')
          .get();

      Set<String> assignedCargoIds = {};
      for (var doc in deliverySnapshot.docs) {
        var deliveryData = doc.data() as Map<String, dynamic>;
        if (deliveryData['cargo_id'] != null) {
          assignedCargoIds.add(deliveryData['cargo_id'].toString());
        }
      }

      List<Map<String, dynamic>> availableCargos = [];
      for (var doc in cargoSnapshot.docs) {
        var cargoData = doc.data() as Map<String, dynamic>;
        final status = cargoData['status']?.toString().toLowerCase() ?? 'pending';

        // Only include cargos that are not assigned to any delivery and not delayed
        if (!assignedCargoIds.contains(doc.id) && status != 'delayed') {
          Map<String, dynamic> combinedData = {
            'cargo_id': doc.id,
            'containerNo': 'CONT-${cargoData['item_number']?.toString() ?? 'N/A'}',
            'status': cargoData['status']?.toString() ?? 'pending',
            'pickupLocation': cargoData['origin']?.toString() ?? 'Port Terminal',
            'destination': cargoData['destination']?.toString() ?? 'Delivery Point',
            'created_at': cargoData['created_at'],
            'description': cargoData['description']?.toString() ?? 'N/A',
            'weight': cargoData['weight'] ?? 0.0,
            'value': cargoData['value'] ?? 0.0,
            'hs_code': cargoData['hs_code']?.toString() ?? 'N/A',
            'quantity': cargoData['quantity'] ?? 0,
            'item_number': cargoData['item_number'] ?? 0,
            'additional_info': cargoData['additional_info']?.toString() ?? '',
            'submanifest_id': cargoData['submanifest_id']?.toString() ?? '',
          };
          availableCargos.add(combinedData);
        }
      }

      setState(() {
        _availableCargos = availableCargos;
      });
      
      print('Found ${_availableCargos.length} available cargos');
    } catch (e) {
      print('Error loading available cargos: $e');
    }
  }

  Future<void> _loadInProgressDeliveries() async {
    try {
      print('Loading in-progress deliveries...');
      
      QuerySnapshot deliverySnapshot = await _firestore
          .collection('CargoDelivery')
          .where('courier_id', isEqualTo: _currentUser!.uid)
          .get();

      List<Map<String, dynamic>> inProgressDeliveries = [];
      
      for (var doc in deliverySnapshot.docs) {
        var deliveryData = doc.data() as Map<String, dynamic>;
        String status = deliveryData['status']?.toString().toLowerCase() ?? '';
        
        // Only include in-progress, in_transit, assigned, or delayed statuses
        if (status == 'in-progress' || status == 'in_transit' || status == 'assigned' || status == 'delayed') {
          try {
            DocumentSnapshot cargoDoc = await _firestore
                .collection('Cargo')
                .doc(deliveryData['cargo_id'].toString())
                .get();

            if (cargoDoc.exists) {
              var cargoData = cargoDoc.data() as Map<String, dynamic>;
              
              Map<String, dynamic> combinedData = {
                'delivery_id': doc.id,
                'cargo_id': deliveryData['cargo_id'],
                'containerNo': 'CONT-${cargoData['item_number'] ?? 'N/A'}',
                'status': deliveryData['status'] ?? 'in-progress',
                'pickupLocation': cargoData['origin'] ?? 'Port Terminal',
                'destination': cargoData['destination'] ?? 'Delivery Point',
                'confirmed_at': deliveryData['confirmed_at'],
                'courier_id': deliveryData['courier_id'],
                'description': cargoData['description'] ?? 'N/A',
                'weight': cargoData['weight'] ?? 0.0,
                'value': cargoData['value'] ?? 0.0,
                'hs_code': cargoData['hs_code'] ?? 'N/A',
                'quantity': cargoData['quantity'] ?? 0,
                'item_number': cargoData['item_number'] ?? 0,
                'proof_image': deliveryData['proof_image'],
                'confirmed_by': deliveryData['confirmed_by'],
              };
              inProgressDeliveries.add(combinedData);
            }
          } catch (e) {
            print('Error loading cargo details for delivery: $e');
          }
        }
      }

      setState(() {
        _inProgressDeliveries = inProgressDeliveries;
      });
      
      print('Found ${_inProgressDeliveries.length} in-progress deliveries');
    } catch (e) {
      print('Error loading in-progress deliveries: $e');
    }
  }

  Future<void> _loadUserData() async {
    if (_currentUser != null) {
      try {
        DocumentSnapshot courierDoc = await _firestore
            .collection('Couriers')
            .doc(_currentUser!.uid)
            .get();

        if (courierDoc.exists) {
          setState(() {
            _userData = courierDoc.data() as Map<String, dynamic>;
          });
          return;
        }
      } catch (e) {
        print('Error loading user profile: $e');
      }
    }
  }

  // Accept a cargo delivery
  Future<void> _acceptCargoDelivery(Map<String, dynamic> cargoData) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        _showErrorModal('User not authenticated');
        return;
      }

      // Create CargoDelivery document with correct field names
      await _firestore.collection('CargoDelivery').add({
        'cargo_id': cargoData['cargo_id'],
        'courier_id': user.uid,
        'status': 'in-progress',
        'confirmed_at': Timestamp.now(),
        'confirmed_by': 'courier',
        'proof_image': '',
        'remarks': 'Accepted by courier',
      });

      // Update cargo status
      await _firestore.collection('Cargo').doc(cargoData['cargo_id']).update({
        'status': 'in-progress',
        'updated_at': Timestamp.now(),
      });

      // Create notification for admin
      try {
        await _firestore.collection('Notifications').add({
          'userId': 'admin',
          'type': 'delivery_assigned',
          'message': 'Cargo ${cargoData['containerNo']} has been accepted by ${_getFullName()}',
          'timestamp': Timestamp.now(),
          'read': false,
          'cargoId': cargoData['cargo_id'],
          'containerNo': cargoData['containerNo'],
        });
      } catch (e) {
        print('Error creating notification: $e');
      }

      // Refresh data
      await _loadData();
      
      _showSuccessModal('Cargo accepted successfully!');
    } catch (e) {
      print('Error accepting cargo: $e');
      _showErrorModal('Failed to accept cargo. Please try again.');
    }
  }

  String _getFullName() {
    String firstName = _userData['first_name'] ?? '';
    String lastName = _userData['last_name'] ?? '';
    if (firstName.isNotEmpty && lastName.isNotEmpty) {
      return '$firstName $lastName';
    } else if (firstName.isNotEmpty) {
      return firstName;
    } else if (lastName.isNotEmpty) {
      return lastName;
    } else {
      return 'Driver';
    }
  }

  String _getDriverId() {
    return _userData['driverId'] ?? _userData['license_number'] ?? 'N/A';
  }

  String _getCourierStatus() {
    return _inProgressDeliveries.isNotEmpty ? 'On Delivery' : 'Available';
  }

  Widget _getProfileWidget() {
    String? profileImageBase64 = _userData['profile_image_base64'];
    if (profileImageBase64 != null && profileImageBase64.isNotEmpty) {
      if (profileImageBase64.contains('base64,')) {
        profileImageBase64 = profileImageBase64.split('base64,').last;
      }
      try {
        return CircleAvatar(
          radius: 30,
          backgroundImage: MemoryImage(base64Decode(profileImageBase64)),
        );
      } catch (e) {
        return _buildDefaultProfile();
      }
    } else {
      return _buildDefaultProfile();
    }
  }

  Widget _buildDefaultProfile() {
    return CircleAvatar(
      radius: 30,
      backgroundColor: Colors.white.withOpacity(0.2),
      child: const Icon(
        Icons.person,
        color: Colors.white,
        size: 30,
      ),
    );
  }

  String _getCargoStatusText(String status) {
    switch (status.toLowerCase()) {
      case 'scheduled':
        return 'Scheduled';
      case 'pending':
        return 'Pending';
      case 'assigned':
        return 'Assigned';
      case 'in-progress':
      case 'in_transit':
        return 'In Progress';
      case 'delivered':
        return 'Delivered';
      case 'delayed':
        return 'Delayed';
      default:
        return status;
    }
  }

  Color _getCargoStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'scheduled':
        return const Color(0xFF3B82F6);
      case 'pending':
        return const Color(0xFFF59E0B);
      case 'assigned':
        return const Color(0xFF8B5CF6);
      case 'in-progress':
      case 'in_transit':
        return const Color(0xFF6366F1);
      case 'delivered':
        return const Color(0xFF10B981);
      case 'delayed':
        return const Color(0xFFEF4444);
      default:
        return const Color(0xFF64748B);
    }
  }

  String _formatTimeAgo(Timestamp timestamp) {
    final now = DateTime.now();
    final time = timestamp.toDate();
    final difference = now.difference(time);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${time.day}/${time.month}/${time.year}';
    }
  }

  void _showSuccessModal(String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.check_circle,
                  color: Color(0xFF10B981),
                  size: 64,
                ),
                const SizedBox(height: 16),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3B82F6),
                    minimumSize: const Size(120, 48),
                  ),
                  child: const Text('OK'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showErrorModal(String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error,
                  color: Color(0xFFEF4444),
                  size: 64,
                ),
                const SizedBox(height: 16),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3B82F6),
                    minimumSize: const Size(120, 48),
                  ),
                  child: const Text('OK'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildNotificationIcon() {
    return Stack(
      children: [
        const Icon(Icons.notifications, color: Colors.white, size: 24),
        if (_hasUnreadNotifications)
          Positioned(
            right: 0,
            top: 0,
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _loadData,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Header with gradient background
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 40, 16, 20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF1E40AF),
                    Color(0xFF3B82F6),
                  ],
                ),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // App title with icon
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.local_shipping_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "CARGO EXPRESS",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: 1.1,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            "Fast Delivery",
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  
                  // Notification icon with badge
                  IconButton(
                    icon: _buildNotificationIcon(),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => NotificationsPage(userId: _currentUser!.uid),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

            // Profile Section (removed box shadow)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF1E40AF),
                    Color(0xFF3B82F6),
                  ],
                ),
                borderRadius: BorderRadius.all(Radius.circular(16)),
              ),
              child: Row(
                children: [
                  // Profile Image
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                    ),
                    child: _getProfileWidget(),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Name with icon
                        Row(
                          children: [
                            const Icon(
                              Icons.person_outline,
                              color: Colors.white,
                              size: 18,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _getFullName(),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        
                        // License No with icon
                        Row(
                          children: [
                            const Icon(
                              Icons.badge_outlined,
                              color: Colors.white70,
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              "License No: ${_getDriverId()}",
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        
                        // Status with icon
                        Row(
                          children: [
                            Icon(
                              _inProgressDeliveries.isNotEmpty 
                                  ? Icons.delivery_dining 
                                  : Icons.check_circle_outline,
                              color: Colors.white,
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white.withOpacity(0.3)),
                              ),
                              child: Text(
                                _getCourierStatus(),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // Image Slider
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              height: 150,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Stack(
                children: [
                  PageView.builder(
                    controller: _pageController,
                    itemCount: _sliderImages.length,
                    onPageChanged: (int page) {
                      setState(() {
                        _currentPage = page;
                      });
                    },
                    itemBuilder: (context, index) {
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.network(
                          _sliderImages[index],
                          fit: BoxFit.cover,
                          width: double.infinity,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return Container(
                              decoration: BoxDecoration(
                                color: Colors.grey[300],
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Center(
                                child: CircularProgressIndicator(),
                              ),
                            );
                          },
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              decoration: BoxDecoration(
                                color: Colors.grey[300],
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Center(
                                child: Icon(Icons.error, color: Colors.grey),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                  Positioned(
                    bottom: 10,
                    left: 0,
                    right: 0,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(_sliderImages.length, (index) {
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: _currentPage == index ? 20 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: _currentPage == index ? BoxShape.rectangle : BoxShape.circle,
                            borderRadius: _currentPage == index ? BorderRadius.circular(4) : null,
                            color: _currentPage == index ? Colors.white : Colors.white.withOpacity(0.5),
                          ),
                        );
                      }),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Cargos and Track Section (removed box shadow)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: _buildActionCard(
                      "Cargos",
                      Icons.local_shipping,
                      const Color(0xFF3B82F6),
                      _availableCargos.length.toString(),
                      () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const SchedulePage()),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildActionCard(
                      "Track",
                      Icons.track_changes,
                      const Color(0xFF10B981),
                      _inProgressDeliveries.length.toString(),
                      () {
                        if (_inProgressDeliveries.isNotEmpty) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const LiveMapPage()),
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('No in-progress deliveries to track'),
                              backgroundColor: Color(0xFFF59E0B),
                            ),
                          );
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Order History and Performance Section (without Reports title)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: _buildReportItem("Order History", Icons.history, const Color(0xFF3B82F6)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildReportItem("Performance", Icons.assessment, const Color(0xFFF59E0B), onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => AnalyticsPage(userId: _currentUser!.uid)),
                      );
                    }),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Available Cargos Section
            if (_availableCargos.isNotEmpty)
              _buildCargoSection(
                "Available Deliveries",
                _availableCargos,
                _availableCargos.length,
                true, // isAvailable
              ),

            const SizedBox(height: 20),

            // In Progress Deliveries Section
            if (_inProgressDeliveries.isNotEmpty)
              _buildCargoSection(
                "Track Your Deliveries",
                _inProgressDeliveries,
                _inProgressDeliveries.length,
                false, // isAvailable
              ),

            const SizedBox(height: 100),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNavigation(context, 0),
    );
  }

  Widget _buildActionCard(String title, IconData icon, Color color, String count, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, color: color, size: 24),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      count,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title == "Cargos" ? "Available for delivery" : "Track your cargo",
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReportItem(String title, IconData icon, Color color, {VoidCallback? onTap}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCargoSection(String title, List<Map<String, dynamic>> deliveries, int count, bool isAvailable) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1E293B),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF3B82F6).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  count.toString(),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF3B82F6),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...deliveries.take(3).map((delivery) {
            return Column(
              children: [
                _buildCargoDeliveryCard(delivery, isAvailable),
                if (deliveries.indexOf(delivery) < deliveries.length - 1 && deliveries.indexOf(delivery) < 2)
                  const SizedBox(height: 12),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildCargoDeliveryCard(Map<String, dynamic> delivery, bool isAvailable) {
    // Check if this delivery is already accepted/in-progress
    final status = delivery['status']?.toString().toLowerCase() ?? 'pending';
    final bool isAlreadyAccepted = status == 'in-progress' || 
                                  status == 'in_transit' || 
                                  status == 'assigned';
    
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
              Expanded(
                child: Text(
                  "Container: ${delivery['containerNo'] ?? 'N/A'}",
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _getCargoStatusColor(delivery['status'] ?? 'pending').withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _getCargoStatusText(delivery['status'] ?? 'pending'),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _getCargoStatusColor(delivery['status'] ?? 'pending'),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.location_on_outlined, size: 16, color: Color(0xFF64748B)),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  "${delivery['pickupLocation'] ?? 'Port Terminal'} → ${delivery['destination'] ?? 'Delivery Point'}",
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF64748B),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.access_time_outlined, size: 16, color: Color(0xFF64748B)),
              const SizedBox(width: 4),
              Text(
                delivery['created_at'] != null
                    ? _formatTimeAgo(delivery['created_at'])
                    : delivery['confirmed_at'] != null
                        ? _formatTimeAgo(delivery['confirmed_at'])
                        : 'Recently',
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF64748B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    final status = delivery['status']?.toString().toLowerCase() ?? 'pending';
                    
                    if (status == 'in-progress' || status == 'in_transit') {
                      // Navigate to live location for in-progress deliveries
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => LiveLocationPage(
                            cargoData: delivery,
                          ),
                        ),
                      );
                    } else {
                      // Navigate to container details for available/pending deliveries
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ContainerDetailsPage(
                            containerData: delivery,
                            isAvailable: isAvailable,
                          ),
                        ),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3B82F6),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text(
                    status == 'in-progress' || status == 'in_transit' ? 'Track Now' : 'View Details',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              if (isAvailable && !isAlreadyAccepted)
                const SizedBox(width: 8),
              if (isAvailable && !isAlreadyAccepted)
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _acceptCargoDelivery(delivery),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text(
                      'Accept',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
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
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
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
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const HomePage()),
              );
              break;
            case 1:
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const SchedulePage()),
              );
              break;
            case 2:
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const LiveMapPage()),
              );
              break;
            case 3:
              // Already on Settings page
              break;
          }
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.schedule_outlined),
            activeIcon: Icon(Icons.schedule),
            label: 'Schedule',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.map_outlined),
            activeIcon: Icon(Icons.map),
            label: 'Live Map',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            activeIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

}

mixin AutoRefreshMixin<T extends StatefulWidget> on State<T> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _startAutoRefresh() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) {
        _refreshData();
      }
    });
  }

  void _refreshData() {
    // This method should be implemented by the parent class
    if (this is _HomePageState) {
      (this as _HomePageState)._loadData();
    }
  }
}

void setupCargoListener(Function refreshCallback) {
  FirebaseFirestore.instance
      .collection('Cargo')
      .snapshots()
      .listen((_) => refreshCallback());
}

void setupDeliveryListener(String userId, Function refreshCallback) {
  FirebaseFirestore.instance
      .collection('CargoDelivery')
      .where('courier_id', isEqualTo: userId)
      .snapshots()
      .listen((_) => refreshCallback());
}