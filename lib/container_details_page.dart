import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'livemap_page.dart';
import 'live_location_page.dart';

class ContainerDetailsPage extends StatefulWidget {
  final Map<String, dynamic> containerData;
  final bool isAvailable;

  const ContainerDetailsPage({
    super.key,
    required this.containerData,
    required this.isAvailable,
  });

  @override
  State<ContainerDetailsPage> createState() => _ContainerDetailsPageState();
}

class _ContainerDetailsPageState extends State<ContainerDetailsPage> {
  Map<String, dynamic>? _cargoData;
  bool _isLoading = true;
  String? _error;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  // Real-time route information
  Map<String, dynamic>? _routeInfo;
  bool _isLoadingRoute = false;
  bool _isUpdatingStatus = false; // Prevent multiple status updates

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  Future<void> _initializeData() async {
    try {
      // Use containerData from widget
      _cargoData = widget.containerData;
      setState(() {
        _isLoading = false;
      });
      
      // Load real-time route information
      _loadRealTimeRouteInfo();
    } catch (e) {
      setState(() {
        _error = 'Error loading cargo data: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadRealTimeRouteInfo() async {
    if (_pickup.isEmpty || _destination.isEmpty) return;
    
    setState(() {
      _isLoadingRoute = true;
    });

    try {
      final routeInfo = await OSMService.getRouteInfo(_pickup, _destination);
      setState(() {
        _routeInfo = routeInfo;
        _isLoadingRoute = false;
      });
    } catch (e) {
      print('Error loading route info: $e');
      setState(() {
        _isLoadingRoute = false;
      });
    }
  }

  // Getter methods to safely access data
  String get _cargoId {
    return _cargoData?['cargo_id'] ?? '';
  }

  String get _containerNo {
    return _cargoData?['containerNo'] ?? 'CONT-${_cargoData?['item_number'] ?? 'N/A'}';
  }

  String get _status {
    return _cargoData?['status'] ?? 'pending';
  }

  String get _pickup {
    return _cargoData?['origin'] ?? _cargoData?['pickupLocation'] ?? 'Port Terminal';
  }

  String get _destination {
    return _cargoData?['destination'] ?? 'Delivery Point';
  }

  // Check if cargo is cancelled - FIXED VERSION
  bool get _isCancelled {
    final status = _status.toLowerCase();
    return status == 'cancelled' || 
           _cargoData?['is_cancelled'] == true ||
           _cargoData?['cancelled'] == true ||
           widget.containerData['is_cancelled'] == true ||
           widget.containerData['cancelled'] == true;
  }

  Future<void> _updateCargoStatus(String newStatus) async {
    // Prevent multiple simultaneous updates
    if (_isUpdatingStatus) {
      _showErrorModal('Please wait, update in progress...');
      return;
    }

    // Check if cargo is cancelled - ENHANCED CHECK
    if (_isCancelled) {
      _showErrorModal('This delivery has been cancelled and cannot be updated.');
      return;
    }

    // Prevent starting delivery if cargo is cancelled
    if (newStatus == 'in-progress' && _isCancelled) {
      _showErrorModal('Cannot start delivery - this task has been cancelled.');
      return;
    }

    // Check if already delivered
    if (newStatus == 'delivered' && (_status == 'delivered' || _status == 'cancelled')) {
      _showAlreadyConfirmedModal();
      return;
    }

    setState(() {
      _isUpdatingStatus = true;
    });

    try {
      final cargoId = _cargoId;
      final user = _auth.currentUser;
      
      if (cargoId.isEmpty || user == null) {
        _showErrorModal('Unable to update status: Missing cargo ID or user');
        return;
      }

      // Check if cargo is already in the target status
      final cargoDoc = await _firestore.collection('Cargo').doc(cargoId).get();
      if (cargoDoc.exists) {
        final currentStatus = cargoDoc.data()?['status'] ?? 'pending';
        if (currentStatus == newStatus) {
          _showAlreadyConfirmedModal();
          return;
        }
      }

      if (newStatus == 'in-progress') {
        // Check if delivery record already exists
        final existingDelivery = await _firestore
            .collection('CargoDelivery')
            .where('cargo_id', isEqualTo: cargoId)
            .limit(1)
            .get();

        if (existingDelivery.docs.isEmpty) {
          // Create delivery record when starting delivery
          await _firestore.collection('CargoDelivery').add({
            'cargo_id': cargoId,
            'courier_id': user.uid,
            'status': 'in-progress',
            'confirmed_at': Timestamp.now(),
            'confirmed_by': 'courier',
            'proof_image': '',
            'remarks': 'Delivery started by courier',
          });
        }
      }

      // Update cargo status
      await _firestore
          .collection('Cargo')
          .doc(cargoId)
          .update({
            'status': newStatus,
            'updated_at': Timestamp.now(),
          });

      // Update delivery record if exists
      if (newStatus == 'delivered' || newStatus == 'cancelled') {
        final deliveryQuery = await _firestore
            .collection('CargoDelivery')
            .where('cargo_id', isEqualTo: cargoId)
            .limit(1)
            .get();

        if (deliveryQuery.docs.isNotEmpty) {
          await deliveryQuery.docs.first.reference.update({
            'status': newStatus,
            'confirmed_at': Timestamp.now(),
          });
        }
      }

      // Create notification for status update
      await _firestore.collection('Notifications').add({
        'userId': user.uid,
        'type': 'status_update',
        'message': 'Cargo status updated to ${_getStatusText(newStatus)} for Container $_containerNo',
        'timestamp': Timestamp.now(),
        'read': false,
        'cargoId': cargoId,
        'containerNo': _containerNo,
        'newStatus': newStatus,
      });

      // Refresh the data
      await _initializeData();
      
      // Show success modal for starting delivery
      if (newStatus == 'in-progress') {
        _showDeliveryStartedModal();
      } else {
        _showSuccessModal('Status updated to ${_getStatusText(newStatus)}!');
      }
      
      // Navigate to live location page if starting delivery
      if (newStatus == 'in-progress') {
        // Delay navigation to show the success modal first
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => LiveLocationPage(
                  cargoData: _cargoData!,
                ),
              ),
            );
          }
        });
      }
    } catch (e) {
      print('Error updating cargo status: $e');
      _showErrorModal('Failed to update status: $e');
    } finally {
      setState(() {
        _isUpdatingStatus = false;
      });
    }
  }

  // NEW METHOD: Show delivery started success modal
  void _showDeliveryStartedModal() {
    showDialog(
      context: context,
      barrierDismissible: false, // Prevent dismissing by tapping outside
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
                // Success Icon with Animation
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.play_circle_fill_rounded,
                    color: Color(0xFF10B981),
                    size: 50,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  "Delivery Started!",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "You have successfully started the delivery for Container $_containerNo",
                  textAlign: TextAlign.center,
                  style: const TextStyle(
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
                          "You will be redirected to the live tracking page shortly",
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
                  onPressed: () {
                    Navigator.of(context).pop();
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (context) => LiveLocationPage(
                          cargoData: _cargoData!,
                        ),
                      ),
                    );
                  },
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
                      Icon(Icons.navigation_rounded, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Continue to Tracking',
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

  void _showAlreadyConfirmedModal() {
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
                    color: const Color(0xFF3B82F6).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.info_outline_rounded,
                    color: Color(0xFF3B82F6),
                    size: 40,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Already Confirmed',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'This delivery has already been ${_getStatusText(_status).toLowerCase()}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3B82F6),
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

  String _getStatusText(String status) {
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
      case 'cancelled':
        return 'Cancelled';
      default:
        return status;
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'delivered':
        return const Color(0xFF10B981);
      case 'pending':
      case 'scheduled':
        return const Color(0xFFF59E0B);
      case 'delayed':
      case 'cancelled':
        return const Color(0xFFEF4444);
      case 'in-progress':
      case 'in_transit':
      case 'assigned':
        return const Color(0xFF3B82F6);
      default:
        return const Color(0xFF3B82F6);
    }
  }

  String _formatDate(dynamic date) {
    if (date == null) return 'N/A';
    if (date is Timestamp) {
      final dateTime = date.toDate();
      return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    }
    return date.toString();
  }

  String _formatCurrency(dynamic value) {
    if (value == null) return 'N/A';
    if (value is int || value is double) {
      return '\$${value.toStringAsFixed(2)}';
    }
    return value.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: _isLoading
            ? _buildLoadingState()
            : _error != null
                ? _buildErrorState()
                : _buildContent(),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF3B82F6).withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF3B82F6)),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Loading cargo details...',
            style: TextStyle(
              fontSize: 16,
              color: Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
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
              size: 48,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, color: Color(0xFFEF4444)),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _initializeData,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3B82F6),
              foregroundColor: Colors.white,
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final cargo = _cargoData ?? {};
    final currentStatus = _status.toLowerCase();
    
    return SingleChildScrollView(
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(
              24,
              MediaQuery.of(context).padding.top + 8, // Reduced from 16 to 8
              24,
              16, // Reduced from 24 to 16
            ),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF1E40AF),
                  Color(0xFF3B82F6),
                ],
              ),
            ),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.arrow_back_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                const Icon(
                  Icons.inventory_2_rounded,
                  color: Colors.white,
                  size: 24,
                ),
                const SizedBox(width: 12),
                const Text(
                  "Cargo Details",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
        ),

          const SizedBox(height: 16),

          // Cargo Status Card
          _buildCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.assignment_rounded,
                      color: Color(0xFF3B82F6),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      "Cargo Status",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
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
                          Row(
                            children: [
                              const Icon(
                                Icons.local_shipping_rounded,
                                color: Color(0xFF64748B),
                                size: 16,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _containerNo,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1E293B),
                                ),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: _getStatusColor(currentStatus).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _getStatusIcon(currentStatus),
                                  size: 12,
                                  color: _getStatusColor(currentStatus),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _getStatusText(currentStatus),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: _getStatusColor(currentStatus),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(
                            Icons.fingerprint_rounded,
                            color: Color(0xFF64748B),
                            size: 14,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            "Cargo ID: ${_cargoId.isEmpty ? 'N/A' : _cargoId}",
                            style: const TextStyle(
                              fontSize: 14,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(
                            Icons.calendar_today_rounded,
                            color: Color(0xFF64748B),
                            size: 14,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            "Created: ${_formatDate(cargo['created_at'])}",
                            style: const TextStyle(
                              fontSize: 14,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                      // Show cancellation warning if applicable
                      if (_isCancelled)
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
                                  "This delivery has been cancelled and cannot be started or updated.",
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
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Cargo Information
          _buildCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.description_rounded,
                      color: Color(0xFF3B82F6),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      "Cargo Information",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildInfoRow(Icons.numbers_rounded, "Container No:", _containerNo),
                _buildInfoRow(Icons.description_rounded, "Description:", cargo['description'] ?? 'N/A'),
                _buildInfoRow(Icons.code_rounded, "HS Code:", cargo['hs_code'] ?? 'N/A'),
                _buildInfoRow(Icons.format_list_numbered_rounded, "Item Number:", cargo['item_number']?.toString() ?? 'N/A'),
                _buildInfoRow(Icons.inventory_rounded, "Quantity:", cargo['quantity']?.toString() ?? 'N/A'),
                _buildInfoRow(Icons.attach_money_rounded, "Value:", _formatCurrency(cargo['value'])),
                _buildInfoRow(Icons.fitness_center_rounded, "Weight:", "${cargo['weight']?.toString() ?? 'N/A'} kg"),
                _buildInfoRow(Icons.place_rounded, "Origin:", _pickup),
                _buildInfoRow(Icons.flag_rounded, "Destination:", _destination),
                if (cargo['additional_info'] != null && cargo['additional_info'].toString().isNotEmpty)
                  _buildInfoRow(Icons.info_rounded, "Additional Info:", cargo['additional_info'].toString()),
                if (cargo['submanifest_id'] != null)
                  _buildInfoRow(Icons.list_alt_rounded, "Submanifest ID:", cargo['submanifest_id'].toString()),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Real-time Route Information
          _buildCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.route_rounded,
                      color: Color(0xFF3B82F6),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      "Route Information",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                
                if (_isLoadingRoute)
                  _buildRouteLoadingState()
                else if (_routeInfo != null)
                  _buildRealTimeRouteInfo()
                else
                  _buildFallbackRouteInfo(),
                  
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3B82F6),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    onPressed: _isCancelled ? null : () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => LiveMapPage(
                            cargoId: _cargoId,
                            pickup: _pickup,
                            destination: _destination,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.navigation_rounded),
                    label: const Text(
                      "Open Navigation",
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

          const SizedBox(height: 16),

          // Action Buttons
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                // First row of buttons
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isSmallScreen = constraints.maxWidth < 360;
                    return isSmallScreen
                        ? Column(
                            children: [
                              _buildActionButton(
                                icon: Icons.report_problem_rounded,
                                text: "Report Issue",
                                isPrimary: false,
                                color: const Color(0xFFF59E0B),
                                onPressed: _isCancelled ? null : () => _showReportIssueModal(),
                              ),
                              const SizedBox(height: 8),
                              if (currentStatus != 'in-progress' && currentStatus != 'in_transit' && currentStatus != 'delivered' && !_isCancelled)
                                _buildActionButton(
                                  icon: Icons.play_arrow_rounded,
                                  text: _isUpdatingStatus ? "Starting..." : "Start Delivery",
                                  isPrimary: true,
                                  color: const Color(0xFF3B82F6),
                                  onPressed: _isUpdatingStatus || _isCancelled ? null : () => _updateCargoStatus('in-progress'),
                                ),
                            ],
                          )
                        : Row(
                            children: [
                              Expanded(
                                child: _buildActionButton(
                                  icon: Icons.report_problem_rounded,
                                  text: "Report Issue",
                                  isPrimary: false,
                                  color: const Color(0xFFF59E0B),
                                  onPressed: _isCancelled ? null : () => _showReportIssueModal(),
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (currentStatus != 'in-progress' && currentStatus != 'in_transit' && currentStatus != 'delivered' && !_isCancelled)
                                Expanded(
                                  child: _buildActionButton(
                                    icon: Icons.play_arrow_rounded,
                                    text: _isUpdatingStatus ? "Starting..." : "Start Delivery",
                                    isPrimary: true,
                                    color: const Color(0xFF3B82F6),
                                    onPressed: _isUpdatingStatus || _isCancelled ? null : () => _updateCargoStatus('in-progress'),
                                  ),
                                ),
                            ],
                          );
                  },
                ),
                
                const SizedBox(height: 8),
                
                // Second row of buttons
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isSmallScreen = constraints.maxWidth < 360;
                    return isSmallScreen
                        ? Column(
                            children: [
                              if (!_isCancelled && currentStatus != 'delivered')
                                _buildActionButton(
                                  icon: Icons.cancel_rounded,
                                  text: "Cancel Task",
                                  isPrimary: false,
                                  color: const Color(0xFFEF4444),
                                  onPressed: _isCancelled ? null : () => _showCancelConfirmation(),
                                ),
                              const SizedBox(height: 8),
                              if ((currentStatus == 'in-progress' || currentStatus == 'in_transit') && !_isCancelled)
                                _buildActionButton(
                                  icon: Icons.check_circle_rounded,
                                  text: _isUpdatingStatus ? "Confirming..." : "Confirm Delivery",
                                  isPrimary: true,
                                  color: const Color(0xFF10B981),
                                  onPressed: _isUpdatingStatus || _isCancelled ? null : () => _updateCargoStatus('delivered'),
                                ),
                            ],
                          )
                        : Row(
                            children: [
                              if (!_isCancelled && currentStatus != 'delivered')
                                Expanded(
                                  child: _buildActionButton(
                                    icon: Icons.cancel_rounded,
                                    text: "Cancel Task",
                                    isPrimary: false,
                                    color: const Color(0xFFEF4444),
                                    onPressed: _isCancelled ? null : () => _showCancelConfirmation(),
                                  ),
                                ),
                              if (!_isCancelled && currentStatus != 'delivered') const SizedBox(width: 8),
                              if ((currentStatus == 'in-progress' || currentStatus == 'in_transit') && !_isCancelled)
                                Expanded(
                                  child: _buildActionButton(
                                    icon: Icons.check_circle_rounded,
                                    text: _isUpdatingStatus ? "Confirming..." : "Confirm Delivery",
                                    isPrimary: true,
                                    color: const Color(0xFF10B981),
                                    onPressed: _isUpdatingStatus || _isCancelled ? null : () => _updateCargoStatus('delivered'),
                                  ),
                                ),
                            ],
                          );
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildRouteLoadingState() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: const Column(
        children: [
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF3B82F6)),
          ),
          SizedBox(height: 8),
          Text(
            'Calculating route...',
            style: TextStyle(
              fontSize: 14,
              color: Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRealTimeRouteInfo() {
    final routeInfo = _routeInfo!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildRouteInfoItem('${routeInfo['distance']} km', 'Distance', Icons.flag_rounded),
              _buildRouteInfoItem('${routeInfo['duration']} mins', 'Time', Icons.access_time_rounded),
              _buildRouteInfoItem(routeInfo['trafficStatus'], 'Traffic', Icons.traffic_rounded),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.check_circle_rounded,
                size: 12,
                color: Colors.green[600],
              ),
              const SizedBox(width: 4),
              Text(
                'Real-time OSM route data',
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.green[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFallbackRouteInfo() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildRouteInfoItem('15.3 km', 'Distance', Icons.flag_rounded),
              _buildRouteInfoItem('32 mins', 'Time', Icons.access_time_rounded),
              _buildRouteInfoItem('Normal', 'Traffic', Icons.traffic_rounded),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.schedule_rounded,
                size: 12,
                color: Colors.orange[600],
              ),
              const SizedBox(width: 4),
              Text(
                'Estimated route data',
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.orange[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRouteInfoItem(String value, String label, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 16, color: const Color(0xFF3B82F6)),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1E293B),
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            color: Color(0xFF64748B),
          ),
        ),
      ],
    );
  }

  Widget _buildCard({required Widget child}) {
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
      child: child,
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value, {bool isHazardous = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 16,
            color: const Color(0xFF64748B),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF64748B),
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isHazardous ? const Color(0xFFEF4444) : const Color(0xFF1E293B),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String text,
    required bool isPrimary,
    required Color color,
    required VoidCallback? onPressed,
  }) {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: isPrimary ? color : Colors.white,
        foregroundColor: isPrimary ? Colors.white : color,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: isPrimary ? BorderSide.none : BorderSide(color: color, width: 1.5),
        ),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      ),
      onPressed: onPressed,
      icon: Icon(
        icon,
        size: 20,
      ),
      label: Text(
        text,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: isPrimary ? Colors.white : color,
        ),
      ),
    );
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'delivered':
        return Icons.check_circle_rounded;
      case 'pending':
      case 'scheduled':
        return Icons.schedule_rounded;
      case 'delayed':
      case 'cancelled':
        return Icons.cancel_rounded;
      case 'in-progress':
      case 'in_transit':
      case 'assigned':
        return Icons.local_shipping_rounded;
      default:
        return Icons.inventory_2_rounded;
    }
  }

  void _showReportIssueModal() {
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
                    color: const Color(0xFFF59E0B).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.report_problem_rounded,
                    color: Color(0xFFF59E0B),
                    size: 40,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Report Issue',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Please contact support to report any issues with this delivery.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF59E0B),
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

  void _showCancelConfirmation() {
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
                    Icons.warning_amber_rounded,
                    color: Color(0xFFEF4444),
                    size: 40,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Cancel Delivery?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Are you sure you want to cancel this delivery task? This action cannot be undone.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF64748B),
                          side: const BorderSide(color: Color(0xFFE2E8F0)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Text('No, Keep'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          _updateCargoStatus('cancelled');
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFEF4444),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Text('Yes, Cancel'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
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
                    size: 40,
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
                    backgroundColor: const Color(0xFF10B981),
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
                    size: 40,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
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
}

class OSMService {
  static Future<Map<String, dynamic>> getRouteInfo(String pickup, String destination) async {
    try {
      // Simulate API call delay
      await Future.delayed(const Duration(seconds: 2));
      
      // Mock response with realistic data
      return {
        'distance': '15.3',
        'duration': '32',
        'trafficStatus': 'Normal',
        'coordinates': [
          {'lat': 40.7128, 'lng': -74.0060}, // NYC
          {'lat': 40.7589, 'lng': -73.9851}, // Midtown
        ]
      };
    } catch (e) {
      throw Exception('Failed to fetch route info: $e');
    }
  }
}