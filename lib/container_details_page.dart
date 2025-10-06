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

  Future<void> _updateCargoStatus(String newStatus) async {
    // Prevent multiple simultaneous updates
    if (_isUpdatingStatus) {
      _showErrorModal('Please wait, update in progress...');
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
      
      _showSuccessModal('Status updated to ${_getStatusText(newStatus)}!');
      
      // Navigate to live location page if starting delivery
      if (newStatus == 'in-progress') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => LiveLocationPage(
              cargoData: _cargoData!,
            ),
          ),
        );
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

  void _showAlreadyConfirmedModal() {
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
                  Icons.info_outline,
                  color: Color(0xFF3B82F6),
                  size: 64,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Already Confirmed',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
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
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Loading cargo details...'),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 64),
          const SizedBox(height: 16),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, color: Colors.red),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _initializeData,
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
          // Header with back button - Fixed consistent height
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(
              24,
              MediaQuery.of(context).padding.top + 16,
              24,
              24,
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
                      Icons.arrow_back,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
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
                const Text(
                  "Cargo Status",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E293B),
                  ),
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
                          Text(
                            _containerNo,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: _getStatusColor(currentStatus).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              _getStatusText(currentStatus),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: _getStatusColor(currentStatus),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Cargo ID: ${_cargoId.isEmpty ? 'N/A' : _cargoId}",
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Created: ${_formatDate(cargo['created_at'])}",
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF64748B),
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
                const Text(
                  "Cargo Information",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 16),
                _buildInfoRow("Container No:", _containerNo),
                _buildInfoRow("Description:", cargo['description'] ?? 'N/A'),
                _buildInfoRow("HS Code:", cargo['hs_code'] ?? 'N/A'),
                _buildInfoRow("Item Number:", cargo['item_number']?.toString() ?? 'N/A'),
                _buildInfoRow("Quantity:", cargo['quantity']?.toString() ?? 'N/A'),
                _buildInfoRow("Value:", _formatCurrency(cargo['value'])),
                _buildInfoRow("Weight:", "${cargo['weight']?.toString() ?? 'N/A'} kg"),
                _buildInfoRow("Origin:", _pickup),
                _buildInfoRow("Destination:", _destination),
                if (cargo['additional_info'] != null && cargo['additional_info'].toString().isNotEmpty)
                  _buildInfoRow("Additional Info:", cargo['additional_info'].toString()),
                if (cargo['submanifest_id'] != null)
                  _buildInfoRow("Submanifest ID:", cargo['submanifest_id'].toString()),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Real-time Route Information
          _buildCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Route Information",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E293B),
                  ),
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
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3B82F6),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    onPressed: () {
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
                    child: const Text(
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
                                text: "Report Issue",
                                isPrimary: false,
                                color: const Color(0xFFF59E0B),
                                onPressed: () => _showReportIssueModal(),
                              ),
                              const SizedBox(height: 8),
                              if (currentStatus != 'in-progress' && currentStatus != 'in_transit' && currentStatus != 'delivered' && currentStatus != 'cancelled')
                                _buildActionButton(
                                  text: _isUpdatingStatus ? "Starting..." : "Start Delivery",
                                  isPrimary: true,
                                  color: const Color(0xFF3B82F6),
                                  onPressed: _isUpdatingStatus ? null : () => _updateCargoStatus('in-progress'),
                                ),
                            ],
                          )
                        : Row(
                            children: [
                              Expanded(
                                child: _buildActionButton(
                                  text: "Report Issue",
                                  isPrimary: false,
                                  color: const Color(0xFFF59E0B),
                                  onPressed: () => _showReportIssueModal(),
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (currentStatus != 'in-progress' && currentStatus != 'in_transit' && currentStatus != 'delivered' && currentStatus != 'cancelled')
                                Expanded(
                                  child: _buildActionButton(
                                    text: _isUpdatingStatus ? "Starting..." : "Start Delivery",
                                    isPrimary: true,
                                    color: const Color(0xFF3B82F6),
                                    onPressed: _isUpdatingStatus ? null : () => _updateCargoStatus('in-progress'),
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
                              if (currentStatus != 'cancelled' && currentStatus != 'delivered')
                                _buildActionButton(
                                  text: "Cancel Task",
                                  isPrimary: false,
                                  color: const Color(0xFFEF4444),
                                  onPressed: () => _showCancelConfirmation(),
                                ),
                              const SizedBox(height: 8),
                              if (currentStatus == 'in-progress' || currentStatus == 'in_transit')
                                _buildActionButton(
                                  text: _isUpdatingStatus ? "Confirming..." : "Confirm Delivery",
                                  isPrimary: true,
                                  color: const Color(0xFF10B981),
                                  onPressed: _isUpdatingStatus ? null : () => _updateCargoStatus('delivered'),
                                ),
                            ],
                          )
                        : Row(
                            children: [
                              if (currentStatus != 'cancelled' && currentStatus != 'delivered')
                                Expanded(
                                  child: _buildActionButton(
                                    text: "Cancel Task",
                                    isPrimary: false,
                                    color: const Color(0xFFEF4444),
                                    onPressed: () => _showCancelConfirmation(),
                                  ),
                                ),
                              if (currentStatus != 'cancelled' && currentStatus != 'delivered') const SizedBox(width: 8),
                              if (currentStatus == 'in-progress' || currentStatus == 'in_transit')
                                Expanded(
                                  child: _buildActionButton(
                                    text: _isUpdatingStatus ? "Confirming..." : "Confirm Delivery",
                                    isPrimary: true,
                                    color: const Color(0xFF10B981),
                                    onPressed: _isUpdatingStatus ? null : () => _updateCargoStatus('delivered'),
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
          CircularProgressIndicator(),
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
              _buildRouteInfoItem('${routeInfo['distance']} km', 'Distance', Icons.flag),
              _buildRouteInfoItem('${routeInfo['duration']} mins', 'Time', Icons.access_time),
              _buildRouteInfoItem(routeInfo['trafficStatus'], 'Traffic', Icons.traffic),
            ],
          ),
          const SizedBox(height: 8),
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
              _buildRouteInfoItem('15.3 km', 'Distance', Icons.flag),
              _buildRouteInfoItem('32 mins', 'Time', Icons.access_time),
              _buildRouteInfoItem('Normal', 'Traffic', Icons.traffic),
            ],
          ),
          const SizedBox(height: 8),
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

  Widget _buildInfoRow(String label, String value, {bool isHazardous = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w500,
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
    required String text,
    required bool isPrimary,
    required Color color,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      child: isPrimary
          ? ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: onPressed,
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          : OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: color,
                side: BorderSide(color: color),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: onPressed,
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
    );
  }

  void _showReportIssueModal() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Report Issue"),
          content: const Text("What issue would you like to report?"),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("Cancel"),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _showSuccessModal("Issue reported successfully!");
              },
              child: const Text("Report"),
            ),
          ],
        );
      },
    );
  }

  void _showCancelConfirmation() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Cancel Task"),
          content: const Text("Are you sure you want to cancel this delivery task?"),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("No"),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _updateCargoStatus('cancelled');
              },
              child: const Text("Yes, Cancel"),
            ),
          ],
        );
      },
    );
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
}

