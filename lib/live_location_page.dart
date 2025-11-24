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
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:camera/camera.dart';

// Declared origin constant - Gothong Port in Cebu
const String DECLARED_ORIGIN = "Don Carlos A. Gothong Port Centre, Quezon Boulevard, Pier 4, Cebu City";

class LiveLocationPage extends StatefulWidget {
  final Map<String, dynamic>? containerData;

  const LiveLocationPage({
    super.key,
    this.containerData,
  });

  String get containerId {
    return containerData?['id'] ?? containerData?['containerId'] ?? '';
  }

  String get containerNo {
    return containerData?['containerNumber'] ?? 'N/A';
  }

  String get time {
    return containerData?['scannedAt'] != null 
        ? _formatTime(containerData!['scannedAt'] as Timestamp)
        : '';
  }

  String get pickup {
    return DECLARED_ORIGIN;
  }

  String get destination {
    return containerData?['destination'] ?? 'Delivery Point';
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
  final ImagePicker _imagePicker = ImagePicker();
  Map<String, dynamic>? _containerData;
  Map<String, dynamic>? _deliveryData;
  bool _isLoading = true;
  DateTime? _selectedDelayTime;
  LatLng? _courierLocation;
  LatLng? _actualDestinationLocation;
  List<LatLng> _deliveryRoute = [];
  Timer? _locationUpdateTimer;
  String _eta = 'Calculating...';
  double _progress = 0.0;
  Map<String, dynamic>? _routeInfo;
  String _driverName = 'Loading...';
  bool _isTakingPhoto = false;
  File? _proofOfDeliveryImage;
  bool _hasProofImage = false;

  double _calculateDistance(LatLng point1, LatLng point2) {
    const double earthRadius = 6371.0;
    
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
    _loadContainerAndDeliveryData();
    _checkExistingProofImage();
  }

  @override
  void dispose() {
    _locationUpdateTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkExistingProofImage() async {
    try {
      final containerId = widget.containerId;
      if (containerId.isNotEmpty) {
        QuerySnapshot proofQuery = await _firestore
            .collection('proof_image')
            .where('container_id', isEqualTo: containerId)
            .limit(1)
            .get();
        
        setState(() {
          _hasProofImage = proofQuery.docs.isNotEmpty;
        });
        
        if (_deliveryData != null && _deliveryData!['proof_image_url'] != null) {
          setState(() {
            _hasProofImage = true;
          });
        }
      }
    } catch (e) {
      print('Error checking proof image: $e');
      setState(() {
        _hasProofImage = false;
      });
    }
  }

  void _startLocationUpdates() {
    _locationUpdateTimer?.cancel();
    _locationUpdateTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      _animateCourierAlongRoute();
    });
  }

  void _animateCourierAlongRoute() {
  if (_deliveryRoute.isEmpty || _status.toLowerCase() == 'delivered') {
    print('DEBUG: Cannot animate - route empty or delivered');
    return;
  }

  setState(() {
    _progress += 0.01;
    
    if (_progress >= 1.0) {
      _progress = 1.0;
      print('DEBUG: Courier reached destination');
    }
    
    _courierLocation = _getCurrentLocationOnRoute();
    print('DEBUG: Courier location updated to: ${_courierLocation!.latitude}, ${_courierLocation!.longitude}');
  });
  
  // Debug info
  if (_progress < 0.1) { // Only show debug for first few updates
    _debugLocationInfo();
  }
  
  _updateETA();
}

  // Small helper to print debug information about the route and courier.
  // This method was missing and caused a compile error where it was called.
  void _debugLocationInfo() {
    try {
      final int pointCount = _deliveryRoute.length;
      final double totalDistance = _calculateTotalRouteDistance();
      final String progressPct = (_progress * 100).toStringAsFixed(1);
      print('DEBUG: Route points: $pointCount, totalDistance: ${totalDistance.toStringAsFixed(3)} km, progress: $progressPct%');
      if (_courierLocation != null) {
        print('DEBUG: Courier at ${_courierLocation!.latitude}, ${_courierLocation!.longitude}');
      } else {
        print('DEBUG: Courier location is null');
      }
    } catch (e) {
      print('DEBUG: _debugLocationInfo error: $e');
    }
  }

LatLng _getCurrentLocationOnRoute() {
  if (_deliveryRoute.isEmpty) {
    print('WARNING: Delivery route is empty, using DECLARED_ORIGIN as fallback');
    return const LatLng(10.3119, 123.8859); // Gothong Port coordinates
  }
  
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
      final currentLocation = LatLng(
        _deliveryRoute[i].latitude + (_deliveryRoute[i + 1].latitude - _deliveryRoute[i].latitude) * ratio,
        _deliveryRoute[i].longitude + (_deliveryRoute[i + 1].longitude - _deliveryRoute[i].longitude) * ratio,
      );
      return currentLocation;
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
      final timeFormat = DateFormat('h:mm a');
      final arrivalTime = DateTime.now().toUtc().add(const Duration(hours: 8));
      setState(() {
        _eta = timeFormat.format(arrivalTime);
      });
      return;
    }

