import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'homepage.dart';
import 'schedulepage.dart';
import 'settings_page.dart';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'osmservice.dart';
import 'package:url_launcher/url_launcher.dart';

class LiveMapPage extends StatefulWidget {
  final String? containerId;
  final String? destination;
  final String? location;

  const LiveMapPage({
    super.key,
    this.containerId,
    this.destination,
    this.location,
  });

  @override
  State<LiveMapPage> createState() => _LiveMapPageState();
}

class _LiveMapPageState extends State<LiveMapPage> {
  final MapController _mapController = MapController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  List<Map<String, dynamic>> _availableContainers = [];
  List<Map<String, dynamic>> _acceptedDeliveries = [];
  Map<String, dynamic>? _selectedContainerDetails;
  
  bool _showContainerDetails = false;
  bool _isLoadingContainer = false;
  bool _isLoadingRoutes = false;
  
  List<DeliveryRouteData> _deliveryRoutes = [];
  late StreamSubscription<QuerySnapshot>? _containerSubscription;
  late StreamSubscription<QuerySnapshot>? _deliverySubscription;

  // Courier position along the route (1km from pickup) OR live courier position from ContainerDelivery if present
  Map<String, LatLng> _courierRoutePositions = {};

  // Declared origin constant
  static const String DECLARED_ORIGIN = "Don Carlos A. Gothong Port Centre, Quezon Boulevard, Pier 4, Cebu City.";

  // Ensure we center on Cebu once after initial loading completes
  bool _centeredAfterLoad = false;