// OSM Service for real-time routing
class OSMService {
  // Geocoding - Convert address to coordinates
  static Future<Map<String, double>?> geocodeAddress(String address) async {
    try {
      final response = await http.get(
        Uri.parse('https://nominatim.openstreetmap.org/search?format=json&q=${Uri.encodeQueryComponent(address)}&limit=1')
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is List && data.isNotEmpty) {
          return {
            'lat': double.parse(data[0]['lat']),
            'lng': double.parse(data[0]['lon']),
          };
        }
      }
      return null;
    } catch (e) {
      print('Geocoding error for $address: $e');
      return null;
    }
  }

  // Routing - Get real-time route info
  static Future<Map<String, dynamic>> getRouteInfo(
    String originAddress, 
    String destinationAddress
  ) async {
    try {
      // Geocode both addresses
      final originCoords = await geocodeAddress(originAddress);
      final destinationCoords = await geocodeAddress(destinationAddress);
      
      if (originCoords == null || destinationCoords == null) {
        return _getFallbackRouteInfo();
      }
      
      // Get route from OSRM
      final response = await http.get(
        Uri.parse('https://router.project-osrm.org/route/v1/driving/'
          '${originCoords['lng']},${originCoords['lat']};'
          '${destinationCoords['lng']},${destinationCoords['lat']}?overview=false')
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['code'] == 'Ok' && data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          final distanceKm = (route['distance'] / 1000); // meters to km
          final durationMinutes = (route['duration'] / 60); // seconds to minutes
          
          // Determine traffic status based on duration (simplified)
          String trafficStatus = _getTrafficStatus(durationMinutes, distanceKm);
          
          return {
            'distance': distanceKm.toStringAsFixed(1),
            'distanceValue': distanceKm,
            'duration': durationMinutes.toStringAsFixed(0),
            'durationValue': durationMinutes,
            'trafficStatus': trafficStatus,
            'originCoords': originCoords,
            'destinationCoords': destinationCoords,
          };
        }
      }
      return _getFallbackRouteInfo();
    } catch (e) {
      print('Routing error: $e');
      return _getFallbackRouteInfo();
    }
  }
  
  static String _getTrafficStatus(double durationMinutes, double distanceKm) {
    final averageSpeed = distanceKm / (durationMinutes / 60);
    
    if (averageSpeed < 20) return 'Heavy Traffic';
    if (averageSpeed < 40) return 'Moderate Traffic';
    return 'Normal';
  }
  
  static Map<String, dynamic> _getFallbackRouteInfo() {
    return {
      'distance': '15.3',
      'distanceValue': 15.3,
      'duration': '32',
      'durationValue': 32.0,
      'trafficStatus': 'Normal',
    };
  }
}