    try {
      final totalDistance = _routeInfo!['distanceValue'] as double? ?? 0.0;
      final totalDurationMinutes = _routeInfo!['durationValue'] as double? ?? 0.0;
      
      // Calculate remaining time based on progress
      final remainingMinutes = totalDurationMinutes * (1 - _progress);
      
      // Calculate ETA time (Philippines time = UTC+8)
      final now = DateTime.now().toUtc().add(const Duration(hours: 8));
      final etaTime = now.add(Duration(minutes: remainingMinutes.toInt()));
      
      // Format as time (e.g., "2:30 PM")
      final timeFormat = DateFormat('h:mm a');
      setState(() {
        _eta = timeFormat.format(etaTime);
      });
    } catch (e) {
      print('Error updating ETA: $e');
      setState(() {
        _eta = 'Calculating...';
      });
    }
  }

  Future<void> _loadDriverName() async {
    try {
      final courierId = _deliveryData?['courier_id'];
      if (courierId != null && courierId is String) {
        DocumentSnapshot courierDoc = await _firestore
            .collection('Couriers')
            .doc(courierId)
            .get();
        
        if (courierDoc.exists) {
          final courierData = courierDoc.data() as Map<String, dynamic>;
          final firstName = courierData['first_name'] ?? '';
          final lastName = courierData['last_name'] ?? '';
          
          setState(() {
            _driverName = '$firstName $lastName'.trim();
            if (_driverName.isEmpty) {
              _driverName = 'Assigned Driver';
            }
          });
        } else {
          setState(() {
            _driverName = 'Assigned Driver';
          });
        }
      } else {
        setState(() {
          _driverName = 'Assigned Driver';
        });
      }
    } catch (e) {
      print('Error loading driver name: $e');
      setState(() {
        _driverName = 'Assigned Driver';
      });
    }
  }

  Future<void> _loadContainerAndDeliveryData() async {
  try {
    // Try to derive containerId from widget first (handles case where caller passed container data)
    String containerId = widget.containerId;
    print('DEBUG: initial widget containerId: "$containerId"');
    print('DEBUG: initial widget.containerData: ${widget.containerData}');

    // If widget.containerData contains containerNumber but no id, set containerId to that for lookups
    if ((containerId == null || containerId.isEmpty) && widget.containerData != null) {
      final w = widget.containerData!;
      final altId = (w['containerId'] ?? w['container_id'] ?? w['id'] ?? w['containerNumber'] ?? w['container_no'])?.toString();
      if (altId != null && altId.isNotEmpty) {
        containerId = altId;
        print('DEBUG: derived containerId from widget data: $containerId');
      }
    }

    if (containerId == null || containerId.isEmpty) {
      print('ERROR: Container ID still empty after checking widget data');
      _showErrorModal('Container ID is missing');
      setState(() => _isLoading = false);
      return;
    }

    // Attempt to fetch container doc by id
    print('DEBUG: Looking for container document with ID: $containerId');
    DocumentSnapshot containerDoc = await _firestore.collection('Containers').doc(containerId).get();

    if (containerDoc.exists) {
      _containerData = containerDoc.data() as Map<String, dynamic>;
      print('DEBUG: Container document loaded from Containers/${containerId}');
    } else {
      print('DEBUG: Container doc not found by ID; trying alternate queries...');
      // If not found by doc ID, try searching by containerNumber fields
      QuerySnapshot containerQuery = await _firestore
          .collection('Containers')
          .where('containerNumber', isEqualTo: containerId)
          .limit(1)
          .get();

      if (containerQuery.docs.isEmpty) {
        containerQuery = await _firestore
            .collection('Containers')
            .where('container_no', isEqualTo: containerId)
            .limit(1)
            .get();
      }

      if (containerQuery.docs.isNotEmpty) {
        _containerData = containerQuery.docs.first.data() as Map<String, dynamic>;
        print('DEBUG: Container document found by containerNumber query: ${_containerData?['containerNumber']}');
      } else if (widget.containerData != null) {
        // Use widget-provided data as fallback (caller likely passed the accepted container)
        _containerData = widget.containerData;
        print('DEBUG: Using widget.containerData as fallback: $_containerData');
      } else {
        print('WARNING: No container document or widget data available for id: $containerId');
      }
    }

    // Fetch ContainerDelivery record. Prefer container_id/containerId, but try containerNumber as alternate key.
    QuerySnapshot deliveryQuery = await _firestore
        .collection('ContainerDelivery')
        .where('containerId', isEqualTo: containerId)
        .limit(1)
        .get();

    if (deliveryQuery.docs.isEmpty) {
      print('DEBUG: No ContainerDelivery found by containerId, trying container_id');
      deliveryQuery = await _firestore
          .collection('ContainerDelivery')
          .where('container_id', isEqualTo: containerId)
          .limit(1)
          .get();
    }

    // If still empty, try searching by containerNumber coming from container data
    if (deliveryQuery.docs.isEmpty && _containerData != null) {
      final cnum = _containerData!['containerNumber'] ?? _containerData!['container_no'] ?? _containerData!['containerNo'];
      if (cnum != null) {
        print('DEBUG: Trying ContainerDelivery query by container number: $cnum');
        deliveryQuery = await _firestore
            .collection('ContainerDelivery')
            .where('container_no', isEqualTo: cnum)
            .limit(1)
            .get();

        if (deliveryQuery.docs.isEmpty) {
          deliveryQuery = await _firestore
              .collection('ContainerDelivery')
              .where('containerNumber', isEqualTo: cnum)
              .limit(1)
              .get();
        }
      }
    }

    if (deliveryQuery.docs.isNotEmpty) {
      _deliveryData = deliveryQuery.docs.first.data() as Map<String, dynamic>;
      print('DEBUG: Delivery data loaded: $_deliveryData');
      await _loadDriverName();
    } else {
      print('WARNING: No delivery record found; using container destination as fallback if available');
      final containerDestination = _containerData?['destination'] ?? widget.destination ?? '';
      if (containerDestination == null || containerDestination.isEmpty) {
        _showErrorModal('No delivery record and no destination found in container data. Please check your data.');
        setState(() {
          _isLoading = false;
        });
        return;
      }
      _deliveryData = {
        'status': 'pending',
        'destination': containerDestination,
      };
      print('DEBUG: Built minimal delivery data from container: $_deliveryData');
      setState(() => _driverName = 'Not Assigned');
    }

    // Generate route after delivery data loaded
    await _generateRealisticDeliveryRoute();

    setState(() => _isLoading = false);
  } catch (e, st) {
    print('Error loading container/delivery data: $e\n$st');
    _showErrorModal('Error loading data: $e');
    setState(() {
      _isLoading = false;
      _driverName = 'Assigned Driver';
    });
  }
}

