import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:latlong2/latlong.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:flutter_map/flutter_map.dart';
import 'dart:async';
import 'dart:math';
import 'osmservice.dart';

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
  DateTime? _selectedDelayTime;
  LatLng? _courierLocation;
  List<LatLng> _deliveryRoute = [];
  Timer? _locationUpdateTimer;
  String _eta = 'Calculating...';
  double _progress = 0.0;
  Map<String, dynamic>? _routeInfo;

  // Local distance calculation method
  double _calculateDistance(LatLng point1, LatLng point2) {
    const double earthRadius = 6371.0; // Earth's radius in kilometers
    
    final double lat1 = point1.latitude * (pi / 180.0);
    final double lon1 = point1.longitude * (pi / 180.0);
    final double lat2 = point2.latitude * (pi / 180.0);
    final double lon2 = point2.longitude * (pi / 180.0);
    
    final double dLat = lat2 - lat1;
    final double dLon = lon2 - lon1;
    
    final double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1) * cos(lat2) *
        sin(dLon / 2) * sin(dLon / 2);
    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    
    return earthRadius * c;
  }

  @override
  void initState() {
    super.initState();
    _loadCargoAndDeliveryData();
  }

  @override
  void dispose() {
    _locationUpdateTimer?.cancel();
    super.dispose();
  }
  void _startLocationUpdates() {
    // Remove automatic movement - just update ETA periodically
    _locationUpdateTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _updateETA();
    });
  }

  Future<void> _updateCourierLocation() async {
      _updateETA();
  }

  LatLng _getCurrentLocationOnRoute() {
    if (_deliveryRoute.isEmpty) return const LatLng(14.5995, 120.9842);
    
    final totalDistance = _calculateTotalRouteDistance();
    final targetDistance = totalDistance * _progress;
    
    double accumulatedDistance = 0.0;
    
    for (int i = 0; i < _deliveryRoute.length - 1; i++) {
      final segmentDistance = _calculateDistance(
        _deliveryRoute[i], 
        _deliveryRoute[i + 1]
      );
      
      if (accumulatedDistance + segmentDistance >= targetDistance) {
        final ratio = (targetDistance - accumulatedDistance) / segmentDistance;
        return LatLng(
          _deliveryRoute[i].latitude + (_deliveryRoute[i + 1].latitude - _deliveryRoute[i].latitude) * ratio,
          _deliveryRoute[i].longitude + (_deliveryRoute[i + 1].longitude - _deliveryRoute[i].longitude) * ratio,
        );
      }
      accumulatedDistance += segmentDistance;
    }
    
    return _deliveryRoute.last;
  }

  double _calculateTotalRouteDistance() {
    double total = 0.0;
    for (int i = 0; i < _deliveryRoute.length - 1; i++) {
      total += _calculateDistance(_deliveryRoute[i], _deliveryRoute[i + 1]);
    }
    return total;
  }

  void _updateETA() {
    if (_routeInfo == null) {
      setState(() {
        _eta = 'Calculating...';
      });
      return;
    }

    if (_progress >= 1.0) {
      setState(() {
        _eta = 'Arrived';
      });
      return;
    }

    final remainingDistance = (_routeInfo!['distanceValue'] as double) * (1 - _progress);
    final averageSpeed = 50.0; // km/h
    final remainingHours = remainingDistance / averageSpeed;
    final now = DateTime.now();
    final etaTime = now.add(Duration(
    hours: remainingHours.toInt(), 
    minutes: ((remainingHours % 1) * 60).toInt()
  ));
  
    
    setState(() {
      _eta = DateFormat('hh:mm a').format(etaTime);
    });
  }

  Future<void> _loadCargoAndDeliveryData() async {
    try {
      if (widget.cargoData != null) {
        _cargoData = widget.cargoData;
        
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

        await _generateRealisticDeliveryRoute();
        _startLocationUpdates();
        
        setState(() {
          _isLoading = false;
        });
        return;
      }

      final cargoId = widget.cargoId;
      if (cargoId.isNotEmpty) {
        DocumentSnapshot cargoDoc = await _firestore
            .collection('Cargo')
            .doc(cargoId)
            .get();
        
        if (cargoDoc.exists) {
          _cargoData = cargoDoc.data() as Map<String, dynamic>;
        }

        QuerySnapshot deliveryQuery = await _firestore
            .collection('CargoDelivery')
            .where('cargo_id', isEqualTo: cargoId)
            .limit(1)
            .get();
        
        if (deliveryQuery.docs.isNotEmpty) {
          _deliveryData = deliveryQuery.docs.first.data() as Map<String, dynamic>;
        }

        await _generateRealisticDeliveryRoute();
        _startLocationUpdates();
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

  Future<void> _generateRealisticDeliveryRoute() async {
  try {
    // Get coordinates for pickup and destination
    final pickupCoords = await OSMService.geocodeAddress(_pickup);
    final destinationCoords = await OSMService.geocodeAddress(_destination);
    
    LatLng pickupLocation;
    LatLng destinationLocation;
    
    if (pickupCoords != null) {
      pickupLocation = LatLng(pickupCoords['lat']!, pickupCoords['lng']!);
    } else {
      // Fallback to Manila coordinates
      pickupLocation = const LatLng(14.5832, 120.9695);
    }
    
    if (destinationCoords != null) {
      destinationLocation = LatLng(destinationCoords['lat']!, destinationCoords['lng']!);
    } else {
      // Fallback to Batangas coordinates
      destinationLocation = const LatLng(13.7565, 121.0583);
    }

    // Get real route from OSM
    _routeInfo = await OSMService.getRouteWithGeometry(pickupLocation, destinationLocation);
    
    if (_routeInfo != null && _routeInfo!['routePoints'] != null) {
      _deliveryRoute = List<LatLng>.from(_routeInfo!['routePoints']);
    } else {
      // Fallback route
      _deliveryRoute = _generateFallbackRoute(pickupLocation, destinationLocation);
    }

    // Place courier 1km from pickup location (static position)
    _initializeCourierLocationNearPickup(pickupLocation);
    
  } catch (e) {
    print('Error generating route: $e');
    // Fallback route
    final pickupLocation = const LatLng(14.5832, 120.9695);
    final destinationLocation = const LatLng(13.7565, 121.0583);
    _deliveryRoute = _generateFallbackRoute(pickupLocation, destinationLocation);
    _initializeCourierLocationNearPickup(pickupLocation);
  }
}

  void _initializeCourierLocationNearPickup(LatLng pickupLocation) {
    // Place courier 1km away from pickup location along the route
    if (_deliveryRoute.length > 1) {
      // Calculate a point 1km from pickup along the route
      const double initialDistance = 1.0; // 1km
      double accumulatedDistance = 0.0;
      
      for (int i = 0; i < _deliveryRoute.length - 1; i++) {
        final segmentDistance = _calculateDistance(
          _deliveryRoute[i], 
          _deliveryRoute[i + 1]
        );
        
       if (accumulatedDistance + segmentDistance >= initialDistance) {
        final ratio = (initialDistance - accumulatedDistance) / segmentDistance;
        final initialLocation = LatLng(
          _deliveryRoute[i].latitude + (_deliveryRoute[i + 1].latitude - _deliveryRoute[i].latitude) * ratio,
          _deliveryRoute[i].longitude + (_deliveryRoute[i + 1].longitude - _deliveryRoute[i].longitude) * ratio,
        );
          
          setState(() {
          _courierLocation = initialLocation;
          _progress = initialDistance / _calculateTotalRouteDistance();
        });
        
        // Calculate initial ETA immediately after setting position
        _updateETA();
        return;
      }
        accumulatedDistance += segmentDistance;
      }
    }
    
    // Fallback: place near pickup location
    // Fallback: place near pickup location
  setState(() {
    _courierLocation = LatLng(
      pickupLocation.latitude + 0.009, // ~1km north
      pickupLocation.longitude
    );
    _progress = 0.1;
  });
  
  // Calculate initial ETA for fallback position
  _updateETA();
}
  List<LatLng> _generateFallbackRoute(LatLng pickup, LatLng destination) {
    // Generate intermediate points for a realistic route
    return [
      pickup,
      LatLng(
        pickup.latitude + (destination.latitude - pickup.latitude) * 0.25,
        pickup.longitude + (destination.longitude - pickup.longitude) * 0.25,
      ),
      LatLng(
        pickup.latitude + (destination.latitude - pickup.latitude) * 0.5,
        pickup.longitude + (destination.longitude - pickup.longitude) * 0.5,
      ),
      LatLng(
        pickup.latitude + (destination.latitude - pickup.latitude) * 0.75,
        pickup.longitude + (destination.longitude - pickup.longitude) * 0.75,
      ),
      destination,
    ];
  }

  // Getter methods to safely access data
  String get _cargoId {
    return _cargoData?['cargo_id'] ?? widget.cargoId;
  }

  String get _containerNo {
    return _cargoData?['containerNo'] ?? widget.containerNo;
  }

  String get _status {
    // Prioritize delivery data status, then cargo data, then widget status
    return _deliveryData?['status'] ?? _cargoData?['status'] ?? widget.status;
  }

  String get _pickup {
    return _cargoData?['origin'] ?? _cargoData?['pickupLocation'] ?? widget.pickup;
  }

  String get _destination {
    return _cargoData?['destination'] ?? widget.destination;
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

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'delivered':
        return Icons.check_circle_rounded;
      case 'pending':
      case 'scheduled':
        return Icons.schedule_rounded;
      case 'delayed':
        return Icons.watch_later_rounded;
      case 'in-progress':
      case 'in_transit':
      case 'assigned':
        return Icons.local_shipping_rounded;
      default:
        return Icons.help_rounded;
    }
  }

  Future<void> _confirmDelivery() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        _showErrorModal('User not logged in');
        return;
      }

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
      await _firestore.collection('Notifications').add({
        'userId': user.uid,
        'type': 'delivery_completed',
        'message': 'Delivery completed for Container $_containerNo',
        'timestamp': Timestamp.now(),
        'read': false,
        'cargoId': _cargoId,
        'containerNo': _containerNo,
      });

      // Update local state
      setState(() {
        _cargoData?['status'] = 'delivered';
        _deliveryData?['status'] = 'delivered';
        _progress = 1.0;
        _eta = 'Arrived';
      });

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

  Future<void> _reportDelay(String reason, DateTime estimatedTime) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        _showErrorModal('User not logged in');
        return;
      }

      // Update CargoDelivery status
      QuerySnapshot deliveryQuery = await _firestore
          .collection('CargoDelivery')
          .where('cargo_id', isEqualTo: _cargoId)
          .limit(1)
          .get();

      if (deliveryQuery.docs.isNotEmpty) {
        await deliveryQuery.docs.first.reference.update({
          'status': 'delayed',
          'remarks': 'Delay reported: $reason. Estimated new arrival: ${DateFormat('MMM dd, yyyy - HH:mm').format(estimatedTime)}',
          'updated_at': Timestamp.now(),
          'estimated_arrival': Timestamp.fromDate(estimatedTime),
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
              'estimated_arrival': Timestamp.fromDate(estimatedTime),
            });
      }

      // Create delay notification
      await _firestore.collection('Notifications').add({
        'userId': user.uid,
        'type': 'delivery_delayed',
        'message': 'Delivery delayed for Container $_containerNo: $reason',
        'timestamp': Timestamp.now(),
        'read': false,
        'cargoId': _cargoId,
        'containerNo': _containerNo,
      });

      // Update local state
      setState(() {
        _cargoData?['status'] = 'delayed';
        _deliveryData?['status'] = 'delayed';
        _selectedDelayTime = null;
      });

      _showSuccessModal('Delay reported successfully!');
    } catch (e) {
      print('Error reporting delay: $e');
      _showErrorModal('Failed to report delay: $e');
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
                    size: 40,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  "Success!",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
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
                const Text(
                  "Error",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: Center(
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
                'Loading delivery details...',
                style: TextStyle(
                  fontSize: 16,
                  color: Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: LayoutBuilder(
        builder: (context, constraints) {
          bool isTablet = constraints.maxWidth > 600;
          double horizontalPadding = isTablet ? 32.0 : 16.0;
          double mapHeight = isTablet ? 300.0 : 220.0;

          return SingleChildScrollView(
            child: Column(
              children: [
                // Header with back button
                Container(
                  width: double.infinity,
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding, 
                      isTablet ? 40.0 : MediaQuery.of(context).padding.top + 8,
                      horizontalPadding, 
                      16
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
                        Icons.location_on_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
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

                // Live Location Map - Real-time with ETA
                _buildLiveLocationMap(horizontalPadding, mapHeight, isTablet),

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
                      Row(
                        children: [
                          const Icon(
                            Icons.local_shipping_rounded,
                            color: Color(0xFF3B82F6),
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            "Delivery Details",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildDetailRow(
                        Icons.calendar_today_rounded,
                        _deliveryData?['confirmed_at'] != null 
                            ? _formatDate(_deliveryData!['confirmed_at'] as Timestamp)
                            : "Schedule Date", 
                        ""
                      ),
                      _buildDetailRow(Icons.access_time_rounded, widget.time, _containerNo),
                      _buildDetailRow(Icons.place_rounded, _pickup, ""),
                      _buildDetailRow(Icons.flag_rounded, _destination, ""),
                      _buildDetailRow(Icons.person_rounded, "Driver Assigned: ${_deliveryData?['courier_id'] ?? 'Assigned Driver'}", ""),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _getStatusColor(_status).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: _getStatusColor(_status).withOpacity(0.3)),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _getStatusIcon(_status),
                              color: _getStatusColor(_status),
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              "Status: ",
                              style: TextStyle(
                                fontSize: 14,
                                color: Color(0xFF64748B),
                              ),
                            ),
                            Text(
                              _status.toUpperCase(),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: _getStatusColor(_status),
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
                        children: [
                          const Icon(
                            Icons.inventory_2_rounded,
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
                      _buildDetailRow(Icons.type_specimen_rounded, "Container Type: Standard Container", ""),
                      _buildDetailRow(Icons.description_rounded, "Contents: ${_cargoData?['description'] ?? 'Electronics'}", ""),
                      _buildDetailRow(Icons.fitness_center_rounded, "Weight: ${_cargoData?['weight'] ?? '3,200'}kg", ""),
                      _buildDetailRow(Icons.code_rounded, "HS Code: ${_cargoData?['hs_code'] ?? 'N/A'}", ""),
                      _buildDetailRow(Icons.attach_money_rounded, "Value: \$${_cargoData?['value'] ?? '0'}", ""),
                      _buildDetailRow(Icons.format_list_numbered_rounded, "Quantity: ${_cargoData?['quantity'] ?? '1'}", ""),
                      _buildDetailRow(Icons.numbers_rounded, "Item Number: ${_cargoData?['item_number'] ?? 'N/A'}", ""),
                      if (_cargoData?['additional_info'] != null && _cargoData!['additional_info'].toString().isNotEmpty)
                        _buildDetailRow(Icons.info_rounded, "Additional Info: ${_cargoData!['additional_info']}", ""),
                      _buildDetailRow(Icons.warning_rounded, "Hazardous: No", ""),
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

                const SizedBox(height: 32),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildLiveLocationMap(double horizontalPadding, double mapHeight, bool isTablet) {
    return Container(
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
            children: [
              const Icon(
                Icons.map_rounded,
                color: Color(0xFF3B82F6),
                size: 20,
              ),
              const SizedBox(width: 8),
              const Text(
                "Live Location",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1E293B),
                ),
              ),
              const Spacer(),
              const Icon(
                Icons.access_time_rounded,
                color: Color(0xFF64748B),
                size: 16,
              ),
              const SizedBox(width: 4),
              Text(
                "ETA: $_eta",
                style: const TextStyle(
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
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: _courierLocation != null && _deliveryRoute.isNotEmpty
                  ? RealtimeLocationMap(
                      courierLocation: _courierLocation!,
                      deliveryRoute: _deliveryRoute,
                      pickupLocation: _deliveryRoute.first,
                      destinationLocation: _deliveryRoute.last,
                      progress: _progress,
                      calculateDistance: _calculateDistance,
                    )
                  : const Center(
                      child: Text(
                        'Loading map...',
                        style: TextStyle(
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ),
            ),
          ),
          // Progress indicator
          if (_routeInfo != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                children: [
                  LinearProgressIndicator(
                    value: _progress, // Static progress value
                    backgroundColor: const Color(0xFFE2E8F0),
                    valueColor: AlwaysStoppedAnimation<Color>(_getStatusColor(_status)),
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${(_progress * 100).toStringAsFixed(1)}% Complete',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                        ),
                      ),
                      Text(
                        '${_routeInfo!['distance']} km • ${_routeInfo!['duration']} min',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Courier positioned 1km from pickup',
                    style: TextStyle(
                      fontSize: 10,
                      color: const Color(0xFF64748B).withOpacity(0.7),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildActionButtons(BuildContext context, bool isTablet) {
  final bool isDelivered = _status.toLowerCase() == 'delivered';
  final bool isDelayed = _status.toLowerCase() == 'delayed';
  
  return [
    Expanded(
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: isDelivered 
              ? const Color(0xFF94A3B8)
              : const Color(0xFF3B82F6),
          side: BorderSide(
            color: isDelivered
                ? const Color(0xFFE2E8F0)
                : const Color(0xFF3B82F6),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: EdgeInsets.symmetric(vertical: isTablet ? 16 : 12),
        ),
        onPressed: isDelivered ? null : () => _showQRScanner(context),
        icon: Icon(Icons.qr_code_scanner_rounded, 
            size: 20, 
            color: isDelivered ? const Color(0xFF94A3B8) : const Color(0xFF3B82F6)),
        label: Text(
          "Scan QR",
          style: TextStyle(
            fontSize: isTablet ? 16 : 14,
            fontWeight: FontWeight.w600,
            color: isDelivered ? const Color(0xFF94A3B8) : const Color(0xFF3B82F6),
          ),
        ),
      ),
    ),
    SizedBox(width: isTablet ? 12 : 8),
    Expanded(
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: (isDelivered || isDelayed) 
              ? const Color(0xFF94A3B8)
              : const Color(0xFFF59E0B),
          side: BorderSide(
            color: (isDelivered || isDelayed)
                ? const Color(0xFFE2E8F0)
                : const Color(0xFFF59E0B),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: EdgeInsets.symmetric(vertical: isTablet ? 16 : 12),
        ),
        onPressed: (isDelivered || isDelayed) ? null : () => _showReportDelayModal(context),
        icon: Icon(Icons.report_problem_rounded, 
            size: 20, 
            color: (isDelivered || isDelayed) ? const Color(0xFF94A3B8) : const Color(0xFFF59E0B)),
        label: Text(
          "Report Delay",
          style: TextStyle(
            fontSize: isTablet ? 16 : 14,
            fontWeight: FontWeight.w600,
            color: (isDelivered || isDelayed) ? const Color(0xFF94A3B8) : const Color(0xFFF59E0B),
          ),
        ),
      ),
    ),
    SizedBox(width: isTablet ? 12 : 8),
    Expanded(
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: (isDelivered || isDelayed) 
              ? const Color(0xFF94A3B8)
              : const Color(0xFF10B981),
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: EdgeInsets.symmetric(vertical: isTablet ? 16 : 12),
        ),
        onPressed: (isDelivered || isDelayed) ? null : () => _showDeliveryConfirmationModal(context),
        icon: const Icon(Icons.check_circle_rounded, size: 20),
        label: Text(
          "Mark Delivered",
          style: TextStyle(
            fontSize: isTablet ? 16 : 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ),
  ];
}

  Widget _buildDetailRow(IconData icon, String text, String value) {
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
                    Icons.qr_code_scanner_rounded,
                    color: Color(0xFF10B981),
                    size: 40,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  "Scan Successful!",
                  style: TextStyle(
                    fontSize: 20,
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
                        children: [
                          const Icon(
                            Icons.local_shipping_rounded,
                            color: Color(0xFF64748B),
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            "Container:",
                            style: TextStyle(
                              fontSize: 14,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _containerNo,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Icon(
                            Icons.qr_code_rounded,
                            color: Color(0xFF64748B),
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            "Scanned Data:",
                            style: TextStyle(
                              fontSize: 14,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        scannedData,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Scan verified successfully!',
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
                    backgroundColor: const Color(0xFF3B82F6),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(120, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
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

  void _showReportDelayModal(BuildContext context) {
    final bool isDelivered = _status.toLowerCase() == 'delivered';
    final bool isDelayed = _status.toLowerCase() == 'delayed';
    
    if (isDelivered || isDelayed) {
      _showErrorModal('Cannot report delay for ${isDelivered ? 'delivered' : 'already delayed'} cargo.');
      return;
    }

    final reasonController = TextEditingController();

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
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.white, Color(0xFFFAFBFF)],
            ),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.report_problem_rounded,
                      color: Color(0xFFF59E0B),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Report Delay',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.local_shipping_rounded,
                      color: Color(0xFF64748B),
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Container: $_containerNo',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Reason for delay:',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: reasonController,
                decoration: InputDecoration(
                  hintText: 'Enter the reason for delay...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF3B82F6)),
                  ),
                  contentPadding: const EdgeInsets.all(16),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              const Text(
                'Estimated new arrival time:',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _showDateTimePicker,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.calendar_today_rounded,
                        color: _selectedDelayTime != null 
                            ? const Color(0xFF3B82F6)
                            : const Color(0xFF64748B),
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _selectedDelayTime != null
                              ? DateFormat('MMM dd, yyyy - HH:mm').format(_selectedDelayTime!)
                              : 'Select date and time',
                          style: TextStyle(
                            fontSize: 14,
                            color: _selectedDelayTime != null
                                ? const Color(0xFF1E293B)
                                : const Color(0xFF94A3B8),
                            fontWeight: _selectedDelayTime != null
                                ? FontWeight.w500
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        color: const Color(0xFF64748B),
                        size: 16,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF64748B),
                        side: const BorderSide(color: Color(0xFFE2E8F0)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        if (reasonController.text.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Please enter reason for delay'),
                              backgroundColor: Color(0xFFEF4444),
                            ),
                          );
                          return;
                        }
                        if (_selectedDelayTime == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Please select estimated arrival time'),
                              backgroundColor: Color(0xFFEF4444),
                            ),
                          );
                          return;
                        }
                        Navigator.pop(context);
                        _reportDelay(reasonController.text, _selectedDelayTime!);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF59E0B),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 16),
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

  Future<void> _showDateTimePicker() async {
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(hours: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF3B82F6),
            ),
          ),
          child: child!,
        );
      },
    );

    if (pickedDate != null) {
      final TimeOfDay? pickedTime = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(DateTime.now().add(const Duration(hours: 1))),
        builder: (context, child) {
          return Theme(
            data: ThemeData.light().copyWith(
              colorScheme: const ColorScheme.light(
                primary: Color(0xFF3B82F6),
              ),
            ),
            child: child!,
          );
        },
      );

      if (pickedTime != null) {
        setState(() {
          _selectedDelayTime = DateTime(
            pickedDate.year,
            pickedDate.month,
            pickedDate.day,
            pickedTime.hour,
            pickedTime.minute,
          );
        });
      }
    }
  }

  void _showDeliveryConfirmationModal(BuildContext context) {
    final bool isDelivered = _status.toLowerCase() == 'delivered';
    
    if (isDelivered) {
      _showErrorModal('This cargo has already been delivered.');
      return;
    }

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
                    Icons.delivery_dining_rounded,
                    color: Color(0xFF10B981),
                    size: 40,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  "Confirm Delivery",
                  style: TextStyle(
                    fontSize: 20,
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
                        children: [
                          const Icon(
                            Icons.local_shipping_rounded,
                            color: Color(0xFF64748B),
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            "Container:",
                            style: TextStyle(
                              fontSize: 14,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
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
                ),
                const SizedBox(height: 16),
                const Text(
                  'Are you sure you want to mark this delivery as completed?',
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
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          _confirmDelivery();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Text('Confirm'),
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
}

// New Realtime Location Map Widget
class RealtimeLocationMap extends StatelessWidget {
  final LatLng courierLocation;
  final List<LatLng> deliveryRoute;
  final LatLng pickupLocation;
  final LatLng destinationLocation;
  final double progress;
  final double Function(LatLng, LatLng) calculateDistance;

  const RealtimeLocationMap({
    super.key,
    required this.courierLocation,
    required this.deliveryRoute,
    required this.pickupLocation,
    required this.destinationLocation,
    required this.progress,
    required this.calculateDistance,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: double.infinity,
      child: FlutterMap(
        options: MapOptions(
          initialCenter: courierLocation,
          initialZoom: 10.0,
          minZoom: 9.0,
          maxZoom: 15.0,
          interactiveFlags: InteractiveFlag.none,
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.example.cargo_app',
          ),
          
          // Delivery route
          if (deliveryRoute.length > 1)
            PolylineLayer(
              polylines: [
                Polyline(
                  points: deliveryRoute,
                  color: const Color(0xFF3B82F6).withOpacity(0.7),
                  strokeWidth: 4.0,
                ),
                // Completed route portion
                Polyline(
                  points: _getCompletedRoutePortion(),
                  color: const Color(0xFF10B981),
                  strokeWidth: 4.0,
                ),
              ],
            ),
          
          MarkerLayer(
            markers: [
              // Pickup location
              Marker(
                point: pickupLocation,
                width: 32,
                height: 32,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.location_on,
                    color: Color(0xFF10B981),
                    size: 16,
                  ),
                ),
              ),
              
              // Destination location
              Marker(
                point: destinationLocation,
                width: 32,
                height: 32,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.flag,
                    color: Color(0xFFEF4444),
                    size: 16,
                  ),
                ),
              ),
              
              // Courier location (minimized)
              Marker(
                point: courierLocation,
                width: 40, // Reduced from 60
                height: 40, // Reduced from 60
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.4),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.local_shipping,
                    color: Colors.white,
                    size: 18, // Reduced from 24
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<LatLng> _getCompletedRoutePortion() {
    if (progress >= 1.0) return deliveryRoute;
    
    final completedDistance = _calculateTotalRouteDistance() * progress;
    double accumulatedDistance = 0.0;
    List<LatLng> completedPoints = [deliveryRoute.first];
    
    for (int i = 0; i < deliveryRoute.length - 1; i++) {
      final segmentDistance = calculateDistance(
        deliveryRoute[i], 
        deliveryRoute[i + 1]
      );
      
      if (accumulatedDistance + segmentDistance <= completedDistance) {
        completedPoints.add(deliveryRoute[i + 1]);
        accumulatedDistance += segmentDistance;
      } else {
        final ratio = (completedDistance - accumulatedDistance) / segmentDistance;
        final lastPoint = LatLng(
          deliveryRoute[i].latitude + (deliveryRoute[i + 1].latitude - deliveryRoute[i].latitude) * ratio,
          deliveryRoute[i].longitude + (deliveryRoute[i + 1].longitude - deliveryRoute[i].longitude) * ratio,
        );
        completedPoints.add(lastPoint);
        break;
      }
    }
    
    return completedPoints;
  }

  double _calculateTotalRouteDistance() {
    double total = 0.0;
    for (int i = 0; i < deliveryRoute.length - 1; i++) {
      total += calculateDistance(deliveryRoute[i], deliveryRoute[i + 1]);
    }
    return total;
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
                    return const Icon(Icons.flash_off_rounded, color: Colors.grey);
                  case TorchState.on:
                    return const Icon(Icons.flash_on_rounded, color: Colors.yellow);
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.qr_code_scanner_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Container: ${widget.containerNo}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
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
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6B7280),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.cancel_rounded),
              label: const Text('Cancel Scan'),
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