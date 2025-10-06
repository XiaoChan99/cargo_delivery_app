import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:latlong2/latlong.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'livemap_page.dart';

class LiveLocationPage extends StatefulWidget {
  final Map<String, dynamic>? cargoData;

  const LiveLocationPage({
    super.key,
    this.cargoData,
  });

  // Getters for backward compatibility
  String get cargoId {
    return cargoData?['cargo_id'] ?? cargoData?['id'] ?? '';
  }

  String get containerNo {
    return cargoData?['containerNo'] ?? 'CONT-${cargoData?['item_number'] ?? 'N/A'}';
  }

  String get time {
    return cargoData?['confirmed_at'] != null 
        ? _formatTime(cargoData!['confirmed_at'] as Timestamp)
        : '';
  }

  String get pickup {
    return cargoData?['origin'] ?? cargoData?['pickupLocation'] ?? 'Port Terminal';
  }

  String get destination {
    return cargoData?['destination'] ?? 'Delivery Point';
  }

  String get status {
    return cargoData?['status'] ?? 'pending';
  }

  String _formatTime(Timestamp timestamp) {
    final date = timestamp.toDate();
    final hour = date.hour % 12;
    final period = date.hour >= 12 ? 'PM' : 'AM';
    return '${hour == 0 ? 12 : hour}:${date.minute.toString().padLeft(2, '0')} $period';
  }

  @override
  State<LiveLocationPage> createState() => _LiveLocationPageState();
}