  @override
  void initState() {
    super.initState();
    // Set initial position to Cebu immediately
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        try {
          _mapController.move(const LatLng(10.3157, 123.8854), 11.0);
        } catch (e) {
          // Map controller may not be ready yet; it's safe to ignore here
          print('Initial map move error: $e');
        }
      }
    });
    _loadAvailableAndAcceptedContainers();
    _setupRealtimeListeners();
  }

  Future<void> _loadAvailableAndAcceptedContainers() async {
    setState(() {
      _isLoadingContainer = true;
      _isLoadingRoutes = true;
    });

    try {
      final user = _auth.currentUser;
      if (user == null) {
        setState(() {
          _isLoadingContainer = false;
          _isLoadingRoutes = false;
        });
        return;
      }

      // Load ONLY containers with "ready_for_delivery" status
      QuerySnapshot containerSnapshot = await _firestore
          .collection('Containers')
          .where('status', isEqualTo: 'ready_for_delivery')
          .get();

      // Load ALL container deliveries (we need this to determine assignments & tracking info)
      QuerySnapshot containerDeliverySnapshot = await _firestore
          .collection('ContainerDelivery')
          .get();

      Set<String> assignedContainerIds = {};
      Map<String, String> containerDeliveryStatus = {};
      Map<String, String> containerDeliveryIds = {}; // Store delivery IDs
      Map<String, String> containerDeliveryCouriers = {}; // Store which courier accepted the container
      Map<String, String> containerDeliveredBy = {}; // Store deliveredBy from ContainerDelivery
      
      // Build lookup maps from ContainerDelivery (this ensures tracking & statuses come from ContainerDelivery)
      for (var doc in containerDeliverySnapshot.docs) {
        var deliveryData = doc.data() as Map<String, dynamic>;
        
        final containerId = _getContainerId(deliveryData['containerId']);
        if (containerId.isNotEmpty) {
          assignedContainerIds.add(containerId);
          containerDeliveryStatus[containerId] = deliveryData['status']?.toString() ?? 'pending';
          containerDeliveryIds[containerId] = doc.id;
          containerDeliveryCouriers[containerId] = deliveryData['courier_id']?.toString() ?? '';
          containerDeliveredBy[containerId] = deliveryData['deliveredBy']?.toString() ?? '';
        }
      }

      List<Map<String, dynamic>> availableContainers = [];
      
      for (var doc in containerSnapshot.docs) {
        var containerData = doc.data() as Map<String, dynamic>;
        String containerId = doc.id;
        
        // Ensure container has "ready_for_delivery" status in Containers collection
        if (containerData['status'] != 'ready_for_delivery') {
          continue;
        }

        // Determine status: prefer status from ContainerDelivery, otherwise default to available
        String status = 'available';
        if (containerDeliveryStatus.containsKey(containerId)) {
          status = containerDeliveryStatus[containerId]!;
        }

        // Skip delivered containers
        if (status == 'delivered') {
          continue;
        }

        // Skip containers accepted by other couriers (show only those not taken or taken by current user)
        if (containerDeliveryCouriers.containsKey(containerId) && 
            containerDeliveryCouriers[containerId] != user.uid && 
            containerDeliveryCouriers[containerId]!.isNotEmpty) {
          continue;
        }
        
        // Get courier name - FIRST check ContainerDelivery, then fallback to Containers
        String deliveredByName = 'Not Assigned';
        
        if (containerDeliveryCouriers.containsKey(containerId) && 
            containerDeliveryCouriers[containerId]!.isNotEmpty) {
          deliveredByName = await _getCourierName(containerDeliveryCouriers[containerId]!);
        }
        else if (containerDeliveredBy.containsKey(containerId) && 
                 containerDeliveredBy[containerId]!.isNotEmpty) {
          deliveredByName = await _getCourierName(containerDeliveredBy[containerId]!);
        }
        else if (containerData['deliveredBy'] != null && containerData['deliveredBy'].isNotEmpty) {
          deliveredByName = await _getCourierName(containerData['deliveredBy']);
        }
        
        // Get coordinates for the DESTINATION of all containers (fallback to Containers.consigneeAddress)
        final destCoords = await _getCoordinatesForAddress(containerData['consigneeAddress'] ?? 'Cebu City');
        
        Map<String, dynamic> container = {
          'containerId': containerId,
          'containerNo': containerData['containerNumber'] ?? 'N/A',
          'destination': containerData['consigneeAddress'] ?? 'Unknown',
          'origin': DECLARED_ORIGIN, // Always use declared origin
          'description': containerData['cargoType'] ?? 'N/A',
          'weight': 0.0, // Not available in Containers collection
          'value': 0.0, // Not available in Containers collection
          'status': status, // Use status from ContainerDelivery or 'available'
          'cargoType': containerData['cargoType'],
          'consigneeName': containerData['consigneeName'],
          'consigneeAddress': containerData['consigneeAddress'],
          'deliveredBy': deliveredByName,
          'sealNumber': containerData['sealNumber'],
          'voyageId': containerData['voyageId'],
          'priority': containerData['priority'],
          'destination_coords': destCoords, // Store DESTINATION coordinates for mapping
          // Add delivery_id if this container has been accepted
          if (containerDeliveryIds.containsKey(containerId))
            'delivery_id': containerDeliveryIds[containerId],
          // Add courier_id for reference
          if (containerDeliveryCouriers.containsKey(containerId))
            'courier_id': containerDeliveryCouriers[containerId],
          ...containerData,
        };
        availableContainers.add(container);
      }

      // Load accepted deliveries from ContainerDelivery (these are authoritative for deliveries accepted by couriers)
      QuerySnapshot acceptedSnapshot = await _firestore
          .collection('ContainerDelivery')
          .where('courier_id', isEqualTo: user.uid)
          .get();

      List<Map<String, dynamic>> acceptedDeliveries = [];
      List<DeliveryRouteData> routes = [];
      
      for (var doc in acceptedSnapshot.docs) {
        var deliveryData = doc.data() as Map<String, dynamic>;
        String status = deliveryData['status']?.toString() ?? 'pending';
        
        // Skip cancelled AND delivered deliveries for route drawing/tracking
        if (status == 'cancelled' || status == 'delivered') continue;
        
        // Use the containerId field from ContainerDelivery
        final containerId = _getContainerId(deliveryData['containerId']);
        if (containerId.isEmpty) continue;
        
        DocumentSnapshot containerDoc = await _firestore
            .collection('Containers')
            .doc(containerId)
            .get();
        
        if (!containerDoc.exists) continue;
        var containerData = containerDoc.data() as Map<String, dynamic>;
        
        // Build delivery map (authoritative fields come from ContainerDelivery but augment with Containers)
        Map<String, dynamic> delivery = {
          'delivery_id': doc.id,
          'containerId': containerId,
          'containerNo': containerData['containerNumber'] ?? 'N/A',
          'destination': containerData['consigneeAddress'] ?? 'Unknown',
          'origin': DECLARED_ORIGIN,
          'status': status,
          'description': containerData['cargoType'] ?? 'N/A',
          'weight': 0.0,
          'value': 0.0,
          'cargoType': containerData['cargoType'],
          'consigneeName': containerData['consigneeName'],
          'consigneeAddress': containerData['consigneeAddress'],
          'deliveredBy': await _getCourierName(user.uid),
          'sealNumber': containerData['sealNumber'],
          'voyageId': containerData['voyageId'],
          'priority': containerData['priority'],
          'courier_id': user.uid,
          ...containerData,
          ...deliveryData, // ensure fields from ContainerDelivery (like live_coords) are present
        };

        acceptedDeliveries.add(delivery);

        // Determine origin/destination coordinates, prefer coordinates present in ContainerDelivery doc
        LatLng originCoords = const LatLng(10.3157, 123.8854); // default Cebu
        LatLng destCoords = const LatLng(10.3157, 123.8854);

        LatLng? originFromDelivery = _parseLatLngFromDeliveryData(deliveryData, [
          'origin_coords',
          'origin',
          'pickup_location',
          'pickup_coords',
          'pickup_latlng',
          'pickup_lat',
        ]);
        LatLng? destFromDelivery = _parseLatLngFromDeliveryData(deliveryData, [
          'destination_coords',
          'destination',
          'dropoff_location',
          'dropoff_coords',
          'dropoff_latlng',
          'dropoff_lat',
        ]);

        if (originFromDelivery != null) {
          originCoords = OSMService.validateAndCorrectCoordinates(originFromDelivery, const LatLng(10.3157, 123.8854));
        } else {
          // fallback to declared origin constant (validated)
          originCoords = OSMService.validateAndCorrectCoordinates(
            await _getCoordinatesForAddress(DECLARED_ORIGIN),
            const LatLng(10.3157, 123.8854),
          );
        }

        if (destFromDelivery != null) {
          destCoords = OSMService.validateAndCorrectCoordinates(destFromDelivery, const LatLng(10.3157, 123.8854));
        } else {
          // fallback to container consigneeAddress or geocoded
          destCoords = OSMService.validateAndCorrectCoordinates(
            await _getCoordinatesForAddress(delivery['destination'] ?? containerData['consigneeAddress'] ?? 'Cebu City'),
            const LatLng(10.3157, 123.8854),
          );
        }

        // Attempt to get route using OSMService (geometric route + metadata)
        var routeInfo = await OSMService.getRouteWithGeometry(originCoords, destCoords);

        // If route doesn't seem accurate, try alternative routing
        if (!routeInfo['routeFound'] || routeInfo['routeAccuracy'] == 'low') {
          final alternativeRoute = await OSMService.getAlternativeRoute(originCoords, destCoords);
          if (alternativeRoute['routeFound']) {
            routeInfo = alternativeRoute;
          }
        }

        routes.add(DeliveryRouteData(
          origin: originCoords,
          destination: destCoords,
          delivery: delivery,
          routePoints: (routeInfo['routePoints'] as List<dynamic>?)
                  ?.map((p) => p is LatLng ? p : LatLng(p.latitude ?? p['lat'], p.longitude ?? p['lng']))
                  .cast<LatLng>()
                  .toList() ??
              [],
          distance: routeInfo['distance']?.toString() ?? '0',
          duration: routeInfo['duration']?.toString() ?? '0',
          trafficStatus: routeInfo['trafficStatus']?.toString() ?? 'Unknown',
          isInternational: routeInfo['isInternational'] ?? false,
          routeFound: routeInfo['routeFound'] ?? false,
          routeAccuracy: routeInfo['routeAccuracy'] ?? 'low',
        ));

        // Determine courier position:
        // Priority: live courier location in ContainerDelivery (fields like live_coords, current_location, lat/lng)
        LatLng? liveCourierCoords = _parseLatLngFromDeliveryData(deliveryData, [
          'live_coords',
          'current_location',
          'current_coords',
          'courier_coords',
          'courier_location',
          'latlng',
          'current_lat',
        ]);

        if (liveCourierCoords != null) {
          // Validate and use live coords
          _courierRoutePositions[containerId] = OSMService.validateAndCorrectCoordinates(liveCourierCoords, originCoords);
        } else {
          // Calculate courier position 1km from pickup along the route
          if (routeInfo['routePoints'] != null && (routeInfo['routePoints'] as List).isNotEmpty) {
            final pts = (routeInfo['routePoints'] as List).map((p) {
              if (p is LatLng) return p;
              if (p is Map) {
                final lat = (p['lat'] ?? p['latitude']) as num?;
                final lng = (p['lng'] ?? p['longitude']) as num?;
                if (lat != null && lng != null) return LatLng(lat.toDouble(), lng.toDouble());
              }
              return const LatLng(10.3157, 123.8854);
            }).toList();
            final courierPosition = _calculateCourierPositionAlongRoute(pts, 1.0);
            _courierRoutePositions[containerId] = courierPosition;
          } else {
            // default to origin
            _courierRoutePositions[containerId] = originCoords;
          }
        }
      }

      setState(() {
        _availableContainers = availableContainers;
        _acceptedDeliveries = acceptedDeliveries;
        _deliveryRoutes = routes;
        _isLoadingContainer = false;
        _isLoadingRoutes = false;
      });

      // After loading, ensure map shows Cebu (if nothing to show) or zoom to fit routes
      if (!_centeredAfterLoad) {
        _centeredAfterLoad = true;
        if (_deliveryRoutes.isEmpty) {
          // No routes: just center on Cebu
          try {
            _mapController.move(const LatLng(10.3157, 123.8854), 11.0);
          } catch (e) {
            print('Map move error: $e');
          }
        } else {
          _zoomToFitRoutes();
        }
      } else {
        if (routes.isNotEmpty) {
          _zoomToFitRoutes();
        }
      }
    } catch (e) {
      print('[v0] Error loading containers: $e');
      setState(() {
        _isLoadingContainer = false;
        _isLoadingRoutes = false;
      });
    }
  }

  // Get courier name from Couriers collection
  Future<String> _getCourierName(String courierId) async {
    try {
      DocumentSnapshot courierDoc = await _firestore
          .collection('Couriers')
          .doc(courierId)
          .get();
      
      if (courierDoc.exists) {
        var courierData = courierDoc.data() as Map<String, dynamic>;
        String firstName = courierData['first_name'] ?? '';
        String lastName = courierData['last_name'] ?? '';
        return '$firstName $lastName'.trim();
      }
    } catch (e) {
      print('Error fetching courier name: $e');
    }
    return 'Unknown Courier';
  }

  // FIXED: Helper method to handle both String and int containerId types
  String _getContainerId(dynamic containerIdValue) {
    if (containerIdValue == null) return '';
    if (containerIdValue is String) return containerIdValue;
    if (containerIdValue is int) return containerIdValue.toString();
    return containerIdValue.toString();
  }

  // Calculate courier position 1km from pickup along the route
  LatLng _calculateCourierPositionAlongRoute(List<LatLng> routePoints, double distanceKm) {
    if (routePoints.isEmpty) {
      return const LatLng(10.3157, 123.8854); // Default to Cebu if no route points
    }

    final Distance distanceCalculator = Distance();
    double accumulatedDistance = 0.0;
    
    // Start from the first point (pickup)
    for (int i = 0; i < routePoints.length - 1; i++) {
      final currentPoint = routePoints[i];
      final nextPoint = routePoints[i + 1];
      
      // Calculate distance between current and next point in kilometers
      final segmentDistance = distanceCalculator(currentPoint, nextPoint) / 1000;
      
      // Check if we've reached or exceeded 1km
      if (accumulatedDistance + segmentDistance >= distanceKm) {
        // Calculate how far along this segment we need to go
        final remainingDistance = distanceKm - accumulatedDistance;
        final ratio = remainingDistance / segmentDistance;
        
        // Interpolate between current and next point
        return LatLng(
          currentPoint.latitude + (nextPoint.latitude - currentPoint.latitude) * ratio,
          currentPoint.longitude + (nextPoint.longitude - currentPoint.longitude) * ratio,
        );
      }
      
      accumulatedDistance += segmentDistance;
    }
    
    // If we haven't reached 1km by the end of the route, return the last point
    return routePoints.last;
  }

  void _zoomToFitRoutes() {
    if (_deliveryRoutes.isEmpty) return;

    Future.delayed(const Duration(milliseconds: 500), () {
      try {
        // Collect all points to show
        List<LatLng> allPoints = [];
        
        // Add courier route positions
        allPoints.addAll(_courierRoutePositions.values);
        
        // Add available container positions (DESTINATION coordinates) - only valid non-Cebu locations
        for (var container in _availableContainers) {
          if (container['destination_coords'] != null && 
              _isValidNonDefaultLocation(container['destination_coords'])) {
            allPoints.add(container['destination_coords']);
          }
        }
        
        for (var route in _deliveryRoutes) {
          allPoints.add(route.origin);
          allPoints.add(route.destination);
          if (route.routePoints.isNotEmpty) {
            // Add some key points from long routes
            if (route.routePoints.length > 10) {
              for (int i = 0; i < route.routePoints.length; i += route.routePoints.length ~/ 10) {
                allPoints.add(route.routePoints[i]);
              }
            } else {
              allPoints.addAll(route.routePoints);
            }
          }
        }

        if (allPoints.length < 2) return;

        // Calculate bounds
        double minLat = allPoints.first.latitude;
        double maxLat = allPoints.first.latitude;
        double minLng = allPoints.first.longitude;
        double maxLng = allPoints.first.longitude;

        for (var point in allPoints) {
          minLat = point.latitude < minLat ? point.latitude : minLat;
          maxLat = point.latitude > maxLat ? point.latitude : maxLat;
          minLng = point.longitude < minLng ? point.longitude : minLng;
          maxLng = point.longitude > maxLng ? point.longitude : maxLng;
        }

        // Add padding to bounds
        final latPadding = (maxLat - minLat) * 0.1;
        final lngPadding = (maxLng - minLng) * 0.1;
        
        minLat -= latPadding;
        maxLat += latPadding;
        minLng -= lngPadding;
        maxLng += lngPadding;

        // Calculate center
        final center = LatLng(
          (minLat + maxLat) / 2,
          (minLng + maxLng) / 2,
        );

        // Calculate zoom level
        final latDiff = maxLat - minLat;
        final lngDiff = maxLng - minLng;
        final maxDiff = latDiff > lngDiff ? latDiff : lngDiff;
        
        double zoom = _calculateZoomLevel(maxDiff);
        
        // Ensure reasonable zoom bounds
        zoom = zoom.clamp(3.0, 15.0);
        
        _mapController.move(center, zoom);
      } catch (e) {
        print('Error zooming to fit routes: $e');
        // Fallback: center on first route
        if (_deliveryRoutes.isNotEmpty) {
          _mapController.move(_deliveryRoutes.first.origin, 10.0);
        }
      }
    });
  }

  double _calculateZoomLevel(double maxDiff) {
    if (maxDiff > 100) return 3.0;
    if (maxDiff > 50) return 4.0;
    if (maxDiff > 20) return 5.0;
    if (maxDiff > 10) return 6.0;
    if (maxDiff > 5) return 7.0;
    if (maxDiff > 2) return 8.0;
    if (maxDiff > 1) return 9.0;
    if (maxDiff > 0.5) return 10.0;
    if (maxDiff > 0.2) return 11.0;
    if (maxDiff > 0.1) return 12.0;
    return 13.0;
  }

  Future<LatLng> _getCoordinatesForAddress(String address) async {
    try {
      // First try enhanced geocoding
      final enhancedResult = await OSMService.geocodeAddressWithDetails(address);
      if (enhancedResult['lat'] != null && enhancedResult['lng'] != null) {
        return LatLng(enhancedResult['lat'], enhancedResult['lng']);
      }
    } catch (e) {
      print('Enhanced geocoding error for $address: $e');
    }

    // Fallback to local database with Cebu as default
    final locationMap = {
      // Cebu and nearby areas
      'Don Carlos A. Gothong Port Centre, Quezon Boulevard, Pier 4, Cebu City': const LatLng(10.3119, 123.8853),
      'Cebu': const LatLng(10.3157, 123.8854),
      'Cebu City': const LatLng(10.3157, 123.8854),
      'Dalaguete': const LatLng(9.8956, 123.5344),
      'Casey, Dalaguete, Cebu': const LatLng(9.8956, 123.5344),
      'Alcoy': const LatLng(9.7100, 123.5069),
      'Bilibid': const LatLng(14.6500, 120.9833), // Assuming this is in Manila area
      
      // Other Philippines locations
      'Manila': const LatLng(14.5995, 120.9842),
      'Manila City': const LatLng(14.5995, 120.9842),
      'Davao': const LatLng(7.1907, 125.4553),
      'Davao City': const LatLng(7.1907, 125.4553),
      'Batangas': const LatLng(13.7565, 121.0583),
      'Subic': const LatLng(14.7942, 120.2799),
      'Quezon City': const LatLng(14.6760, 121.0437),
      'Makati': const LatLng(14.5547, 121.0244),
    };
    
    for (var key in locationMap.keys) {
      if (address.toLowerCase().contains(key.toLowerCase())) {
        return locationMap[key]!;
      }
    }
    
    return const LatLng(10.3157, 123.8854); // Default to Cebu
  }

  void _setupRealtimeListeners() {
    _containerSubscription = _firestore
        .collection('Containers')
        .where('status', isEqualTo: 'ready_for_delivery')
        .snapshots() // Listen only to ready_for_delivery containers
        .listen((snapshot) {
      _loadAvailableAndAcceptedContainers();
    });

    final user = _auth.currentUser;
    if (user != null) {
      _deliverySubscription = _firestore
          .collection('ContainerDelivery')
          .where('courier_id', isEqualTo: user.uid)
          .snapshots()
          .listen((snapshot) {
        _loadAvailableAndAcceptedContainers();
      });
    }
  }

  void _showContainerDetailsForMarker(Map<String, dynamic> containerData) {
    setState(() {
      _selectedContainerDetails = containerData;
      _showContainerDetails = true;
    });
  }

  void _hideContainerDetailsModal() {
    setState(() {
      _showContainerDetails = false;
      _selectedContainerDetails = null;
    });
  }

  // Helper method to check if location is valid and not the default Cebu location
  bool _isValidNonDefaultLocation(LatLng coords) {
    final cebu = const LatLng(10.3157, 123.8854);
    final distance = Distance();
    // Only show locations that are at least 1km away from Cebu default
    return distance(coords, cebu) > 1000; // 1km in meters
  }

  @override
  void dispose() {
    _containerSubscription?.cancel();
    _deliverySubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Stack(
        children: [
          Stack(
            children: [
              LiveMapWidget(
                mapController: _mapController,
                deliveryRoutes: _deliveryRoutes,
                availableContainers: _availableContainers,
                acceptedDeliveries: _acceptedDeliveries,
                courierRoutePositions: _courierRoutePositions,
                onDestinationTap: _showContainerDetailsForMarker,
                isLoadingRoutes: _isLoadingRoutes,
              ),
              
              Positioned(
                bottom: 16,
                right: 16,
                child: Column(
                  children: [
                    _buildMapControl(Icons.add, () {
                      _mapController.move(
                        _mapController.camera.center,
                        _mapController.camera.zoom + 1,
                      );
                    }),
                    const SizedBox(height: 8),
                    _buildMapControl(Icons.remove, () {
                      _mapController.move(
                        _mapController.camera.center,
                        _mapController.camera.zoom - 1,
                      );
                    }),
                    const SizedBox(height: 8),
                    _buildMapControl(Icons.my_location, () {
                      // Always return to Cebu when location button is pressed
                      _mapController.move(const LatLng(10.3157, 123.8854), 11.0);
                    }),
                  ],
                ),
              ),

              Positioned(
                bottom: 16,
                left: 16,
                child: _buildRouteLegend(),
              ),

              if (_isLoadingRoutes)
                Positioned(
                  top: MediaQuery.of(context).padding.top + 100,
                  left: 0,
                  right: 0,
                  child: const Center(
                    child: Column(
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 8),
                        Text(
                          'Loading routes...',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),

          if (_showContainerDetails && _selectedContainerDetails != null)
            Positioned.fill(
              child: Container(
                color: Colors.black54,
                child: Center(
                  child: _buildContainerDetailsModal(),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: _buildBottomNavigation(context, 2),
    );
  }

  Widget _buildRouteLegend() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Map Legend',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 8),
          LegendItem(
            color: const Color(0xFF10B981),
            label: 'Pickup Point',
            icon: Icons.location_on,
          ),
          LegendItem(
            color: const Color(0xFFEF4444),
            label: 'Delivery Point',
            icon: Icons.location_on,
          ),
          LegendItem(
            color: const Color(0xFF8B5CF6),
            label: 'Available Container',
            icon: Icons.local_shipping,
          ),
          LegendItem(
            color: const Color(0xFFEF4444),
            label: 'Courier on Route',
            icon: Icons.local_shipping,
          ),
          LegendItem(
            color: const Color(0xFF8B5CF6),
            label: 'International Route',
            icon: Icons.language,
          ),
          LegendItem(
            color: const Color(0xFF6B7280),
            label: 'Cancelled Container',
            icon: Icons.local_shipping,
            isCancelled: true,
          ),
        ],
      ),
    );
  }

  Widget _buildContainerDetailsModal() {
    final container = _selectedContainerDetails!;
    final isAccepted = _acceptedDeliveries.any((d) => d['containerId'] == container['containerId']);
    final isCancelled = container['status'] == 'cancelled';
    final routeData = _deliveryRoutes.firstWhere(
      (r) => r.delivery['containerId'] == container['containerId'],
      orElse: () => DeliveryRouteData(
        origin: const LatLng(0, 0),
        destination: const LatLng(0, 0),
        delivery: {},
        routePoints: [],
        distance: '0',
        duration: '0',
        trafficStatus: 'Unknown',
        isInternational: false,
        routeFound: false,
        routeAccuracy: 'low',
      ),
    );
    
    final courierOnRoute = _courierRoutePositions.containsKey(container['containerId']);
    
    return Container(
      width: MediaQuery.of(context).size.width * 0.9,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header with close button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.local_shipping, // now using truck icon for container header
                      color: isCancelled ? const Color(0xFF6B7280) : 
                             (routeData.isInternational ? const Color(0xFFEF4444) : const Color(0xFF3B82F6)),
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          container['containerNo'] ?? 'N/A',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: isCancelled ? const Color(0xFF6B7280) : const Color(0xFF1E293B),
                          ),
                        ),
                        if (isCancelled)
                          Container(
                            margin: const EdgeInsets.only(top: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4444).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.cancel, size: 12, color: const Color(0xFFEF4444)),
                                const SizedBox(width: 4),
                                Text(
                                  'DELIVERY CANCELLED',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFFEF4444),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (!isCancelled && routeData.isInternational)
                          Container(
                            margin: const EdgeInsets.only(top: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4444).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.language, size: 12, color: Color(0xFFEF4444)),
                                SizedBox(width: 4),
                                Text(
                                  'International Delivery',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFFEF4444),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (!isCancelled && courierOnRoute)
                          Container(
                            margin: const EdgeInsets.only(top: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4444).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.local_shipping, size: 12, color: const Color(0xFFEF4444)),
                                const SizedBox(width: 4),
                                Text(
                                  'Courier En Route (1km from pickup)',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFFEF4444),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                IconButton(
                  onPressed: _hideContainerDetailsModal,
                  icon: const Icon(Icons.close, size: 24),
                ),
              ],
            ),
            
            const SizedBox(height: 20),
            
            // Container Information Section 
            _buildInfoSection(
              title: "Container Information",
              icon: Icons.local_shipping,
              children: [
                _buildDetailRow(Icons.description, "Cargo Type", container['cargoType'] ?? 'N/A'),
                _buildDetailRow(Icons.numbers, "Container Number", container['containerNo']?.toString() ?? 'N/A'),
                _buildDetailRow(Icons.person, "Consignee Name", container['consigneeName']?.toString() ?? 'N/A'),
                _buildDetailRow(Icons.local_shipping, "Assigned Courier", container['confirmed_by'] ?? 'Not Assigned'),
                _buildDetailRow(Icons.security, "Seal Number", container['sealNumber']?.toString() ?? 'N/A'),
                _buildDetailRow(Icons.confirmation_number, "Voyage ID", container['voyageId']?.toString() ?? 'N/A'),
                _buildDetailRow(Icons.priority_high, "Priority", container['priority']?.toString().toUpperCase() ?? 'NORMAL'),
                _buildDetailRow(
                  Icons.info, 
                  "Status", 
                  container['status']?.toUpperCase() ?? 'PENDING',
                  valueColor: isCancelled ? const Color(0xFFEF4444) : 
                             (container['status'] == 'delivered' ? const Color(0xFF10B981) : null),
                ),
              ],
            ),
            
            const SizedBox(height: 20),
            
            // Route Information Section
            if (!isCancelled)
            _buildInfoSection(
              title: "Route Information",
              icon: Icons.route,
              children: [
                _buildDetailRow(Icons.location_on, "Origin", DECLARED_ORIGIN),
                _buildDetailRow(Icons.flag, "Destination", container['consigneeAddress'] ?? 'N/A'),
                if (isAccepted && routeData.distance != '0') ...[
                  _buildDetailRow(Icons.space_dashboard, "Distance", "${routeData.distance} km"),
                  _buildDetailRow(Icons.access_time, "Estimated Time", "${routeData.duration} min"),
                  _buildDetailRow(Icons.traffic, "Traffic", routeData.trafficStatus),
                  if (routeData.routeAccuracy == 'high')
                    _buildDetailRow(Icons.verified, "Route Accuracy", "High Precision"),
                  if (routeData.routeAccuracy == 'low')
                    _buildDetailRow(Icons.warning, "Route Accuracy", "Approximate Route"),
                  if (courierOnRoute)
                    _buildDetailRow(Icons.local_shipping, "Courier Status", "1km from pickup - En route"),
                  if (routeData.isInternational)
                    _buildDetailRow(Icons.language, "Route Type", "International Delivery"),
                  if (!routeData.routeFound)
                    _buildDetailRow(Icons.warning, "Note", "Route approximation - actual path may vary"),
                ],
              ],
            ),
            
            if (isCancelled)
            _buildInfoSection(
              title: "Delivery Status",
              icon: Icons.info,
              children: [
                _buildDetailRow(
                  Icons.cancel, 
                  "Status", 
                  "CANCELLED",
                  valueColor: const Color(0xFFEF4444),
                ),
                _buildDetailRow(
                  Icons.location_on, 
                  "Container Location", 
                  "At destination: ${container['consigneeAddress'] ?? 'N/A'}",
                ),
                _buildDetailRow(
                  Icons.note, 
                  "Note", 
                  "This delivery has been cancelled. The container is located at its destination.",
                ),
              ],
            ),
            
            const SizedBox(height: 20),
            
            // Close Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _hideContainerDetailsModal,
                style: ElevatedButton.styleFrom(
                  backgroundColor: isCancelled ? const Color(0xFF6B7280) : const Color(0xFF3B82F6),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  "Close Details",
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
    );
  }

  Widget _buildInfoSection({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: const Color(0xFF3B82F6)),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1E293B),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...children,
      ],
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: const Color(0xFF64748B)),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: Text(
              "$label:",
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
                color: valueColor ?? const Color(0xFF1E293B),
                fontWeight: valueColor != null ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapControl(IconData icon, VoidCallback onPressed, {String? tooltip}) {
    return Tooltip(
      message: tooltip ?? '',
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: IconButton(
          onPressed: onPressed,
          icon: Icon(
            icon,
            color: const Color(0xFF3B82F6),
            size: 20,
          ),
          padding: EdgeInsets.zero,
        ),
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

  // Helper: try parsing various delivery fields to a LatLng
  LatLng? _parseLatLngFromDeliveryData(Map<String, dynamic> data, List<String> possibleKeys) {
    for (final key in possibleKeys) {
      if (!data.containsKey(key)) continue;
      final value = data[key];
      final latlng = _latLngFromDynamic(value);
      if (latlng != null) return latlng;
    }
    return null;
  }

  LatLng? _latLngFromDynamic(dynamic value) {
    try {
      if (value == null) return null;
      if (value is LatLng) return value;
      if (value is Map) {
        // Accept many key shapes
        final lat = value['lat'] ?? value['latitude'] ?? value['latitude'] ?? value['latCoord'] ?? value['lat1'];
        final lng = value['lng'] ?? value['lon'] ?? value['longitude'] ?? value['lngCoord'] ?? value['lon1'];
        if (lat != null && lng != null) {
          return LatLng((lat as num).toDouble(), (lng as num).toDouble());
        }
        // Some systems store as {'latitude':{'value':...}, ...} - ignore for now
      }
      if (value is List && value.length >= 2) {
        final lat = value[0];
        final lng = value[1];
        if (lat != null && lng != null) {
          return LatLng((lat as num).toDouble(), (lng as num).toDouble());
        }
      }
      if (value is String) {
        // Accept "lat,lng"
        final parts = value.split(',');
        if (parts.length >= 2) {
          final lat = double.tryParse(parts[0].trim());
          final lng = double.tryParse(parts[1].trim());
          if (lat != null && lng != null) return LatLng(lat, lng);
        }
      }
      if (value is num) {
        // Single numeric value - cannot parse
        return null;
      }
    } catch (e) {
      print('Error parsing latlng: $e');
    }
    return null;
  }
}

class DeliveryRouteData {
  final LatLng origin;
  final LatLng destination;
  final Map<String, dynamic> delivery;
  final List<LatLng> routePoints;
  final String distance;
  final String duration;
  final String trafficStatus;
  final bool isInternational;
  final bool routeFound;
  final String routeAccuracy;

  const DeliveryRouteData({
    required this.origin,
    required this.destination,
    required this.delivery,
    required this.routePoints,
    required this.distance,
    required this.duration,
    required this.trafficStatus,
    required this.isInternational,
    required this.routeFound,
    this.routeAccuracy = 'low',
  });
}

class LiveMapWidget extends StatelessWidget {
  final MapController mapController;
  final List<DeliveryRouteData> deliveryRoutes;
  final List<Map<String, dynamic>> availableContainers;
  final List<Map<String, dynamic>> acceptedDeliveries;
  final Map<String, LatLng> courierRoutePositions;
  final Function(Map<String, dynamic>) onDestinationTap;
  final bool isLoadingRoutes;

  const LiveMapWidget({
    super.key,
    required this.mapController,
    required this.deliveryRoutes,
    required this.availableContainers,
    required this.acceptedDeliveries,
    required this.courierRoutePositions,
    required this.onDestinationTap,
    required this.isLoadingRoutes,
  });

  // Helper method to check if location is valid and not the default Cebu location
  bool _isValidNonDefaultLocation(LatLng coords) {
    final cebu = const LatLng(10.3157, 123.8854);
    final distance = Distance();
    // Only show locations that are at least 1km away from Cebu default
    return distance(coords, cebu) > 1000; // 1km in meters
  }

  // Build a container icon marker for destination points
  Widget _buildContainerIconMarker(Color backgroundColor, Color iconColor) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: backgroundColor,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Icon(
        Icons.inventory_2, // Container icon
        color: Colors.white,
        size: 24,
      ),
    );
  }

  // Build a simple styled container/truck marker that visually leans toward the provided image
  Widget _buildContainerMarker(BuildContext context, Color backgroundColor, Color cabColor) {
    return SizedBox(
      width: 44,
      height: 30,
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          // container box (white)
          Positioned(
            left: 8,
            right: 0,
            top: 4,
            bottom: 4,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.grey.shade300, width: 1),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 4, offset: const Offset(0,1)),
                ],
              ),
              child: Center(
                child: Icon(
                  Icons.inventory_2,
                  size: 14,
                  color: Colors.amber.shade700, // yellow boxes inside
                ),
              ),
            ),
          ),
          // truck cab (colored square) to emulate the red cab in the image
          Positioned(
            left: 0,
            top: 6,
            bottom: 6,
            child: Container(
              width: 16,
              decoration: BoxDecoration(
                color: cabColor,
                borderRadius: BorderRadius.circular(3),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.18), blurRadius: 3, offset: const Offset(0,1)),
                ],
              ),
              child: const Icon(Icons.directions_car, size: 12, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      mapController: mapController,
      options: MapOptions(
        initialCenter: const LatLng(10.3157, 123.8854), // Cebu
        initialZoom: 10.0,
        minZoom: 3.0,
        maxZoom: 18.0,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
      ),
      children: [
        // Using reliable OSM tiles
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.de/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.cargo_delivery_app', // Replace with your actual package name
        ),
        
        // Proper attribution
        RichAttributionWidget(
          attributions: [
            TextSourceAttribution(
              'OpenStreetMap contributors',
              onTap: () => launchUrl(Uri.parse('https://openstreetmap.org/copyright')),
            ),
          ],
        ),
        
        // Draw routes for active deliveries with RED color (as requested)
        for (final route in deliveryRoutes)
          if (route.routePoints.isNotEmpty)
            PolylineLayer(
              polylines: [
                Polyline(
                  points: route.routePoints,
                  color: const Color(0xFFEF4444), // RED for all routes
                  strokeWidth: route.routeAccuracy == 'high' ? 4.0 : 3.0,
                  borderColor: route.routeAccuracy == 'high' ? Colors.transparent : Colors.grey,
                  borderStrokeWidth: 1.0,
                  strokeCap: StrokeCap.round,
                  strokeJoin: StrokeJoin.round,
                ),
              ],
            ),
        
        // Pickup points for active deliveries (green location icon)
        for (final route in deliveryRoutes)
          MarkerLayer(
            markers: [
              Marker(
                point: route.origin,
                width: 40,
                height: 40,
                child: GestureDetector(
                  onTap: () => onDestinationTap(route.delivery),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.location_on,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
              ),
            ],
          ),
        
        // Destination points for active deliveries
        // CHANGED: Use container icon instead of location icon for destination points
        for (final route in deliveryRoutes)
          MarkerLayer(
            markers: [
              Marker(
                point: route.destination,
                width: 40,
                height: 40,
                child: GestureDetector(
                  onTap: () => onDestinationTap(route.delivery),
                  child: _buildContainerIconMarker(
                    const Color(0xFFEF4444), // RED background for destination
                    Colors.white,
                  ),
                ),
              ),
            ],
          ),
        
        // All containers (available, in-progress, and cancelled) placed at DESTINATION coordinates
        // CHANGED: use a truck/container-styled marker (to visually match the provided image)
        for (final container in availableContainers)
  if (container['destination_coords'] != null &&
      _isValidNonDefaultLocation(container['destination_coords']))
    MarkerLayer(
      markers: [
        // compute status/colors here, then pass a child widget
        Marker(
          point: container['destination_coords'],
          width: 44,
          height: 30,
          // builder is not defined in this flutter_map version; use `child`
          child: Builder(builder: (context) {
            final isCancelled = container['status'] == 'cancelled';
            final cabColor = isCancelled ? const Color(0xFF6B7280) : const Color(0xFFE53935); // red cab
            return GestureDetector(
              onTap: () => onDestinationTap(container),
              child: _buildContainerMarker(context, Colors.white, cabColor),
            );
          }),
        ),
      ],
    ),
        
        // Courier positions on route (1km from pickup or live coords from ContainerDelivery)
        for (final entry in courierRoutePositions.entries)
          if (_isValidNonDefaultLocation(entry.value)) // Only show valid courier positions
            MarkerLayer(
              markers: [
                Marker(
                  point: entry.value,
                  width: 40,
                  height: 40,
                  child: GestureDetector(
                    onTap: () {
                      final container = acceptedDeliveries.firstWhere(
                        (d) => d['containerId'] == entry.key,
                        orElse: () => {},
                      );
                      if (container.isNotEmpty) {
                        onDestinationTap(container);
                      }
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.local_shipping, // courier uses truck icon too but as a route/courier indicator
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ],
            ),
      ],
    );
  }
}

class LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  final IconData icon;
  final bool isCancelled;

  const LegendItem({
    super.key,
    required this.color,
    required this.label,
    required this.icon,
    this.isCancelled = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: isCancelled ? const Color(0xFF6B7280) : color,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 10,
              color: Colors.white,
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
      ),
    );
  }
}