// 3) improved route generation with validation & secondary geocode attempts
Future<void> _generateRealisticDeliveryRoute() async {
  try {
    if (_deliveryData == null) throw Exception('Delivery data missing');

    String destinationAddress = (_deliveryData!['destination'] ?? _containerData?['destination'] ?? '').toString().trim();
    if (destinationAddress.isEmpty) {
      print('DEBUG: Destination empty, attempting to extract coordinates from delivery record if any');
      // try to use lat/lng fields if present in delivery document
      final lat = _deliveryData?['destination_lat'] ?? _deliveryData?['lat'];
      final lng = _deliveryData?['destination_lng'] ?? _deliveryData?['lng'];
      if (lat != null && lng != null) {
        _actualDestinationLocation = LatLng(double.parse(lat.toString()), double.parse(lng.toString()));
        print('DEBUG: Using coordinates from delivery data: $_actualDestinationLocation');
      } else {
        // fallback address
        destinationAddress = 'Cebu City, Philippines';
        print('DEBUG: destinationAddress empty -> using fallback "$destinationAddress"');
      }
    }

    final LatLng pickupLocation = const LatLng(10.3119, 123.8859);
    print('DEBUG: pickupLocation forced to Gothong Port: $pickupLocation');

    LatLng destinationLocation;
    if (_actualDestinationLocation != null) {
      destinationLocation = _actualDestinationLocation!;
    } else {
      // First try standard geocode
      print('DEBUG: geocoding destinationAddress: "$destinationAddress"');
      final destinationCoords = await OSMService.geocodeAddress(destinationAddress);

      // Secondary attempt: append ", Cebu" if geocode fails or returns a very nearby point
      Map<String, double>? coords = destinationCoords;
      if (coords == null) {
        final secAddress = destinationAddress.contains('Cebu') ? destinationAddress : '$destinationAddress, Cebu';
        print('DEBUG: primary geocode failed, trying secondary address: "$secAddress"');
        coords = await OSMService.geocodeAddress(secAddress);
      }

      // If still null, try to extract coords from delivery data
      if (coords == null && _deliveryData != null) {
        final lat = _deliveryData?['destination_lat'] ?? _deliveryData?['lat'];
        final lng = _deliveryData?['destination_lng'] ?? _deliveryData?['lng'];
        if (lat != null && lng != null) {
          coords = {'lat': double.parse(lat.toString()), 'lng': double.parse(lng.toString())};
          print('DEBUG: extracted coords from delivery data: $coords');
        }
      }

      if (coords != null) {
        destinationLocation = LatLng(coords['lat']!, coords['lng']!);
        print('DEBUG: resolved destinationLocation: $destinationLocation');
      } else {
        // use a distinct fallback far from Gothong port so map isn't locked near pickup
        print('WARNING: geocoding failed entirely, using Toledo City fallback to ensure route spans distance');
        destinationLocation = const LatLng(10.3797, 123.6393);
      }
    }

    // Ask OSM for route geometry
    print('DEBUG: requesting route geometry from $pickupLocation to $destinationLocation');
    _routeInfo = await OSMService.getRouteWithGeometry(pickupLocation, destinationLocation);

    bool haveValidRoutePoints = false;
    if (_routeInfo != null && _routeInfo!['routePoints'] != null) {
      final points = List<LatLng>.from(_routeInfo!['routePoints']);
      print('DEBUG: raw routePoints length = ${points.length}');
      // validate points: need at least 2 distinct points and end not equal start
      if (points.length >= 2) {
        // quick check that route spans distance (not identical coords)
        final dist = _calculateDistance(points.first, points.last);
        print('DEBUG: route start->end distance = ${dist} km');
        if (dist > 0.01) { // at least ~10 meters
          _deliveryRoute = points;
          haveValidRoutePoints = true;
        } else {
          print('DEBUG: route start and end too close (likely invalid).');
        }
      } else {
        print('DEBUG: routePoints length <2');
      }
    } else {
      print('DEBUG: no routeInfo.routePoints returned from OSMService');
    }

    if (!haveValidRoutePoints) {
      // If route invalid, construct a deterministic linear route that starts at pickup and goes to destination
      _deliveryRoute = _generateFallbackRoute(pickupLocation, destinationLocation);
      print('DEBUG: generated fallback route with ${_deliveryRoute.length} points');
    } else {
      // Ensure route starts at exact pickup coordinate (replace or insert)
      final double startDistance = _calculateDistance(pickupLocation, _deliveryRoute.first);
      const double thresholdKm = 0.05;
      if (startDistance <= thresholdKm) {
        _deliveryRoute[0] = pickupLocation;
      } else {
        _deliveryRoute.insert(0, pickupLocation);
      }
    }

    setState(() => _actualDestinationLocation = destinationLocation);

    // Force courier to declared origin and start animation
    _initializeCourierLocationNearPickup(pickupLocation);
  } catch (e, st) {
    print('ERROR in _generateRealisticDeliveryRoute: $e\n$st');
    // fallback simple route
    final LatLng pickupLocation = const LatLng(10.3119, 123.8859);
    final LatLng destinationLocation = const LatLng(10.3157, 123.8854);
    _deliveryRoute = _generateFallbackRoute(pickupLocation, destinationLocation);
    setState(() {
      _actualDestinationLocation = destinationLocation;
    });
    _initializeCourierLocationNearPickup(pickupLocation);
    _showErrorModal('Route generation failed, using default route from Gothong Port');
    setState(() => _isLoading = false);
  }
}


  // Remove duplicate or extremely close consecutive points at the start of the route
  void _removeDuplicateStartPoints() {
    if (_deliveryRoute.length < 2) return;
    try {
      final LatLng first = _deliveryRoute[0];
      int removeCount = 0;
      for (int i = 1; i < _deliveryRoute.length; i++) {
        final double d = _calculateDistance(first, _deliveryRoute[i]);
        if (d < 0.01) { // 10 meters
          removeCount++;
        } else {
          break;
        }
      }
      if (removeCount > 0) {
        _deliveryRoute.removeRange(1, 1 + removeCount);
        print('DEBUG: Removed $removeCount near-duplicate start points');
      }
    } catch (e) {
      print('DEBUG: _removeDuplicateStartPoints error: $e');
    }
  }

  void _initializeCourierLocationNearPickup(LatLng pickupLocation) {
  // Force courier to start at exact declared pickup coordinates regardless of route first point
  setState(() {
    _courierLocation = pickupLocation;
    _progress = 0.0;
  });
  
  // If route is empty, ensure there's a minimal route that starts at the pickup
  if (_deliveryRoute.isEmpty) {
    _deliveryRoute = [pickupLocation];
  } else {
    // Make sure first point is the pickup (already ensured in route generation, but enforce again)
    try {
      if (_deliveryRoute.first.latitude != pickupLocation.latitude || _deliveryRoute.first.longitude != pickupLocation.longitude) {
        _deliveryRoute.insert(0, pickupLocation);
      }
    } catch (e) {
      print('DEBUG: Error enforcing first route point: $e');
      _deliveryRoute.insert(0, pickupLocation);
    }
  }
  
  _updateETA();
  _startLocationUpdates();
}

  List<LatLng> _generateFallbackRoute(LatLng pickup, LatLng destination) {
  print('DEBUG: Generating fallback route from pickup: ${pickup.latitude}, ${pickup.longitude}');
  print('DEBUG: Generating fallback route to destination: ${destination.latitude}, ${destination.longitude}');
  
  // Ensure pickup is exactly at Gothong Port
  final LatLng actualPickup = const LatLng(10.3119, 123.8859);
  
  return [
    actualPickup, // Always start from exact Gothong Port
    LatLng(
      actualPickup.latitude + (destination.latitude - actualPickup.latitude) * 0.25,
      actualPickup.longitude + (destination.longitude - actualPickup.longitude) * 0.25,
    ),
    LatLng(
      actualPickup.latitude + (destination.latitude - actualPickup.latitude) * 0.5,
      actualPickup.longitude + (destination.longitude - actualPickup.longitude) * 0.5,
    ),
    LatLng(
      actualPickup.latitude + (destination.latitude - actualPickup.latitude) * 0.75,
      actualPickup.longitude + (destination.longitude - actualPickup.longitude) * 0.75,
    ),
    destination,
  ];
}

  String get _containerId {
    return _containerData?['containerId'] ?? _containerData?['id'] ?? widget.containerId;
  }

  String get _containerNo {
    return _containerData?['containerNumber'] ?? widget.containerNo;
  }

  String get _sealNumber {
    return _containerData?['sealNumber'] ?? 'N/A';
  }

  String get _billOfLading {
    return _containerData?['billOfLading'] ?? 'N/A';
  }

  String get _consigneeName {
    return _containerData?['consigneeName'] ?? 'N/A';
  }

  String get _consigneeAddress {
    return _containerData?['consigneeAddress'] ?? 'N/A';
  }

  String get _consignorName {
    return _containerData?['consignorName'] ?? 'N/A';
  }

  String get _consignorAddress {
    return _containerData?['consignorAddress'] ?? 'N/A';
  }

  String get _priority {
    return _containerData?['priority'] ?? 'Standard';
  }

  String get _deliveredBy {
    return _containerData?['assigned_courier_name'] ?? 
           _deliveryData?['confirmed_by'] ?? 
           _driverName;
  }

  String get _voyageId {
    return _containerData?['voyageId'] ?? 'N/A';
  }

  String get _cargoType {
    return _containerData?['cargoType'] ?? 'General';
  }

  String get _status {
    return _containerData?['status'] ?? _deliveryData?['status'] ?? 'pending';
  }

  String get _pickup {
    return DECLARED_ORIGIN;
  }

  String get _destination {
    return _deliveryData?['destination'] ?? 
           _containerData?['destination'] ?? 
           widget.destination;
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

    // Optional: upload proof image but don't rely on it to update ContainerDelivery status.
    if (_proofOfDeliveryImage != null) {
      try {
        await _uploadProofImage(_proofOfDeliveryImage!);
      } catch (e) {
        print('Warning: proof image upload failed: $e');
      }
    }

    // 1) Update Containers collection (only status)
    await _firestore.collection('Containers').doc(_containerId).update({
      'status': 'delivered',
      'lastUpdated': Timestamp.now(),
    });
    print('Info: Containers/${_containerId} status set to delivered');

    // 2) Find and update ContainerDelivery document with multiple fallback strategies
    DocumentReference? deliveryDocRef;
    bool deliveryUpdated = false;

    // Helper to try a query and return first doc ref if found
    Future<DocumentReference?> tryQuery(String field, dynamic value) async {
      try {
        final q = await _firestore
            .collection('ContainerDelivery')
            .where(field, isEqualTo: value)
            .limit(1)
            .get();
        if (q.docs.isNotEmpty) {
          return q.docs.first.reference;
        }
      } catch (e) {
        print('Debug: query by $field with value $value failed: $e');
      }
      return null;
    }

    final String containerIdStr = _containerId?.toString() ?? '';
    final String containerNoStr = _containerNo?.toString() ?? '';

    // Try multiple common field names and both containerId and container number
    final List<Map<String, dynamic>> attempts = [
      {'field': 'container_id', 'value': containerIdStr},
      {'field': 'containerId', 'value': containerIdStr},
      {'field': 'container_no', 'value': containerNoStr},
      {'field': 'container_number', 'value': containerNoStr},
      {'field': 'containerNumber', 'value': containerNoStr},
    ];

    for (final attempt in attempts) {
      final field = attempt['field'] as String;
      final value = attempt['value'];
      if (value == null || value.toString().isEmpty) continue;
      
      final ref = await tryQuery(field, value);
      if (ref != null) {
        deliveryDocRef = ref;
        print('Info: matched ContainerDelivery by "$field" = "$value"; doc: ${ref.path}');
        break;
      }
    }

    // 3) Update the ContainerDelivery.status if we found a doc
    if (deliveryDocRef != null) {
      try {
        await deliveryDocRef.update({
          'status': 'delivered',
          'updated_at': Timestamp.now(),
          'delivered_at': Timestamp.now(),
          'confirmed_by': user.uid,
        });
        print('Info: Updated ${deliveryDocRef.path} status -> delivered');
        deliveryUpdated = true;
      } catch (e) {
        print('Error updating ContainerDelivery: $e');
      }
    }

    // 4) If no existing ContainerDelivery found, create a new one
    if (deliveryDocRef == null) {
      try {
        final newDeliveryData = {
          'container_id': containerIdStr,
          'container_no': containerNoStr,
          'status': 'delivered',
          'courier_id': user.uid,
          'destination': _destination,
          'created_at': Timestamp.now(),
          'updated_at': Timestamp.now(),
          'delivered_at': Timestamp.now(),
          'confirmed_by': user.uid,
          'proof_image_url': _proofOfDeliveryImage != null ? 'uploaded' : null,
        };
        
        await _firestore.collection('ContainerDelivery').add(newDeliveryData);
        print('Info: Created new ContainerDelivery record for container $containerIdStr');
        deliveryUpdated = true;
      } catch (e) {
        print('Error creating new ContainerDelivery: $e');
      }
    }

    // 5) Create notification
    await _firestore.collection('Notifications').add({
      'userId': user.uid,
      'type': 'delivery_completed',
      'message': 'Delivery completed for Container $_containerNo',
      'timestamp': Timestamp.now(),
      'read': false,
      'containerId': _containerId,
      'containerNo': _containerNo,
    });

    // 6) Update UI state
    setState(() {
      _containerData?['status'] = 'delivered';
      _deliveryData?['status'] = 'delivered';
      _progress = 1.0;
      _eta = DateFormat('h:mm a').format(DateTime.now().toUtc().add(const Duration(hours: 8)));
      _hasProofImage = _hasProofImage || (_proofOfDeliveryImage != null);
    });

    // 7) Show appropriate success message
    if (deliveryUpdated) {
      _showSuccessModal('Delivery marked as completed successfully! Container and delivery records updated.');
    } else {
      _showSuccessModal('Delivery marked as completed! Container status updated. Note: Could not update delivery record.');
    }

    Future.delayed(const Duration(seconds: 2), () {
      Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
    });
  } catch (e, st) {
    print('Error confirming delivery: $e\n$st');
    _showErrorModal('Failed to confirm delivery: $e');
  }
}

  Future<String> _uploadProofImage(File imageFile) async {
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final imageName = 'proof_${_containerId}_$timestamp.jpg';
      
      await _firestore.collection('proof_image').add({
        'container_id': _containerId,
        'image_name': imageName,
        'uploaded_at': Timestamp.now(),
        'uploaded_by': _auth.currentUser?.uid,
        'container_no': _containerNo,
      });

      return 'https://example.com/proof_images/$imageName';
    } catch (e) {
      print('Error uploading proof image: $e');
      throw Exception('Failed to upload proof image');
    }
  }

  Future<void> _reportDelay(String reason, DateTime estimatedTime) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        _showErrorModal('User not logged in');
        return;
      }

      await _firestore
          .collection('Containers')
          .doc(_containerId)
          .update({
            'status': 'delayed',
            'lastUpdated': Timestamp.now(),
          });

      QuerySnapshot deliveryQuery = await _firestore
          .collection('ContainerDelivery')
          .where('container_id', isEqualTo: _containerId)
          .limit(1)
          .get();

      final delayData = {
        'status': 'delayed',
        'remarks': 'Delay reported: $reason. Estimated new arrival: ${DateFormat('MMM dd, yyyy - HH:mm').format(estimatedTime)}',
        'updated_at': Timestamp.now(),
        'estimated_arrival': Timestamp.fromDate(estimatedTime),
        'delay_reason': reason,
      };

      if (deliveryQuery.docs.isNotEmpty) {
        await deliveryQuery.docs.first.reference.update(delayData);
      } else {
        await _firestore.collection('ContainerDelivery').add({
          'container_id': _containerId,
          'courier_id': user.uid,
          ...delayData,
          'created_at': Timestamp.now(),
        });
      }

      await _firestore.collection('Notifications').add({
        'userId': user.uid,
        'type': 'delivery_delayed',
        'message': 'Delivery delayed for Container $_containerNo: $reason',
        'timestamp': Timestamp.now(),
        'read': false,
        'containerId': _containerId,
        'containerNo': _containerNo,
      });

      setState(() {
        _containerData?['status'] = 'delayed';
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

  void _showCameraModal() {
    setState(() {
      _isTakingPhoto = true;
    });

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FullScreenCamera(
          containerNo: _containerNo,
          onPhotoTaken: (imageFile) {
            _handlePhotoTaken(imageFile);
          },
          onCancel: () {
            Navigator.pop(context);
            setState(() {
              _isTakingPhoto = false;
            });
          },
        ),
      ),
    );
  }

  void _handlePhotoTaken(File imageFile) {
    setState(() {
      _proofOfDeliveryImage = imageFile;
      _hasProofImage = true;
      _isTakingPhoto = false;
    });

    _uploadProofImage(imageFile).then((imageUrl) {
      print('Proof image uploaded successfully');
    }).catchError((e) {
      print('Error uploading proof image: $e');
    });

    _showPhotoPreviewModal(imageFile.path);
  }

  void _showPhotoPreviewModal(String imagePath) {
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
                    Icons.photo_camera_rounded,
                    color: Color(0xFF10B981),
                    size: 40,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  "Photo Captured!",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  height: 200,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    image: DecorationImage(
                      image: FileImage(File(imagePath)),
                      fit: BoxFit.cover,
                    ),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
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
                            Icons.access_time_rounded,
                            color: Color(0xFF64748B),
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            "Captured:",
                            style: TextStyle(
                              fontSize: 14,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        DateFormat('MMM dd, yyyy - HH:mm').format(DateTime.now()),
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
                  'Proof of delivery photo captured successfully!',
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
                'Loading container details...',
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
                      const SizedBox(width: 12, height: 0),
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

                _buildLiveLocationMap(horizontalPadding, mapHeight, isTablet),

                const SizedBox(height: 16),

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
                              Icons.inventory_2_rounded,
                              color: Color(0xFF64748B),
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    "Location",
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF94A3B8),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _pickup,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
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
                              Icons.flag_rounded,
                              color: Color(0xFF64748B),
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    "Destination",
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF94A3B8),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _destination,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
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
                              Icons.check_circle_rounded,
                              color: Color(0xFF64748B),
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    "Delivered By",
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF94A3B8),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _deliveredBy,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildDetailRow(
                        Icons.photo_camera_rounded,
                        "Proof of Delivery:",
                        _hasProofImage ? "Captured ✓" : "Not Available"
                      ),
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
                            "Container Information",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildDetailRow(Icons.numbers_rounded, "Container Number:", _containerNo),
                      _buildDetailRow(Icons.security_rounded, "Seal Number:", _sealNumber),
                      _buildDetailRow(Icons.description_rounded, "Bill of Landing:", _billOfLading),
                      _buildDetailRow(Icons.person_rounded, "Consignee:", _consigneeName),
                      _buildDetailRow(Icons.location_on_rounded, "Consignee Address:", _consigneeAddress),
                      _buildDetailRow(Icons.person_outline_rounded, "Consignor:", _consignorName),
                      _buildDetailRow(Icons.business_rounded, "Consignor Address:", _consignorAddress),
                      _buildDetailRow(Icons.flag_rounded, "Priority:", _priority),
                      _buildDetailRow(Icons.local_shipping_rounded, "Delivered By:", _deliveredBy),
                      _buildDetailRow(Icons.sailing_rounded, "Voyage ID:", _voyageId),
                      _buildDetailRow(Icons.category_rounded, "Cargo Type:", _cargoType),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

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
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    "ETA:",
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  Text(
                    _eta,
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
              child: _courierLocation != null && 
        _deliveryRoute.isNotEmpty && 
        _actualDestinationLocation != null
    ? RealtimeLocationMap(
        courierLocation: _courierLocation!,
        deliveryRoute: _deliveryRoute,
        pickupLocation: _deliveryRoute.isNotEmpty ? _deliveryRoute.first : _courierLocation!,
        destinationLocation: _actualDestinationLocation!,
        progress: _progress,
        calculateDistance: _calculateDistance,
      )
    : const Center(
         child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF3B82F6)),
            ),
            SizedBox(height: 12),
            Text(
              'Generating route from Gothong Port...',
              style: TextStyle(
                color: Color(0xFF64748B),
              ),
            ),
          ],
        ),
      )
      ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildActionButtons(BuildContext context, bool isTablet) {
    final bool isDelivered = _status.toLowerCase() == 'delivered';
    final bool isDelayed = _status.toLowerCase() == 'delayed';
    // allow marking delivered even if no proof image present
    final bool hasProof = _hasProofImage || _proofOfDeliveryImage != null;
    
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
          onPressed: isDelivered ? null : _showCameraModal,
          icon: Icon(Icons.photo_camera_rounded, 
              size: 20, 
              color: isDelivered ? const Color(0xFF94A3B8) : const Color(0xFF3B82F6)),
          label: Text(
            "Proof of Delivery",
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
            isDelayed ? "Delivery Delayed" : "Report Delay",
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
          // Removed proof requirement from the enable/disable condition:
          onPressed: (isDelivered || isDelayed) ? null : () => _showDeliveryConfirmationModal(context),
          icon: const Icon(Icons.check_circle_rounded, size: 20),
          label: Text(
            isDelayed ? "Cannot Deliver" : "Mark Delivered",
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
                color: Colors.black,
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

  void _showReportDelayModal(BuildContext context) {
    final bool isDelivered = _status.toLowerCase() == 'delivered';
    final bool isDelayed = _status.toLowerCase() == 'delayed';
    
    if (isDelivered || isDelayed) {
      _showErrorModal('Cannot report delay for ${isDelivered ? 'delivered' : 'already delayed'} container.');
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
    );

    if (pickedDate != null) {
      final TimeOfDay? pickedTime = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(DateTime.now().add(const Duration(hours: 1))),
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
      _showErrorModal('This container has already been delivered.');
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
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Icon(
                            Icons.photo_camera_rounded,
                            color: Color(0xFF64748B),
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            "Proof of Delivery:",
                            style: TextStyle(
                              fontSize: 14,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _hasProofImage ? "Captured ✓" : "Not Available",
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _hasProofImage ? const Color(0xFF10B981) : const Color(0xFF64748B),
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

// Full Screen Camera Widget
class FullScreenCamera extends StatefulWidget {
  final String containerNo;
  final Function(File) onPhotoTaken;
  final Function() onCancel;

  const FullScreenCamera({
    super.key,
    required this.containerNo,
    required this.onPhotoTaken,
    required this.onCancel,
  });

  @override
  State<FullScreenCamera> createState() => _FullScreenCameraState();
}

class _FullScreenCameraState extends State<FullScreenCamera> {
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  int _selectedCameraIndex = 0;
  bool _isInitializing = true;
  bool _isCapturing = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  Future<void> _initializeCamera() async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      _cameras = await availableCameras();
      
      if (_cameras != null && _cameras!.isNotEmpty) {
        _cameraController = CameraController(
          _cameras![_selectedCameraIndex],
          ResolutionPreset.medium,
        );
        
        await _cameraController!.initialize().then((_) {
          if (!mounted) return;
          setState(() {
            _isInitializing = false;
          });
        }).catchError((e) {
          print('Camera initialization error: $e');
          if (!mounted) return;
          setState(() {
            _isInitializing = false;
          });
        });
      } else {
        setState(() {
          _isInitializing = false;
        });
      }
    } catch (e) {
      print('Error initializing camera: $e');
      if (!mounted) return;
      setState(() {
        _isInitializing = false;
      });
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras == null || _cameras!.length <= 1 || _isCapturing) return;

    final newCameraIndex = (_selectedCameraIndex + 1) % _cameras!.length;
    
    await _cameraController?.dispose();
    
    setState(() {
      _selectedCameraIndex = newCameraIndex;
      _isInitializing = true;
    });

    _cameraController = CameraController(
      _cameras![_selectedCameraIndex],
      ResolutionPreset.medium,
    );

    try {
      await _cameraController!.initialize();
      if (!mounted) return;
      setState(() {
        _isInitializing = false;
      });
    } catch (e) {
      print('Error switching camera: $e');
      if (!mounted) return;
      setState(() {
        _isInitializing = false;
      });
    }
  }

  Future<void> _takePicture() async {
    if (_cameraController == null || 
        !_cameraController!.value.isInitialized || 
        _isCapturing) {
      return;
    }

    setState(() {
      _isCapturing = true;
    });

    try {
      final XFile picture = await _cameraController!.takePicture();
      
      final File imageFile = File(picture.path);
      if (await imageFile.exists()) {
        if (mounted) {
          Navigator.pop(context);
          widget.onPhotoTaken(imageFile);
        }
      } else {
        throw Exception('Captured image file not found');
      }
    } catch (e) {
      print('Error taking picture: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error taking picture: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCapturing = false;
        });
      }
    }
  }

  Widget _buildCameraPreview() {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
            SizedBox(height: 16),
            Text(
              'Initializing Camera...',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      height: double.infinity,
      child: CameraPreview(_cameraController!),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.camera_alt_rounded,
            color: Colors.white54,
            size: 64,
          ),
          const SizedBox(height: 16),
          const Text(
            'Camera not available',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _initializeCamera,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            if (!_isInitializing && _cameraController != null && _cameraController!.value.isInitialized)
              _buildCameraPreview()
            else if (_isInitializing)
              const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Initializing Camera...',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              )
            else
              _buildErrorState(),

            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.7),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: widget.onCancel,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.5),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'Proof of Delivery - ${widget.containerNo}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    const SizedBox(width: 40),
                  ],
                ),
              ),
            ),

            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withOpacity(0.7),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        const SizedBox(width: 48),
                        _isCapturing
                            ? const SizedBox(
                                width: 70,
                                height: 70,
                                child: Center(
                                  child: CircularProgressIndicator(
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                ),
                              )
                            : GestureDetector(
                                onTap: _takePicture,
                                child: Container(
                                  width: 70,
                                  height: 70,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 3,
                                    ),
                                  ),
                                  child: Container(
                                    margin: const EdgeInsets.all(6),
                                    decoration: const BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                              ),
                        if (_cameras != null && _cameras!.length > 1 && !_isCapturing)
                          GestureDetector(
                            onTap: _switchCamera,
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.5),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.cameraswitch_rounded,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                          )
                        else
                          const SizedBox(width: 48),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text(
                      _isCapturing ? 'Capturing...' : 'Position the container in frame and tap to capture',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            if (!_isCapturing)
              Positioned(
                top: MediaQuery.of(context).size.height * 0.25,
                left: 24,
                right: 24,
                child: Container(
                  height: MediaQuery.of(context).size.height * 0.3,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Colors.white.withOpacity(0.7),
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.photo_camera_rounded,
                        color: Colors.white54,
                        size: 40,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.containerNo,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// Realtime Location Map Widget
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
    // Calculate bounds to fit both pickup and destination
    final bounds = LatLngBounds.fromPoints([pickupLocation, destinationLocation]);
    
    return SizedBox(
      width: double.infinity,
      height: double.infinity,
      child: FlutterMap(
        options: MapOptions(
          initialCenter: bounds.center,
          initialZoom: _calculateOptimalZoom(bounds),
          minZoom: 9.0,
          maxZoom: 15.0,
          interactiveFlags: InteractiveFlag.none,
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.example.cargo_app',
          ),
          
          // Display the full route
          if (deliveryRoute.length > 1)
            PolylineLayer(
              polylines: [
                Polyline(
                  points: deliveryRoute,
                  color: const Color(0xFF3B82F6).withOpacity(0.7),
                  strokeWidth: 4.0,
                ),
              ],
            ),
          
          MarkerLayer(
            markers: [
              // Pickup marker
              Marker(
                point: pickupLocation,
                width: 40,
                height: 40,
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
                    Icons.inventory_2_rounded,
                    color: Color(0xFF3B82F6),
                    size: 20,
                  ),
                ),
              ),
              
              // Destination marker
              Marker(
                point: destinationLocation,
                width: 40,
                height: 40,
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
                    Icons.location_on_rounded,
                    color: Color(0xFFEF4444),
                    size: 20,
                  ),
                ),
              ),
              
              // Courier marker
              Marker(
                point: courierLocation,
                width: 40,
                height: 40,
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
                    size: 18,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  double _calculateOptimalZoom(LatLngBounds bounds) {
    // Calculate a zoom level that fits both points comfortably
    final distance = calculateDistance(bounds.northWest, bounds.southEast);
    if (distance > 50) return 10.0;
    if (distance > 20) return 11.0;
    if (distance > 10) return 12.0;
    if (distance > 5) return 13.0;
    return 14.0;
  }

}