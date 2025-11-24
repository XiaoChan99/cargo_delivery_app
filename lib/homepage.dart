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
import 'analytics_page.dart';
import 'order_history_page.dart';
import 'status_update_page.dart'; 

// Add this constant at the top of the file after the imports
const String DECLARED_ORIGIN = "Don Carlos A. Gothong Port Centre, Quezon Boulevard, Pier 4, Cebu City.";

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

  // Container Lists
  List<Map<String, dynamic>> _availableContainers = [];
  List<Map<String, dynamic>> _inProgressDeliveries = [];

  @override
  void initState() {
    super.initState();
    _currentUser = _auth.currentUser;
    if (_currentUser != null) {
      _loadData();
      setupContainerListener(_loadAvailableContainers);
      setupDeliveryListener(_currentUser!.uid, _loadInProgressDeliveries);
      _setupNotificationListener();
    } else {
      _isLoading = false;
      _errorMessage = "User not authenticated";
    }
  }

  @override
  void dispose() {
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

  Future<void> _loadData() async {
    if (_currentUser == null) {
      print('User not authenticated');
      setState(() {
        _isLoading = false;
        _errorMessage = "User not authenticated";
      });
      return;
    }
    
    try {
      await Future.wait([
        _loadUserData(),
        _loadAvailableContainers(),
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

  Future<void> _loadAvailableContainers() async {
  try {
    print('=== DEBUG: Loading available containers ===');
    
    QuerySnapshot containerSnapshot = await _firestore
        .collection('Containers')
        .orderBy('dateCreated', descending: true)
        .get();

    print('DEBUG: Found ${containerSnapshot.docs.length} total containers');
    
    // Print all containers for debugging
    for (var doc in containerSnapshot.docs) {
      var containerData = doc.data() as Map<String, dynamic>;
      print('DEBUG Container: ${doc.id}');
      print('  - ContainerNumber: ${containerData['containerNumber']}');
      print('  - AllocationStatus: ${containerData['allocationStatus']}');
      print('  - Status: ${containerData['status']}');
      print('  - Has allocationStatus field: ${containerData.containsKey('allocationStatus')}');
      print('  - All fields: ${containerData.keys.toList()}');
    }

    QuerySnapshot deliverySnapshot = await _firestore
        .collection('ContainerDelivery')
        .get();

    print('DEBUG: Found ${deliverySnapshot.docs.length} delivery records');
    
    Set<String> assignedContainerIds = {};
    Map<String, String> containerDeliveryStatus = {};
    
    // Get all container IDs that have delivery records
    for (var doc in deliverySnapshot.docs) {
      var deliveryData = doc.data() as Map<String, dynamic>;
      if (deliveryData['containerId'] != null) {
        String containerId = deliveryData['containerId'].toString();
        assignedContainerIds.add(containerId);
        containerDeliveryStatus[containerId] = deliveryData['status']?.toString().toLowerCase() ?? '';
        print('DEBUG Delivery: Container $containerId has status: ${deliveryData['status']}');
      }
    }

    List<Map<String, dynamic>> availableContainers = [];
    
    for (var doc in containerSnapshot.docs) {
      var containerData = doc.data() as Map<String, dynamic>;
      String containerId = doc.id;

      // Check if container has a delivery record
      bool hasDeliveryRecord = assignedContainerIds.contains(containerId);
      String deliveryStatus = containerDeliveryStatus[containerId] ?? '';
      
      // Get allocation status from container data - handle null/empty cases
      String allocationStatus = (containerData['allocationStatus']?.toString().toLowerCase() ?? '').trim();
      
      // Get container status from container data
      String containerStatus = (containerData['status']?.toString().toLowerCase() ?? '').trim();
      
      print('DEBUG Processing: $containerId');
      print('  - Has delivery record: $hasDeliveryRecord');
      print('  - Delivery status: $deliveryStatus');
      print('  - Allocation status: "$allocationStatus"');
      print('  - Container status: "$containerStatus"');
      print('  - Allocation status == "released": ${allocationStatus == "released"}');
      print('  - Container status == "accepted": ${containerStatus == "accepted"}');
      
      // Include container if:
      // 1. It has NO delivery record AND allocationStatus is 'released' AND container status is not 'accepted' OR
      // 2. It has delivery record but status is 'cancelled'
      bool shouldInclude = false;
      String inclusionReason = '';
      
      if (!hasDeliveryRecord && allocationStatus == 'released' && containerStatus != 'accepted') {
        shouldInclude = true;
        inclusionReason = 'No delivery record + released + not accepted';
      } else if (deliveryStatus == 'cancelled') {
        shouldInclude = true;
        inclusionReason = 'Cancelled delivery';
      }
      
      print('  - Should include: $shouldInclude ($inclusionReason)');
      
      if (shouldInclude) {
        // Use ACTUAL field names from your Firestore documents
        Map<String, dynamic> combinedData = {
          'containerId': containerId,
          'containerNumber': containerData['containerNumber']?.toString() ?? 'N/A',
          'sealNumber': containerData['sealNumber']?.toString() ?? 'N/A',
          'billOfLading': containerData['billOfLading']?.toString() ?? 'N/A',
          'consigneeName': containerData['consigneeName']?.toString() ?? 'N/A',
          'consigneeAddress': containerData['consigneeAddress']?.toString() ?? 'N/A',
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
          'containerStatus': containerStatus,
          'created_at': containerData['dateCreated'],
          'is_cancelled': deliveryStatus == 'cancelled',
          'sequence_number': _extractSequenceNumber(containerId),
        };
        availableContainers.add(combinedData);
        
        print('  ✓ ADDED container: $containerId');
      } else {
        print('  ✗ SKIPPED container: $containerId');
      }
    }

    // Sort available containers by sequence number (container ID)
    availableContainers.sort((a, b) {
      int seqA = a['sequence_number'] ?? 0;
      int seqB = b['sequence_number'] ?? 0;
      return seqA.compareTo(seqB);
    });

    setState(() {
      _availableContainers = availableContainers;
    });
    
    print('=== DEBUG: Found ${_availableContainers.length} available containers ===');
    
  } catch (e) {
    print('ERROR loading available containers: $e');
    print('Stack trace: ${e.toString()}');
    setState(() {
      _availableContainers = [];
    });
  }
}

  // Extract sequence number from container ID
  int _extractSequenceNumber(String containerId) {
    try {
      // If container ID is a simple number
      if (RegExp(r'^\d+$').hasMatch(containerId)) {
        return int.parse(containerId);
      }
      
      // If container ID has prefix like "container_123"
      RegExp regex = RegExp(r'(\d+)$');
      Match? match = regex.firstMatch(containerId);
      if (match != null) {
        return int.parse(match.group(1)!);
      }
      
      // If no numbers found, use hash code (fallback)
      return containerId.hashCode.abs();
    } catch (e) {
      print('Error extracting sequence number from $containerId: $e');
      return 0;
    }
  }

  Future<void> _loadInProgressDeliveries() async {
  try {
    print('Loading in-progress deliveries...');
    
    QuerySnapshot deliverySnapshot = await _firestore
        .collection('ContainerDelivery')
        .where('courier_id', isEqualTo: _currentUser!.uid)
        .get();

    List<Map<String, dynamic>> inProgressDeliveries = [];
    
    for (var doc in deliverySnapshot.docs) {
      var deliveryData = doc.data() as Map<String, dynamic>;
      String status = deliveryData['status']?.toString().toLowerCase() ?? '';
      
      // Include accepted, in-progress, in_transit, assigned, or delayed statuses
      if (status == 'accepted' || status == 'in-progress' || status == 'in_transit' || status == 'assigned' || status == 'delayed') {
        try {
          DocumentSnapshot containerDoc = await _firestore
              .collection('Containers')
              .doc(deliveryData['containerId'].toString())
              .get();

          if (containerDoc.exists) {
            var containerData = containerDoc.data() as Map<String, dynamic>;
            
            Map<String, dynamic> combinedData = {
              'delivery_id': doc.id,
              'containerId': deliveryData['containerId'],
              'containerNumber': containerData['containerNumber']?.toString() ?? 'N/A',
              'sealNumber': containerData['sealNumber']?.toString() ?? 'N/A',
              'billOfLading': containerData['billOfLading']?.toString() ?? 'N/A',
              'consigneeName': containerData['consigneeName']?.toString() ?? 'N/A',
              'consigneeAddress': containerData['consigneeAddress']?.toString() ?? 'N/A',
              'consignorName': containerData['consignorName']?.toString() ?? 'N/A',
              'consignorAddress': containerData['consignorAddress']?.toString() ?? 'N/A',
              'priority': containerData['priority']?.toString() ?? 'normal',
              'deliveredBy': deliveryData['courierFullName'] ?? '',
              'voyageId': containerData['voyageId']?.toString() ?? '',
              'location': DECLARED_ORIGIN,
              'destination': containerData['destination']?.toString() ?? 'Delivery Point',
              'cargoType': containerData['cargoType']?.toString() ?? 'General',
              'status': deliveryData['status'] ?? 'in-progress',
              'confirmed_at': deliveryData['confirmed_at'],
              'courier_id': deliveryData['courier_id'],
              'proof_image': deliveryData['proof_image'],
              'confirmed_by': deliveryData['courierFullName'] ?? '',
              'sequence_number': _extractSequenceNumber(deliveryData['containerId'].toString()),
            };
            inProgressDeliveries.add(combinedData);
          }
        } catch (e) {
          print('Error loading container details for delivery: $e');
        }
      }
    }

    // Sort in-progress deliveries by sequence number
    inProgressDeliveries.sort((a, b) {
      int seqA = a['sequence_number'] ?? 0;
      int seqB = b['sequence_number'] ?? 0;
      return seqA.compareTo(seqB);
    });

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

  Future<void> _acceptContainerDelivery(Map<String, dynamic> containerData) async {
  try {
    final user = _auth.currentUser;
    if (user == null) {
      _showErrorModal('User not authenticated');
      return;
    }

    // Check if container is cancelled
    final bool isCancelled = containerData['is_cancelled'] == true;
    if (isCancelled) {
      _showErrorModal('This delivery has been cancelled and cannot be accepted again.');
      return;
    }

    // Check allocation status
    final String allocationStatus = containerData['allocationStatus']?.toString().toLowerCase() ?? '';
    if (allocationStatus != 'released') {
      _showErrorModal('This container is not yet released for delivery.');
      return;
    }

    // Check if container is already assigned to someone else
    final deliveryCheck = await _firestore
        .collection('ContainerDelivery')
        .where('containerId', isEqualTo: containerData['containerId'])
        .limit(1)
        .get();

    if (deliveryCheck.docs.isNotEmpty) {
      final existingDelivery = deliveryCheck.docs.first.data();
      final existingStatus = existingDelivery['status']?.toString().toLowerCase() ?? '';
      final existingCourierId = existingDelivery['courier_id']?.toString() ?? '';
      
      if (existingStatus == 'cancelled') {
        _showErrorModal('This delivery has been cancelled and cannot be accepted.');
        return;
      }
      
      if (existingCourierId != user.uid) {
        _showErrorModal('This container has already been assigned to another courier.');
        return;
      }
    }

    // Get courier's full name
    String courierFullName = _getFullName();

    // Use batch write to ensure both updates happen atomically
    WriteBatch batch = _firestore.batch();

    // Update container status to 'accepted' in Containers collection
    DocumentReference containerRef = _firestore.collection('Containers').doc(containerData['containerId']);
    batch.update(containerRef, {
      'status': 'accepted',
      'updated_at': Timestamp.now(),
      'assigned_courier_id': user.uid,
      'assigned_courier_name': courierFullName,
    });

    // Create or update ContainerDelivery document
    DocumentReference deliveryRef;
    if (deliveryCheck.docs.isNotEmpty) {
      // Update existing delivery record
      deliveryRef = deliveryCheck.docs.first.reference;
      batch.update(deliveryRef, {
        'status': 'accepted',
        'confirmed_at': Timestamp.now(),
        'confirmed_by': courierFullName,
        'courier_id': user.uid,
        'proof_image': '',
        'remarks': 'Accepted by courier',
        'updated_at': Timestamp.now(),
        'consigneeName': containerData['consigneeName'] ?? 'N/A',
        'consigneeAddress': containerData['consigneeAddress'] ?? 'N/A',
        'consignorName': containerData['consignorName'] ?? 'N/A',
        'consignorAddress': containerData['consignorAddress'] ?? 'N/A',
      });
    } else {
      // Create new delivery record
      deliveryRef = _firestore.collection('ContainerDelivery').doc();
      batch.set(deliveryRef, {
        'containerId': containerData['containerId'],
        'courier_id': user.uid,
        'status': 'accepted',
        'confirmed_at': Timestamp.now(),
        'confirmed_by': courierFullName,
        'proof_image': '',
        'remarks': 'Accepted by courier',
        'created_at': Timestamp.now(),
        'updated_at': Timestamp.now(),
        'container_number': containerData['containerNumber'],
        'seal_number': containerData['sealNumber'],
        'bill_of_lading': containerData['billOfLading'],
        'consigneeName': containerData['consigneeName'] ?? 'N/A',
        'consigneeAddress': containerData['consigneeAddress'] ?? 'N/A',
        'destination': containerData['destination'],
        'priority': containerData['priority'],
        'consignorName': containerData['consignorName'] ?? 'N/A',
        'consignorAddress': containerData['consignorAddress'] ?? 'N/A',
      });
    }

    // Commit both updates in a single transaction
    await batch.commit();

    // Create notification for admin
    try {
      await _firestore.collection('Notifications').add({
        'userId': 'admin',
        'type': 'delivery_assigned',
        'title': 'Delivery Accepted',
        'message': 'Container ${containerData['containerNumber']} has been accepted by $courierFullName',
        'timestamp': Timestamp.now(),
        'read': false,
        'containerId': containerData['containerId'],
        'containerNumber': containerData['containerNumber'],
        'courier_id': user.uid,
        'courier_name': courierFullName,
      });
    } catch (e) {
      print('Error creating notification: $e');
      // Don't fail the whole process if notification fails
    }

    // Also update user's current delivery count
    try {
      await _firestore.collection('Couriers').doc(user.uid).update({
        'current_deliveries': FieldValue.increment(1),
        'last_activity': Timestamp.now(),
      });
    } catch (e) {
      print('Error updating courier stats: $e');
    }

    // Refresh data
    await _loadData();
    
    _showSuccessModal('Container accepted successfully! You can now track your delivery.');
    
  } catch (e) {
    print('Error accepting container: $e');
    _showErrorModal('Failed to accept container. Please try again.');
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
      case 'accepted':
        return 'Accepted';
      case 'in-progress':
      case 'in_transit':
        return 'In Progress';
      case 'delivered':
        return 'Delivered';
      case 'delayed':
        return 'Delayed';
      case 'cancelled':
        return 'Cancelled';
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
      case 'accepted':
        return const Color(0xFF6366F1);
      case 'in-progress':
      case 'in_transit':
        return const Color(0xFF6366F1);
      case 'delivered':
        return const Color(0xFF10B981);
      case 'delayed':
        return const Color(0xFFEF4444);
      case 'cancelled':
        return const Color(0xFF6B7280);
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.white, Color(0xFFFAFBFF)],
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  color: Color(0xFF10B981),
                  size: 50,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                "Delivery status updated in both systems",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 16),
              // Additional Info Section
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F9FF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE0F2FE)),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      color: Colors.blue[600],
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Container status: Accepted → Ready for pickup",
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(150, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_rounded, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Start Delivery',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Colors.white, Color(0xFFFAFBFF)],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.error_outline_rounded,
                    color: Color(0xFFEF4444),
                    size: 50,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEF4444),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(120, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'OK',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
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

  void _debugContainerData() {
    print('=== DEBUG CONTAINER DATA ===');
    print('Available Containers: ${_availableContainers.length}');
    print('In Progress Deliveries: ${_inProgressDeliveries.length}');
    
    for (var container in _availableContainers) {
      print('Available: ${container['containerNumber']} - Status: ${container['status']} - ID: ${container['containerId']} - Allocation: ${container['allocationStatus']} - Sequence: ${container['sequence_number']}');
    }
    
    for (var delivery in _inProgressDeliveries) {
      print('In Progress: ${delivery['containerNumber']} - Status: ${delivery['status']} - Sequence: ${delivery['sequence_number']}');
    }
    print('=== END DEBUG ===');
  }

  @override
  Widget build(BuildContext context) {
    // Add this for debugging (remove after fixing)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _debugContainerData();
    });
    
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
                            "CONTAINER EXPRESS",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: 1.1,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            "Gothong Container Shipping Express",
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

            // Profile Section
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

            // All Four Sections in One Container - No background, no shadows
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  // First row: Containers and Track
                  Row(
                    children: [
                      Expanded(
                        child: _buildActionCard(
                          "Containers",
                          Icons.local_shipping,
                          const Color(0xFF3B82F6),
                          _availableContainers.length.toString(),
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
                  const SizedBox(height: 12),
                  const SizedBox(height: 12),
                  // Second row: Order History and Performance
                  Row(
                    children: [
                      Expanded(
                        child: _buildActionCard(
                          "Delivery History",
                          Icons.history,
                          const Color(0xFF3B82F6),
                          "View",
                          () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => const OrderHistoryPage()),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildActionCard(
                          "Performance",
                          Icons.assessment,
                          const Color(0xFFF59E0B),
                          "View",
                          () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => AnalyticsPage(userId: _currentUser!.uid)),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Available Containers Section
            if (_availableContainers.isNotEmpty)
              _buildContainerSection(
                "Available Deliveries",
                _availableContainers,
                _availableContainers.length,
                true, // isAvailable
              ),

            const SizedBox(height: 20),

            // In Progress Deliveries Section
            if (_inProgressDeliveries.isNotEmpty)
              _buildContainerSection(
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
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
          border: Border.all(
            color: Colors.grey.withOpacity(0.1),
            width: 1,
          ),
        ),
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
              title == "Containers" ? "Available for delivery" : 
              title == "Track" ? "Track your container" :
              title == "Delivery History" ? "View past delivery" : "View performance",
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

  Widget _buildContainerSection(String title, List<Map<String, dynamic>> deliveries, int count, bool isAvailable) {
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
                _buildContainerDeliveryCard(delivery, isAvailable),
                if (deliveries.indexOf(delivery) < deliveries.length - 1 && deliveries.indexOf(delivery) < 2)
                  const SizedBox(height: 12),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildContainerDeliveryCard(Map<String, dynamic> delivery, bool isAvailable) {
    // Check if this delivery is already accepted/in-progress
    final status = delivery['status']?.toString().toLowerCase() ?? 'pending';
    final bool isAlreadyAccepted = status == 'accepted' || status == 'in-progress' || 
                                  status == 'in_transit' || status == 'assigned';
    
    // Check if this container was cancelled by the current courier
    final bool isCancelled = delivery['is_cancelled'] == true || 
                            status == 'cancelled';
    
    // Check allocation status
    final String allocationStatus = delivery['allocationStatus']?.toString().toLowerCase() ?? '';
    final bool isReleased = allocationStatus == 'released';
    
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
                  "${delivery['containerNumber'] ?? 'N/A'}",
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
          
          // Show allocation status info
          if (isAvailable && !isReleased)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFEF3C7)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    color: Colors.amber[700],
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Waiting for release - Container not yet ready for delivery",
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.amber[700],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          
          // Show cancellation warning if applicable
          if (isCancelled && isAvailable)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3F2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFECDCA)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.orange[700],
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Trying to deliver after cancellation could cause confusion to the owner!",
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange[700],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.location_on_outlined, size: 16, color: Color(0xFF64748B)),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  "${delivery['location'] ?? DECLARED_ORIGIN} → ${delivery['destination'] ?? 'Delivery Point'}",
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
                    
                    if (status == 'accepted' || status == 'in-progress' || status == 'in_transit') {
                      // Navigate to live location for accepted/in-progress deliveries
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => LiveMapPage(
                          ),
                        ),
                      );
                    } else if (status == 'delayed') {
                      // Navigate to StatusUpdatePage for delayed deliveries
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => StatusUpdatePage(
                            containerData: delivery,
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
                    status == 'accepted' || status == 'in-progress' || status == 'in_transit' 
                        ? 'Track Now' 
                        : status == 'delayed'
                            ? 'Update Status'
                            : 'View Details',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              // Only show Accept button if:
              // - Container is available
              // - Not already accepted
              // - Not cancelled
              // - Allocation status is 'released'
              if (isAvailable && !isAlreadyAccepted && !isCancelled && isReleased)
                const SizedBox(width: 8),
              if (isAvailable && !isAlreadyAccepted && !isCancelled && isReleased)
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _acceptContainerDelivery(delivery),
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
              // Show disabled accept button for non-released tasks
              if (isAvailable && !isAlreadyAccepted && !isCancelled && !isReleased)
                const SizedBox(width: 8),
              if (isAvailable && !isAlreadyAccepted && !isCancelled && !isReleased)
                Expanded(
                  child: ElevatedButton(
                    onPressed: null, // Disabled button
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey[400],
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text(
                      'Not Released',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              // Show disabled accept button for cancelled tasks
              if (isAvailable && isCancelled)
                const SizedBox(width: 8),
              if (isAvailable && isCancelled)
                Expanded(
                  child: ElevatedButton(
                    onPressed: null, // Disabled button
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey[400],
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text(
                      'Cancelled',
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

void setupContainerListener(Function refreshCallback) {
  FirebaseFirestore.instance
      .collection('Containers')
      .snapshots()
      .listen((_) => refreshCallback());
}

void setupDeliveryListener(String userId, Function refreshCallback) {
  FirebaseFirestore.instance
      .collection('ContainerDelivery')
      .where('courier_id', isEqualTo: userId)
      .snapshots()
      .listen((snapshot) {
        // Refresh when any delivery status changes (not just cancellations)
        refreshCallback();
      });
}