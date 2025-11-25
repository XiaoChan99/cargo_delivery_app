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
import 'order_history_page.dart';

const String DECLARED_ORIGIN = "Don Carlos A. Gothong Port Centre, Quezon Boulevard, Pier 4, Cebu City.";

// Add the AutoRefreshMixin if it's missing
mixin AutoRefreshMixin<T extends StatefulWidget> on State<T> {
  void setupContainerListener(Function callback) {
    // Implement your real-time listener here
    FirebaseFirestore.instance
        .collection('Containers')
        .snapshots()
        .listen((_) => callback());
  }

  void setupDeliveryListener(String userId, Function callback) {
    // Implement your real-time delivery listener here
    FirebaseFirestore.instance
        .collection('ContainerDelivery')
        .where('courier_id', isEqualTo: userId)
        .snapshots()
        .listen((_) => callback());
  }
}

class SchedulePage extends StatefulWidget {
  const SchedulePage({super.key});

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> with AutoRefreshMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  Map<String, dynamic>? _userData;
  Uint8List? _cachedAvatarImage;
  String _licenseNumber = '';
  bool _isLoading = true;

  List<Map<String, dynamic>> _availableContainers = [];
  List<Map<String, dynamic>> _inProgressDeliveries = [];
  
  // Filter variables
  String _selectedStatusFilter = 'All';
  final List<String> _statusFilters = [
    'All',
    'Pending',
    'Accepted',
    'Scheduled',
    'Assigned',
    'In Progress',
    'In Transit',
    'Delayed',
    'Delivered',
    'Confirmed',
    'Cancelled'
  ];

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadContainerData();
    _setupRealTimeListeners();
  }

  Future<void> _loadUserData() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      DocumentSnapshot userDoc = await _firestore.collection('Couriers').doc(user.uid).get();
      if (userDoc.exists) {
        var userData = userDoc.data() as Map<String, dynamic>;
        String role = userData['role']?.toString() ?? 'courier';
        await _processUserData(userData, role);
      }
    } catch (e) {
      print('Error loading user data: $e');
    }
  }

  void _setupRealTimeListeners() {
    setupContainerListener(_loadAvailableContainers);
    if (_auth.currentUser != null) {
      setupDeliveryListener(_auth.currentUser!.uid, _loadInProgressDeliveries);
    }
  }

  Future<void> _loadContainerData() async {
    try {
      await Future.wait([
        _loadAvailableContainers(),
        _loadInProgressDeliveries(),
      ]);
    } catch (e) {
      print('Error loading container data: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadAvailableContainers() async {
    try {
      print('=== DEBUG SchedulePage: Loading available containers ===');
      
      QuerySnapshot containerSnapshot = await _firestore
          .collection('Containers')
          .orderBy('dateCreated', descending: true)
          .get();

      print('DEBUG: Found ${containerSnapshot.docs.length} total containers');
      
      QuerySnapshot deliverySnapshot = await _firestore
          .collection('ContainerDelivery')
          .get();

      print('DEBUG: Found ${deliverySnapshot.docs.length} delivery records');
      
      Set<String> assignedContainerIds = {};
      Map<String, String> containerDeliveryStatus = {};
      Map<String, String> containerDeliveryCourier = {};
      
      for (var doc in deliverySnapshot.docs) {
        var deliveryData = doc.data() as Map<String, dynamic>;
        String? containerId = deliveryData['containerId'] ?? deliveryData['container_id'];
        if (containerId != null) {
          assignedContainerIds.add(containerId.toString());
          containerDeliveryStatus[containerId.toString()] = deliveryData['status']?.toString().toLowerCase() ?? '';
          containerDeliveryCourier[containerId.toString()] = deliveryData['courier_id']?.toString() ?? '';
          print('DEBUG Delivery: Container $containerId has status: ${deliveryData['status']}');
        }
      }

      List<Map<String, dynamic>> availableContainers = [];
      for (var doc in containerSnapshot.docs) {
        var containerData = doc.data() as Map<String, dynamic>;
        String containerId = doc.id;
        
        // Get allocation status
        String allocationStatus = (containerData['allocationStatus']?.toString().toLowerCase() ?? '').trim();
        String deliveryStatus = containerDeliveryStatus[containerId] ?? '';
        String deliveryCourier = containerDeliveryCourier[containerId] ?? '';
        final currentUserId = _auth.currentUser?.uid;

        print('DEBUG Processing: $containerId');
        print('  - Allocation status: "$allocationStatus"');
        print('  - Delivery status: "$deliveryStatus"');
        print('  - Delivery courier: "$deliveryCourier"');
        print('  - Current user: "$currentUserId"');

        // Only include containers that are RELEASED and not assigned OR have cancelled/delayed status but only if not assigned to current user
        bool shouldInclude = false;
        if (allocationStatus == 'released') {
          if (!assignedContainerIds.contains(containerId)) {
            // Container not assigned to anyone - include it
            shouldInclude = true;
          } else if (deliveryStatus == 'cancelled' || deliveryStatus == 'delayed') {
            // For cancelled/delayed status, only include if NOT assigned to current user
            // This prevents duplicates - if current user has this container, it will appear in inProgressDeliveries
            if (deliveryCourier != currentUserId) {
              shouldInclude = true;
            }
          }
        }

        print('  - Should include: $shouldInclude');

        if (shouldInclude) {
          Map<String, dynamic> combinedData = {
            'containerId': containerId,
            'containerNumber': containerData['containerNumber']?.toString() ?? 'N/A',
            'sealNumber': containerData['sealNumber']?.toString() ?? 'N/A',
            'billOfLading': containerData['billOfLading']?.toString() ?? 'N/A',
            'consigneeName': containerData['consignedName']?.toString() ?? 'N/A',
            'consigneeAddress': containerData['consignedAddress']?.toString() ?? 'N/A',
            'consignorName': containerData['consignorName']?.toString() ?? 'N/A',
            'consignorAddress': containerData['consignorAddress']?.toString() ?? 'N/A',
            'priority': containerData['priority']?.toString() ?? 'normal',
            'deliveredBy': containerData['deliveredBy']?.toString() ?? '',
            'voyageId': containerData['voyageId']?.toString() ?? '',
            'location': DECLARED_ORIGIN,
            'destination': containerData['destination']?.toString() ?? 'Delivery Point',
            'cargoType': containerData['cargoType']?.toString() ?? 'General',
            'status': deliveryStatus.isNotEmpty ? deliveryStatus : 'pending',
            'allocationStatus': allocationStatus,
            'created_at': containerData['dateCreated'],
            'is_cancelled': deliveryStatus == 'cancelled',
          };
          availableContainers.add(combinedData);
          print('  ✓ ADDED container: $containerId');
        } else {
          print('  ✗ SKIPPED container: $containerId');
        }
      }

      setState(() {
        _availableContainers = availableContainers;
      });
      
      print('=== DEBUG SchedulePage: Found ${_availableContainers.length} available containers ===');
    } catch (e) {
      print('Error loading available containers: $e');
      setState(() {
        _availableContainers = [];
      });
    }
  }

  Future<void> _loadInProgressDeliveries() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      QuerySnapshot deliverySnapshot = await _firestore
          .collection('ContainerDelivery')
          .where('courier_id', isEqualTo: user.uid)
          .get();

      List<Map<String, dynamic>> inProgressDeliveries = [];
      
      for (var doc in deliverySnapshot.docs) {
        var deliveryData = doc.data() as Map<String, dynamic>;
        String status = deliveryData['status']?.toString().toLowerCase() ?? '';
        
        // EXCLUDE delivered/confirmed containers - they should disappear from this page
        if (status.isNotEmpty && status != 'delivered' && status != 'confirmed') {
          try {
            String? containerId = deliveryData['containerId'] ?? deliveryData['container_id'];
            if (containerId == null) continue;

            DocumentSnapshot containerDoc = await _firestore
                .collection('Containers')
                .doc(containerId.toString())
                .get();

            if (containerDoc.exists) {
              var containerData = containerDoc.data() as Map<String, dynamic>;
              
              Map<String, dynamic> combinedData = {
                'delivery_id': doc.id,
                'containerId': containerId,
                'containerNumber': containerData['containerNumber']?.toString() ?? 'N/A',
                'sealNumber': containerData['sealNumber']?.toString() ?? 'N/A',
                'billOfLading': containerData['billOfLading']?.toString() ?? 'N/A',
                'consigneeName': containerData['consignedName']?.toString() ?? 'N/A',
                'consigneeAddress': containerData['consignedAddress']?.toString() ?? 'N/A',
                'consignorName': containerData['consignorName']?.toString() ?? 'N/A',
                'consignorAddress': containerData['consignorAddress']?.toString() ?? 'N/A',
                'priority': containerData['priority']?.toString() ?? 'normal',
                'deliveredBy': containerData['deliveredBy']?.toString() ?? '',
                'voyageId': containerData['voyageId']?.toString() ?? '',
                'location': DECLARED_ORIGIN,
                'destination': containerData['destination']?.toString() ?? 'Delivery Point',
                'cargoType': containerData['cargoType']?.toString() ?? 'General',
                'status': deliveryData['status'] ?? 'pending',
                'confirmed_at': deliveryData['confirmed_at'],
                'courier_id': deliveryData['courier_id'],
                'proof_image': deliveryData['proof_image'],
                'confirmed_by': deliveryData['confirmed_by'],
                'remarks': deliveryData['remarks'],
              };
              inProgressDeliveries.add(combinedData);
            }
          } catch (e) {
            print('Error loading container details for delivery: $e');
          }
        }
      }

      setState(() {
        _inProgressDeliveries = inProgressDeliveries;
      });
    } catch (e) {
      print('Error loading in-progress deliveries: $e');
    }
  }

  // Filter containers based on selected status
  List<Map<String, dynamic>> _getFilteredAvailableContainers() {
    if (_selectedStatusFilter == 'All') {
      return _availableContainers;
    }
    
    return _availableContainers.where((container) {
      final containerStatus = container['status']?.toString().toLowerCase() ?? '';
      final filterStatus = _selectedStatusFilter.toLowerCase();
      
      // Handle multiple status names that represent the same state
      if (filterStatus == 'in progress' || filterStatus == 'in transit') {
        return containerStatus == 'in progress' || 
               containerStatus == 'in-progress' || 
               containerStatus == 'in_transit';
      }
      
      return containerStatus == filterStatus;
    }).toList();
  }

  List<Map<String, dynamic>> _getFilteredInProgressDeliveries() {
    if (_selectedStatusFilter == 'All') {
      return _inProgressDeliveries;
    }
    
    return _inProgressDeliveries.where((delivery) {
      final deliveryStatus = delivery['status']?.toString().toLowerCase() ?? '';
      final filterStatus = _selectedStatusFilter.toLowerCase();
      
      // Handle multiple status names that represent the same state
      if (filterStatus == 'in progress' || filterStatus == 'in transit') {
        return deliveryStatus == 'in progress' || 
               deliveryStatus == 'in-progress' || 
               deliveryStatus == 'in_transit';
      }
      
      return deliveryStatus == filterStatus;
    }).toList();
  }

  Future<void> _processUserData(Map<String, dynamic> data, String role) async {
    Uint8List? decodedImage;
    
    if (data['profile_image_base64'] != null && data['profile_image_base64'].toString().isNotEmpty) {
      try {
        decodedImage = await _decodeImage(data['profile_image_base64']);
      } catch (e) {
        print('Failed to decode profile image: $e');
      }
    }

    setState(() {
      _userData = data;
      _cachedAvatarImage = decodedImage;
      _licenseNumber = data['license_number'] ?? 'N/A';
    });
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'scheduled':
        return Icons.schedule_rounded;
      case 'in progress':
      case 'in-progress':
      case 'in_transit':
        return Icons.local_shipping_rounded;
      case 'delayed':
        return Icons.warning_rounded;
      case 'delivered':
      case 'confirmed':
        return Icons.check_circle_rounded;
      case 'pending':
        return Icons.pending_rounded;
      case 'assigned':
        return Icons.assignment_turned_in_rounded;
      case 'accepted': // NEW: Added accepted status
        return Icons.assignment_ind_rounded;
      case 'cancelled':
        return Icons.cancel_rounded;
      default:
        return Icons.info_rounded;
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'scheduled':
        return const Color(0xFF10B981);
      case 'in progress':
      case 'in-progress':
      case 'in_transit':
        return const Color(0xFFF59E0B);
      case 'delayed':
        return const Color(0xFFEF4444);
      case 'delivered':
      case 'confirmed':
        return const Color(0xFF10B981);
      case 'pending':
        return const Color(0xFF64748B);
      case 'assigned':
        return const Color(0xFF3B82F6);
      case 'accepted': // NEW: Added accepted status (blue color)
        return const Color(0xFF3B82F6);
      case 'cancelled':
        return const Color(0xFFEF4444);
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
    return '${date.day}/${date.month}/${date.year} ${_formatTime(timestamp)}';
  }

  Future<Uint8List> _decodeImage(String imageData) async {
    try {
      if (imageData.startsWith('data:image')) {
        final commaIndex = imageData.indexOf(',');
        if (commaIndex != -1) {
          final base64Data = imageData.substring(commaIndex + 1);
          return base64Decode(base64Data);
        }
      }
      
      return base64Decode(imageData);
    } catch (e) {
      print('Error decoding image: $e');
      rethrow;
    }
  }

  void _handleContainerTap(Map<String, dynamic> containerData) {
    final status = containerData['status']?.toString().toLowerCase() ?? 'pending';
    
    if (status == 'in-progress' || status == 'in_transit') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => LiveLocationPage(
            containerData: containerData,
          ),
        ),
      );
    } else if (status == 'delayed') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => StatusUpdatePage(
            containerData: containerData,
          ),
        ),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ContainerDetailsPage(
            containerData: containerData,
            isAvailable: status == 'accepted' || status == 'pending' || status == 'scheduled',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final firstName = _userData?['first_name'] ?? 'First Name';
    final lastName = _userData?['last_name'] ?? 'Last Name';
    final fullName = _userData != null ? '$firstName $lastName' : 'Loading User...';
    final hasAvatarImage = _cachedAvatarImage != null && _cachedAvatarImage!.isNotEmpty;
    final licenseNumber = _licenseNumber.isNotEmpty ? _licenseNumber : 'Loading license...';

    // Get filtered containers
    final filteredAvailableContainers = _getFilteredAvailableContainers();
    final filteredInProgressDeliveries = _getFilteredInProgressDeliveries();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                children: [
                  // Header
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
                                      "License No: $licenseNumber",
                                      style: const TextStyle(fontSize: 12, color: Colors.white70),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            // Review Logs Icon Button in Header
                            IconButton(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (context) => const OrderHistoryPage()),
                                );
                              },
                              icon: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.history_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Today's Schedule Title and Filter - Title moved to left
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start, // Align to left
                      children: [
                        const Text(
                          "Today's Schedule",
                          style: TextStyle(
                            fontSize: 20, 
                            fontWeight: FontWeight.w700, 
                            color: Color(0xFF1E293B)
                          ),
                          textAlign: TextAlign.left, // Align text to left
                        ),
                        const SizedBox(height: 16),
                        // Status Filter Dropdown
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.filter_list_rounded, 
                                color: Color(0xFF64748B), size: 20),
                              const SizedBox(width: 12),
                              const Text(
                                'Filter by Status:',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1E293B),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: DropdownButton<String>(
                                  value: _selectedStatusFilter,
                                  isExpanded: true,
                                  underline: const SizedBox(),
                                  icon: const Icon(Icons.arrow_drop_down_rounded,
                                    color: Color(0xFF64748B)),
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Color(0xFF1E293B),
                                    fontWeight: FontWeight.w500,
                                  ),
                                  onChanged: (String? newValue) {
                                    setState(() {
                                      _selectedStatusFilter = newValue!;
                                    });
                                  },
                                  items: _statusFilters.map<DropdownMenuItem<String>>((String value) {
                                    return DropdownMenuItem<String>(
                                      value: value,
                                      child: Text(value),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  if (filteredAvailableContainers.isNotEmpty)
                    _buildContainerSection(
                      "Available Containers",
                      filteredAvailableContainers,
                      true,
                    ),

                  const SizedBox(height: 16),

                  if (filteredInProgressDeliveries.isNotEmpty)
                    _buildContainerSection(
                      "Your Active Deliveries",
                      filteredInProgressDeliveries,
                      false,
                    ),

                  if (filteredAvailableContainers.isEmpty && filteredInProgressDeliveries.isEmpty)
                    _buildNoContainer(_selectedStatusFilter),
                  const SizedBox(height: 100),
                ],
              ),
            ),
      bottomNavigationBar: _buildBottomNavigation(context, 1),
    );
  }

  Widget _buildContainerSection(String title, List<Map<String, dynamic>> containers, bool isAvailable) {
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF1E293B)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF3B82F6).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  containers.length.toString(),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF3B82F6),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            isAvailable ? "Containers available for delivery" : "Deliveries in progress",
            style: const TextStyle(fontSize: 14, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 20),
          ...containers.map((container) {
            return Column(
              children: [
                _buildContainerCard(container, isAvailable),
                const SizedBox(height: 16),
              ],
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildContainerCard(Map<String, dynamic> container, bool isAvailable) {
    final containerNo = container['containerNumber'] ?? 'N/A';
    final location = container['location'] ?? 'Port Terminal';
    final destination = container['destination'] ?? 'Delivery Point';
    final cargoType = container['cargoType'] ?? 'General';
    final status = container['status']?.toString().toLowerCase() ?? 'pending';
    final time = container['created_at'] != null 
        ? _formatDate(container['created_at'] as Timestamp)
        : container['confirmed_at'] != null
            ? _formatDate(container['confirmed_at'] as Timestamp)
            : 'No time';

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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _getStatusColor(status).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      _getStatusIcon(status),
                      size: 14,
                      color: _getStatusColor(status),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      status.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _getStatusColor(status),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            containerNo,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
          ),
          const SizedBox(height: 4),
          Text(
            'Cargo Type: $cargoType',
            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
          Text(
            'From: $location',
            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
          Text(
            'To: $destination',
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
                  onPressed: () => _handleContainerTap(container),
                  child: const Text("View Details", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNoContainer(String filter) {
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
        children: [
          Icon(Icons.search_off_rounded, size: 64, color: const Color(0xFF64748B)),
          const SizedBox(height: 16),
          Text(
            filter == 'All' 
                ? 'No container items found'
                : 'No containers with "$filter" status',
            style: const TextStyle(fontSize: 16, color: Color(0xFF64748B)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            filter == 'All'
                ? 'Container items will appear here when added to the system'
                : 'Try selecting a different status filter',
            style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
            textAlign: TextAlign.center,
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
              // Already on SchedulePage, do nothing
              break;
            case 2:
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const LiveMapPage()),
              );
              break;
            case 3:
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const SettingsPage()),
              );
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
          icon: Icon(Icons.format_list_bulleted_outlined),
          activeIcon: Icon(Icons.format_list_bulleted),
          label: 'Tasks',
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