class _LiveLocationPageState extends State<LiveLocationPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  Map<String, dynamic>? _cargoData;
  Map<String, dynamic>? _deliveryData;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCargoAndDeliveryData();
  }

  Future<void> _loadCargoAndDeliveryData() async {
    try {
      // If cargoData is provided, use it directly
      if (widget.cargoData != null) {
        _cargoData = widget.cargoData;
        
        // Load additional delivery data if needed
        final cargoId = widget.cargoId;
        if (cargoId.isNotEmpty) {
          QuerySnapshot deliveryQuery = await _firestore
              .collection('CargoDelivery')
              .where('cargo_id', isEqualTo: cargoId)
              .limit(1)
              .get();
          
          if (deliveryQuery.docs.isNotEmpty) {
            _deliveryData = deliveryQuery.docs.first.data() as Map<String, dynamic>;
          }
        }

        setState(() {
          _isLoading = false;
        });
        return;
      }

      // Otherwise, load data using cargoId (for backward compatibility)
      final cargoId = widget.cargoId;
      if (cargoId.isNotEmpty) {
        // Load cargo data
        DocumentSnapshot cargoDoc = await _firestore
            .collection('Cargo')
            .doc(cargoId)
            .get();
        
        if (cargoDoc.exists) {
          _cargoData = cargoDoc.data() as Map<String, dynamic>;
        }

        // Load delivery data from CargoDelivery collection
        QuerySnapshot deliveryQuery = await _firestore
            .collection('CargoDelivery')
            .where('cargo_id', isEqualTo: cargoId)
            .limit(1)
            .get();
        
        if (deliveryQuery.docs.isNotEmpty) {
          _deliveryData = deliveryQuery.docs.first.data() as Map<String, dynamic>;
        }
      }

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading cargo and delivery data: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Getter methods to safely access data
  String get _cargoId {
    return _cargoData?['cargo_id'] ?? widget.cargoId;
  }

  String get _containerNo {
    return _cargoData?['containerNo'] ?? widget.containerNo;
  }

  String get _status {
    return _cargoData?['status'] ?? widget.status;
  }

  String get _pickup {
    return _cargoData?['origin'] ?? _cargoData?['pickupLocation'] ?? widget.pickup;
  }

  String get _destination {
    return _cargoData?['destination'] ?? widget.destination;
  }

  Future<void> _confirmDelivery() async {
    try {
      // Update CargoDelivery status
      QuerySnapshot deliveryQuery = await _firestore
          .collection('CargoDelivery')
          .where('cargo_id', isEqualTo: _cargoId)
          .limit(1)
          .get();

      if (deliveryQuery.docs.isNotEmpty) {
        await deliveryQuery.docs.first.reference.update({
          'status': 'delivered',
          'confirmed_at': Timestamp.now(),
          'remarks': 'Delivery completed successfully',
        });
      }

      // Update Cargo status
      if (_cargoId.isNotEmpty) {
        await _firestore
            .collection('Cargo')
            .doc(_cargoId)
            .update({
              'status': 'delivered',
              'updated_at': Timestamp.now(),
            });
      }

      // Create delivery completed notification
      final user = _auth.currentUser;
      if (user != null) {
        await _firestore.collection('notifications').add({
          'userId': user.uid,
          'type': 'delivery_completed',
          'message': 'Delivery completed for Container $_containerNo',
          'timestamp': Timestamp.now(),
          'read': false,
          'cargoId': _cargoId,
          'containerNo': _containerNo,
        });
      }

      _showSuccessModal('Delivery marked as completed successfully!');
      
      // Navigate back to home after delay
      Future.delayed(const Duration(seconds: 2), () {
        Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
      });
    } catch (e) {
      print('Error confirming delivery: $e');
      _showErrorModal('Failed to confirm delivery: $e');
    }
  }

  Future<void> _reportDelay(String reason, String estimatedTime) async {
    try {
      // Update CargoDelivery status
      QuerySnapshot deliveryQuery = await _firestore
          .collection('CargoDelivery')
          .where('cargo_id', isEqualTo: _cargoId)
          .limit(1)
          .get();

      if (deliveryQuery.docs.isNotEmpty) {
        await deliveryQuery.docs.first.reference.update({
          'status': 'delayed',
          'remarks': 'Delay reported: $reason. Estimated new arrival: $estimatedTime',
          'updated_at': Timestamp.now(),
        });
      }

      // Update Cargo status
      if (_cargoId.isNotEmpty) {
        await _firestore
            .collection('Cargo')
            .doc(_cargoId)
            .update({
              'status': 'delayed',
              'updated_at': Timestamp.now(),
            });
      }

      // Create delay notification
      final user = _auth.currentUser;
      if (user != null) {
        await _firestore.collection('notifications').add({
          'userId': user.uid,
          'type': 'delivery_delayed',
          'message': 'Delivery delayed for Container $_containerNo: $reason',
          'timestamp': Timestamp.now(),
          'read': false,
          'cargoId': _cargoId,
          'containerNo': _containerNo,
        });
      }

      _showSuccessModal('Delay reported successfully!');
    } catch (e) {
      print('Error reporting delay: $e');
      _showErrorModal('Failed to report delay: $e');
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
        return const Color(0xFFEF4444);
      case 'in-progress':
      case 'in_transit':
      case 'assigned':
        return const Color(0xFF3B82F6);
      default:
        return const Color(0xFF3B82F6);
    }
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    // Create realistic drivable routes using major highways and roads
    final LatLng manilaPort = const LatLng(14.5832, 120.9695); // Manila South Harbor
    final LatLng batangasPort = const LatLng(13.7565, 121.0583); // Batangas Port
    final LatLng cebuPort = const LatLng(10.3157, 123.8854); // Cebu Port
    final LatLng davaoPort = const LatLng(7.1378, 125.6143); // Davao Sasa Port
    final LatLng subicPort = const LatLng(14.7942, 120.2799); // Subic Port
    
    List<LatLng> deliveryRoute = [
      manilaPort,
      const LatLng(14.5200, 121.0000), // Entering SLEX
      const LatLng(14.4500, 121.0200), // SLEX towards Calamba
      const LatLng(14.2000, 121.1000), // STAR Tollway entrance
      const LatLng(14.0000, 121.1500), // STAR Tollway
      const LatLng(13.9000, 121.1200), // Approaching Batangas
      batangasPort,
    ];
    
    List<LatLng> ports = [manilaPort, cebuPort, davaoPort, subicPort, batangasPort];

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: LayoutBuilder(
        builder: (context, constraints) {
          bool isTablet = constraints.maxWidth > 600;
          double horizontalPadding = isTablet ? 32.0 : 16.0;
          double mapHeight = isTablet ? 250.0 : 150.0;

          return SingleChildScrollView(
            child: Column(
              children: [
                // Header with back button
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding, 
                    isTablet ? 80.0 : 60.0, 
                    horizontalPadding, 
                    24
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
                        "Live Location",
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

                // Live Location Map
                Container(
                  margin: EdgeInsets.symmetric(horizontal: horizontalPadding),
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
                          const Text(
                            "Live Location",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                          const Text(
                            "ETA: 11:15 AM",
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Container(
                        height: mapHeight,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: LiveMapWidget(
                          deliveryRoute: deliveryRoute,
                          ports: ports,
                          truckLocation: const LatLng(14.3000, 121.0800), // Current truck position
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Container Delivery Details
                Container(
                  margin: EdgeInsets.symmetric(horizontal: horizontalPadding),
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
                      const Text(
                        "Container Delivery Details",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildDetailRow(
                        _deliveryData?['confirmed_at'] != null 
                            ? _formatDate(_deliveryData!['confirmed_at'] as Timestamp)
                            : "Schedule Date", 
                        ""
                      ),
                      _buildDetailRow(widget.time, _containerNo),
                      _buildDetailRow(_pickup, ""),
                      _buildDetailRow(_destination, ""),
                      _buildDetailRow("Driver Assigned: ${_deliveryData?['courier_id'] ?? 'Assigned Driver'}", ""),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Text(
                            "Status: ",
                            style: TextStyle(
                              fontSize: 14,
                              color: Color(0xFF64748B),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: _getStatusColor(_status).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              _status.toUpperCase(),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: _getStatusColor(_status),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Container Info
                Container(
                  margin: EdgeInsets.symmetric(horizontal: horizontalPadding),
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
                      const Text(
                        "Cargo Information",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildDetailRow("Container Type: Standard Container", ""),
                      _buildDetailRow("Contents: ${_cargoData?['description'] ?? 'Electronics'}", ""),
                      _buildDetailRow("Weight: ${_cargoData?['weight'] ?? '3,200'}kg", ""),
                      _buildDetailRow("HS Code: ${_cargoData?['hs_code'] ?? 'N/A'}", ""),
                      _buildDetailRow("Value: \$${_cargoData?['value'] ?? '0'}", ""),
                      _buildDetailRow("Quantity: ${_cargoData?['quantity'] ?? '1'}", ""),
                      _buildDetailRow("Item Number: ${_cargoData?['item_number'] ?? 'N/A'}", ""),
                      if (_cargoData?['additional_info'] != null && _cargoData!['additional_info'].toString().isNotEmpty)
                        _buildDetailRow("Additional Info: ${_cargoData!['additional_info']}", ""),
                      Row(
                        children: [
                          const Text(
                            "Hazardous: ",
                            style: TextStyle(
                              fontSize: 14,
                              color: Color(0xFF64748B),
                            ),
                          ),
                          Text(
                            "No",
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Attachment
                Container(
                  margin: EdgeInsets.symmetric(horizontal: horizontalPadding),
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
                      const Text(
                        "Attachment",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        "Delivery Photo Placeholder, Bill of Lading, Delivery Receipt",
                        style: TextStyle(
                          fontSize: 14,
                          color: Color(0xFF64748B),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      Container(
                        height: 80,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.add,
                            size: 32,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Action Buttons
                Container(
                  margin: EdgeInsets.symmetric(horizontal: horizontalPadding),
                  child: isTablet 
                    ? Row(
                        children: _buildActionButtons(context, isTablet),
                      )
                    : Column(
                        children: [
                          Row(
                            children: _buildActionButtons(context, isTablet).sublist(0, 2),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: _buildActionButtons(context, isTablet).sublist(2),
                          ),
                        ],
                      ),
                ),

                const SizedBox(height: 100),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: _buildBottomNavigation(context, 1),
    );
  }

  List<Widget> _buildActionButtons(BuildContext context, bool isTablet) {
    return [
      Expanded(
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF3B82F6),
            side: const BorderSide(color: Color(0xFF3B82F6)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            padding: EdgeInsets.symmetric(vertical: isTablet ? 16 : 12),
          ),
          onPressed: () => _showQRScanner(context),
          child: Text(
            "Scan",
            style: TextStyle(
              fontSize: isTablet ? 16 : 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
      SizedBox(width: isTablet ? 12 : 8),
      Expanded(
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFFF59E0B),
            side: const BorderSide(color: Color(0xFFF59E0B)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            padding: EdgeInsets.symmetric(vertical: isTablet ? 16 : 12),
          ),
          onPressed: () => _showReportDelayModal(context),
          child: Text(
            "Report Delay",
            style: TextStyle(
              fontSize: isTablet ? 16 : 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
      SizedBox(width: isTablet ? 12 : 8),
      Expanded(
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF10B981),
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            padding: EdgeInsets.symmetric(vertical: isTablet ? 16 : 12),
          ),
          onPressed: () => _showDeliveryConfirmationModal(context),
          child: Text(
            "Mark as Delivered",
            style: TextStyle(
              fontSize: isTablet ? 16 : 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    ];
  }

  Widget _buildDetailRow(String text, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF64748B),
              ),
            ),
          ),
          if (value.isNotEmpty)
            Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1E293B),
              ),
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
              Navigator.pushReplacementNamed(context, '/home');
              break;
            case 1:
              // Already on schedule page
              break;
            case 2:
              Navigator.pushReplacementNamed(context, '/livemap');
              break;
            case 3:
              Navigator.pushReplacementNamed(context, '/settings');
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

  void _showQRScanner(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => QRScannerPage(
          containerNo: _containerNo,
          onScanComplete: (String scannedData) {
            _handleScanResult(context, scannedData);
          },
        ),
      ),
    );
  }

  void _handleScanResult(BuildContext context, String scannedData) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Scan Result'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Container: $_containerNo'),
              const SizedBox(height: 8),
              Text('Scanned Data: $scannedData'),
              const SizedBox(height: 16),
              const Text('Scan verified successfully!'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  void _showReportDelayModal(BuildContext context) {
    final reasonController = TextEditingController();
    final timeController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Report Delay',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              const Text('Container:'),
              Text(
                _containerNo,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: reasonController,
                decoration: const InputDecoration(
                  labelText: 'Reason for delay',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: timeController,
                decoration: const InputDecoration(
                  labelText: 'Estimated new arrival time',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        if (reasonController.text.isEmpty || timeController.text.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Please fill all fields')),
                          );
                          return;
                        }
                        Navigator.pop(context);
                        _reportDelay(reasonController.text, timeController.text);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF59E0B),
                      ),
                      child: const Text('Submit Report'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDeliveryConfirmationModal(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Delivery'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Container: $_containerNo'),
              const SizedBox(height: 8),
              const Text('Are you sure you want to mark this delivery as completed?'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _confirmDelivery();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
              ),
              child: const Text('Confirm'),
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

class LiveMapWidget extends StatelessWidget {
  final LatLng? truckLocation;
  final List<LatLng> deliveryRoute;
  final List<LatLng> ports;
  final VoidCallback? onTruckTap;

  const LiveMapWidget({
    super.key,
    this.truckLocation,
    required this.deliveryRoute,
    required this.ports,
    this.onTruckTap,
  });

  @override
  Widget build(BuildContext context) {
    final LatLng currentTruckLocation = truckLocation ?? const LatLng(10.3157, 123.8854);

    return SizedBox(
      width: double.infinity,
      height: double.infinity,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(0),
        child: FlutterMap(
          options: MapOptions(
            initialCenter: currentTruckLocation,
            initialZoom: 10.0,
            minZoom: 5.0,
            maxZoom: 18.0,
            interactiveFlags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.cargo_app',
              maxNativeZoom: 19,
            ),
            
            // Delivery route
            if (deliveryRoute.length > 1)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: deliveryRoute,
                    color: const Color(0xFFEF4444).withOpacity(0.7),
                    strokeWidth: 4.0,
                    borderColor: Colors.white.withOpacity(0.5),
                    borderStrokeWidth: 1.0,
                  ),
                ],
              ),
            
            MarkerLayer(
              markers: [
                Marker(
                  point: ports[0],
                  width: 80,
                  height: 80,
                  child: const MapMarker(
                    label: "Manila Port",
                    color: Color(0xFF10B981),
                  ),
                ),
                Marker(
                  point: ports[1],
                  width: 80,
                  height: 80,
                  child: const MapMarker(
                    label: "Cebu Port",
                    color: Color(0xFF3B82F6),
                  ),
                ),
                Marker(
                  point: ports[2],
                  width: 80,
                  height: 80,
                  child: const MapMarker(
                    label: "Batangas Port",
                    color: Color(0xFF10B981),
                  ),
                ),
                
                Marker(
                  point: currentTruckLocation,
                  width: 80,
                  height: 80,
                  child: MapMarker(
                    label: "Your Truck",
                    color: const Color(0xFFF59E0B),
                    isTruck: true,
                    onTap: onTruckTap,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class MapMarker extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  final bool isTruck;
  final VoidCallback? onTap;

  const MapMarker({
    super.key,
    required this.label,
    required this.color,
    this.icon = Icons.location_on,
    this.isTruck = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1E293B),
              ),
            ),
          ),
          if (isTruck)
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  Icon(
                    Icons.local_shipping,
                    color: Colors.white,
                    size: 24,
                  ),
                  Positioned(
                    left: 4,
                    top: 6,
                    child: Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.yellow[700],
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Icon(
              icon,
              color: color,
              size: 24,
            ),
        ],
      ),
    );
  }
}

class LegendItem extends StatelessWidget {
  final Color color;
  final String label;

  const LegendItem({
    super.key,
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: Color(0xFF64748B),
            ),
          ),
        ],
      )
    );
  }
}

class QRScannerPage extends StatefulWidget {
  final String containerNo;
  final Function(String) onScanComplete;

  const QRScannerPage({
    super.key,
    required this.containerNo,
    required this.onScanComplete,
  });

  @override
  State<QRScannerPage> createState() => _QRScannerPageState();
}

class _QRScannerPageState extends State<QRScannerPage> {
  MobileScannerController cameraController = MobileScannerController();
  bool isScanned = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan QR Code'),
        backgroundColor: const Color(0xFF3B82F6),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: ValueListenableBuilder(
              valueListenable: cameraController.torchState,
              builder: (context, state, child) {
                switch (state) {
                  case TorchState.off:
                    return const Icon(Icons.flash_off, color: Colors.grey);
                  case TorchState.on:
                    return const Icon(Icons.flash_on, color: Colors.yellow);
                }
              },
            ),
            onPressed: () => cameraController.toggleTorch(),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: const Color(0xFF3B82F6),
            child: Column(
              children: [
                Text(
                  'Container: ${widget.containerNo}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Position the QR code or barcode within the frame',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          Expanded(
            child: MobileScanner(
              controller: cameraController,
              onDetect: (capture) {
                if (!isScanned) {
                  final List<Barcode> barcodes = capture.barcodes;
                  for (final barcode in barcodes) {
                    if (barcode.rawValue != null) {
                      setState(() {
                        isScanned = true;
                      });
                      widget.onScanComplete(barcode.rawValue!);
                      Navigator.pop(context);
                      break;
                    }
                  }
                }
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6B7280),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 48),
              ),
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    cameraController.dispose();
    super.dispose();
  }
}