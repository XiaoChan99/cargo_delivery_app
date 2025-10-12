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

class LiveMapPage extends StatefulWidget {
  final String? cargoId;
  final String? pickup;
  final String? destination;

  const LiveMapPage({
    super.key,
    this.cargoId,
    this.pickup,
    this.destination,
  });

  @override
  State<LiveMapPage> createState() => _LiveMapPageState();
}

class _LiveMapPageState extends State<LiveMapPage> {
  final MapController _mapController = MapController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  List<Map<String, dynamic>> _availableCargos = [];
  List<Map<String, dynamic>> _acceptedDeliveries = [];
  Map<String, dynamic>? _selectedCargoDetails;
  
  bool _showCargoDetails = false;
  bool _isLoadingCargo = false;
  bool _isLoadingRoutes = false;
  
  List<DeliveryRouteData> _deliveryRoutes = [];
  late StreamSubscription<QuerySnapshot>? _cargoSubscription;
  late StreamSubscription<QuerySnapshot>? _deliverySubscription;

  // Courier position along the route (1km from pickup)
  Map<String, LatLng> _courierRoutePositions = {};

  @override
  void initState() {
    super.initState();
    _loadAvailableAndAcceptedCargos();
    _setupRealtimeListeners();
  }

  Future<void> _loadAvailableAndAcceptedCargos() async {
    setState(() {
      _isLoadingCargo = true;
      _isLoadingRoutes = true;
    });

    try {
      final user = _auth.currentUser;
      if (user == null) return;

      // Load available cargos
      QuerySnapshot cargoSnapshot = await _firestore
          .collection('Cargo')
          .where('status', isEqualTo: 'pending')
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
        if (!assignedCargoIds.contains(doc.id)) {
          var cargoData = doc.data() as Map<String, dynamic>;
          Map<String, dynamic> cargo = {
            'cargo_id': doc.id,
            'containerNo': 'CONT-${cargoData['item_number'] ?? 'N/A'}',
            'destination': cargoData['destination'] ?? 'Unknown',
            'origin': cargoData['origin'] ?? 'Unknown',
            'description': cargoData['description'] ?? 'N/A',
            'weight': cargoData['weight'] ?? 0.0,
            'value': cargoData['value'] ?? 0.0,
            'status': 'pending',
            'item_number': cargoData['item_number'],
            'hs_code': cargoData['hs_code'],
            'quantity': cargoData['quantity'],
            ...cargoData,
          };
          availableCargos.add(cargo);
        }
      }

      // Load accepted deliveries
      QuerySnapshot acceptedSnapshot = await _firestore
          .collection('CargoDelivery')
          .where('courier_id', isEqualTo: user.uid)
          .where('status', whereIn: ['in-progress', 'in_transit', 'assigned'])
          .get();

      List<Map<String, dynamic>> acceptedDeliveries = [];
      List<DeliveryRouteData> routes = [];
      
      for (var doc in acceptedSnapshot.docs) {
        var deliveryData = doc.data() as Map<String, dynamic>;
        DocumentSnapshot cargoDoc = await _firestore
            .collection('Cargo')
            .doc(deliveryData['cargo_id'])
            .get();
        
        if (cargoDoc.exists) {
          var cargoData = cargoDoc.data() as Map<String, dynamic>;
          Map<String, dynamic> delivery = {
            'delivery_id': doc.id,
            'cargo_id': deliveryData['cargo_id'],
            'containerNo': 'CONT-${cargoData['item_number'] ?? 'N/A'}',
            'destination': cargoData['destination'] ?? 'Unknown',
            'origin': cargoData['origin'] ?? 'Unknown',
            'status': deliveryData['status'],
            'description': cargoData['description'] ?? 'N/A',
            'weight': cargoData['weight'] ?? 0.0,
            'value': cargoData['value'] ?? 0.0,
            'item_number': cargoData['item_number'],
            'hs_code': cargoData['hs_code'],
            'quantity': cargoData['quantity'],
            ...cargoData,
          };
          acceptedDeliveries.add(delivery);
          
          // Get coordinates using enhanced geocoding
          final originCoords = await _getCoordinatesForAddress(delivery['origin']);
          final destCoords = await _getCoordinatesForAddress(delivery['destination']);
          
          // Get real route data
          final routeInfo = await OSMService.getRouteWithGeometry(originCoords, destCoords);
          
          routes.add(DeliveryRouteData(
            origin: originCoords,
            destination: destCoords,
            delivery: delivery,
            routePoints: routeInfo['routePoints'] ?? [],
            distance: routeInfo['distance'],
            duration: routeInfo['duration'],
            trafficStatus: routeInfo['trafficStatus'],
            isInternational: routeInfo['isInternational'] ?? false,
            routeFound: routeInfo['routeFound'] ?? false,
          ));

          // Calculate courier position 1km from pickup along the route
          if (routeInfo['routePoints'] != null && routeInfo['routePoints'].isNotEmpty) {
            final courierPosition = _calculateCourierPositionAlongRoute(
              routeInfo['routePoints'] as List<LatLng>,
              1.0 // 1km from pickup
            );
            _courierRoutePositions[delivery['cargo_id']] = courierPosition;
          }
        }
      }

      setState(() {
        _availableCargos = availableCargos;
        _acceptedDeliveries = acceptedDeliveries;
        _deliveryRoutes = routes;
        _isLoadingCargo = false;
        _isLoadingRoutes = false;
      });

      // Auto-zoom to show all routes if there are deliveries
      if (routes.isNotEmpty) {
        _zoomToFitRoutes();
      }
    } catch (e) {
      print('[v0] Error loading cargos: $e');
      setState(() {
        _isLoadingCargo = false;
        _isLoadingRoutes = false;
      });
    }
  }

  // Calculate courier position 1km from pickup along the route
  LatLng _calculateCourierPositionAlongRoute(List<LatLng> routePoints, double distanceKm) {
    if (routePoints.isEmpty) {
      return const LatLng(14.5995, 120.9842); // Default to Manila if no route points
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

    // Fallback to local database
    final locationMap = {
      // Philippines
      'Manila': const LatLng(14.5995, 120.9842),
      'Manila City': const LatLng(14.5995, 120.9842),
      'Cebu': const LatLng(10.3157, 123.8854),
      'Cebu City': const LatLng(10.3157, 123.8854),
      'Davao': const LatLng(7.1907, 125.4553),
      'Davao City': const LatLng(7.1907, 125.4553),
      'Batangas': const LatLng(13.7565, 121.0583),
      'Subic': const LatLng(14.7942, 120.2799),
      'Quezon City': const LatLng(14.6760, 121.0437),
      'Makati': const LatLng(14.5547, 121.0244),
      
      // International Locations
      'Singapore': const LatLng(1.3521, 103.8198),
      'Hong Kong': const LatLng(22.3193, 114.1694),
      'Tokyo': const LatLng(35.6762, 139.6503),
      'Seoul': const LatLng(37.5665, 126.9780),
      'Bangkok': const LatLng(13.7563, 100.5018),
      'Kuala Lumpur': const LatLng(3.1390, 101.6869),
      'Taipei': const LatLng(25.0330, 121.5654),
      'Beijing': const LatLng(39.9042, 116.4074),
      'Shanghai': const LatLng(31.2304, 121.4737),
      'Sydney': const LatLng(-33.8688, 151.2093),
      'Melbourne': const LatLng(-37.8136, 144.9631),
      'Los Angeles': const LatLng(34.0522, -118.2437),
      'New York': const LatLng(40.7128, -74.0060),
      'London': const LatLng(51.5074, -0.1278),
      'Paris': const LatLng(48.8566, 2.3522),
      'Dubai': const LatLng(25.2048, 55.2708),
      'Mumbai': const LatLng(19.0760, 72.8777),
      'Delhi': const LatLng(28.7041, 77.1025),
      'Jakarta': const LatLng(-6.2088, 106.8456),
      'Ho Chi Minh City': const LatLng(10.8231, 106.6297),
      'Hanoi': const LatLng(21.0278, 105.8342),
      'Osaka': const LatLng(34.6937, 135.5023),
      'Busan': const LatLng(35.1796, 129.0756),
      'Incheon': const LatLng(37.4563, 126.7052),
    };
    
    for (var key in locationMap.keys) {
      if (address.toLowerCase().contains(key.toLowerCase())) {
        return locationMap[key]!;
      }
    }
    
    return const LatLng(14.5995, 120.9842); // Default to Manila
  }

  void _setupRealtimeListeners() {
    _cargoSubscription = _firestore
        .collection('Cargo')
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen((snapshot) {
      _loadAvailableAndAcceptedCargos();
    });

    final user = _auth.currentUser;
    if (user != null) {
      _deliverySubscription = _firestore
          .collection('CargoDelivery')
          .where('courier_id', isEqualTo: user.uid)
          .snapshots()
          .listen((snapshot) {
        _loadAvailableAndAcceptedCargos();
      });
    }
  }

  void _showCargoDetailsForMarker(Map<String, dynamic> cargoData) {
    setState(() {
      _selectedCargoDetails = cargoData;
      _showCargoDetails = true;
    });
  }

  void _hideCargoDetailsModal() {
    setState(() {
      _showCargoDetails = false;
      _selectedCargoDetails = null;
    });
  }

  @override
  void dispose() {
    _cargoSubscription?.cancel();
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
                availableCargos: _availableCargos,
                acceptedDeliveries: _acceptedDeliveries,
                courierRoutePositions: _courierRoutePositions,
                onDestinationTap: _showCargoDetailsForMarker,
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
                      if (_deliveryRoutes.isNotEmpty) {
                        _mapController.move(_deliveryRoutes.first.origin, 12.0);
                      }
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

          if (_showCargoDetails && _selectedCargoDetails != null)
            Positioned.fill(
              child: Container(
                color: Colors.black54,
                child: Center(
                  child: _buildCargoDetailsModal(),
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
            color: const Color(0xFF3B82F6),
            label: 'Delivery Point',
            icon: Icons.flag,
          ),
          LegendItem(
            color: const Color(0xFF8B5CF6),
            label: 'Available Cargo',
            icon: Icons.inventory_2,
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
        ],
      ),
    );
  }

  Widget _buildCargoDetailsModal() {
    final cargo = _selectedCargoDetails!;
    final isAccepted = _acceptedDeliveries.any((d) => d['cargo_id'] == cargo['cargo_id']);
    final routeData = _deliveryRoutes.firstWhere(
      (r) => r.delivery['cargo_id'] == cargo['cargo_id'],
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
      ),
    );
    
    final courierOnRoute = _courierRoutePositions.containsKey(cargo['cargo_id']);
    
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
                      Icons.local_shipping,
                      color: routeData.isInternational ? const Color(0xFFEF4444) : const Color(0xFF3B82F6),
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          cargo['containerNo'] ?? 'N/A',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                        if (routeData.isInternational)
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
                        if (courierOnRoute)
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
                  onPressed: _hideCargoDetailsModal,
                  icon: const Icon(Icons.close, size: 24),
                ),
              ],
            ),
            
            const SizedBox(height: 20),
            
            // Cargo Information Section
            _buildInfoSection(
              title: "Cargo Information",
              icon: Icons.inventory_2,
              children: [
                _buildDetailRow(Icons.description, "Description", cargo['description'] ?? 'N/A'),
                _buildDetailRow(Icons.numbers, "Item Number", cargo['item_number']?.toString() ?? 'N/A'),
                _buildDetailRow(Icons.code, "HS Code", cargo['hs_code']?.toString() ?? 'N/A'),
                _buildDetailRow(Icons.format_list_numbered, "Quantity", cargo['quantity']?.toString() ?? 'N/A'),
                _buildDetailRow(Icons.scale, "Weight", "${cargo['weight'] ?? 0} kg"),
                _buildDetailRow(Icons.attach_money, "Value", "\$${cargo['value'] ?? 0}"),
                _buildDetailRow(Icons.info, "Status", cargo['status'] ?? 'pending'),
              ],
            ),
            
            const SizedBox(height: 20),
            
            // Route Information Section
            _buildInfoSection(
              title: "Route Information",
              icon: Icons.route,
              children: [
                _buildDetailRow(Icons.location_on, "Origin", cargo['origin'] ?? 'N/A'),
                _buildDetailRow(Icons.flag, "Destination", cargo['destination'] ?? 'N/A'),
                if (isAccepted && routeData.distance != '0') ...[
                  _buildDetailRow(Icons.space_dashboard, "Distance", "${routeData.distance} km"),
                  _buildDetailRow(Icons.access_time, "Estimated Time", "${routeData.duration} min"),
                  _buildDetailRow(Icons.traffic, "Traffic", routeData.trafficStatus),
                  if (courierOnRoute)
                    _buildDetailRow(Icons.local_shipping, "Courier Status", "1km from pickup - En route"),
                  if (routeData.isInternational)
                    _buildDetailRow(Icons.language, "Route Type", "International Delivery"),
                  if (!routeData.routeFound)
                    _buildDetailRow(Icons.warning, "Note", "Route approximation - actual path may vary"),
                ],
              ],
            ),
            
            const SizedBox(height: 20),
            
            // Close Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _hideCargoDetailsModal,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3B82F6),
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

  Widget _buildDetailRow(IconData icon, String label, String value) {
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
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF1E293B),
                fontWeight: FontWeight.w500,
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
  });
}

class LiveMapWidget extends StatelessWidget {
  final MapController? mapController;
  final List<DeliveryRouteData> deliveryRoutes;
  final List<Map<String, dynamic>> availableCargos;
  final List<Map<String, dynamic>> acceptedDeliveries;
  final Map<String, LatLng> courierRoutePositions;
  final Function(Map<String, dynamic>) onDestinationTap;
  final bool isLoadingRoutes;

  const LiveMapWidget({
    super.key,
    this.mapController,
    required this.deliveryRoutes,
    required this.availableCargos,
    required this.acceptedDeliveries,
    required this.courierRoutePositions,
    required this.onDestinationTap,
    required this.isLoadingRoutes,
  });

  @override
  Widget build(BuildContext context) {
    final routeColors = [
      const Color(0xFF10B981), // Local routes
      const Color(0xFF3B82F6), 
      const Color(0xFFF59E0B),
      const Color(0xFF8B5CF6),
      const Color(0xFFEF4444), // International routes
    ];

    // Use first route origin as initial center, or default to Manila
    final initialCenter = deliveryRoutes.isNotEmpty 
        ? deliveryRoutes.first.origin 
        : const LatLng(14.5995, 120.9842);

    return SizedBox(
      width: double.infinity,
      height: double.infinity,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(0),
        child: FlutterMap(
          mapController: mapController,
          options: MapOptions(
            initialCenter: initialCenter,
            initialZoom: 5.0, // Start more zoomed out for international
            minZoom: 2.0,     // Allow global view
            maxZoom: 18.0,
            interactiveFlags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.cargo_app',
              maxNativeZoom: 19,
            ),
            
            // Draw real routes for accepted deliveries
            if (!isLoadingRoutes)
              ...deliveryRoutes.asMap().entries.map((entry) {
                int index = entry.key;
                DeliveryRouteData routeData = entry.value;
                // Use red for international routes, other colors for local
                Color routeColor = routeData.isInternational 
                    ? const Color(0xFFEF4444) 
                    : routeColors[index % (routeColors.length - 1)];
                
                // Use real route points from OSM
                if (routeData.routePoints.isNotEmpty) {
                  return PolylineLayer(
                    polylines: [
                      Polyline(
                        points: routeData.routePoints,
                        color: routeColor.withOpacity(0.7),
                        strokeWidth: routeData.isInternational ? 3.0 : 4.0,
                        borderColor: Colors.white.withOpacity(0.5),
                        borderStrokeWidth: routeData.isInternational ? 1.0 : 1.0,
                      ),
                    ],
                  );
                } else {
                  // Fallback to straight line if no route points
                  return PolylineLayer(
                    polylines: [
                      Polyline(
                        points: [routeData.origin, routeData.destination],
                        color: routeColor.withOpacity(0.7),
                        strokeWidth: routeData.isInternational ? 3.0 : 4.0,
                        borderColor: Colors.white.withOpacity(0.5),
                        borderStrokeWidth: routeData.isInternational ? 1.0 : 1.0,
                        strokeCap: StrokeCap.round,
                        isDotted: true,
                      ),
                    ],
                  );
                }
              }),
            
            // Pickup markers for accepted deliveries
            if (!isLoadingRoutes)
              MarkerLayer(
                markers: deliveryRoutes.map((routeData) {
                  final isInternational = routeData.isInternational;
                  return Marker(
                    point: routeData.origin,
                    width: 40,
                    height: 40,
                    child: GestureDetector(
                      onTap: () => onDestinationTap(routeData.delivery),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.location_on,
                          color: isInternational ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                          size: 24,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            
            // Destination markers for accepted deliveries
            if (!isLoadingRoutes)
              MarkerLayer(
                markers: deliveryRoutes.map((routeData) {
                  final isInternational = routeData.isInternational;
                  return Marker(
                    point: routeData.destination,
                    width: 40,
                    height: 40,
                    child: GestureDetector(
                      onTap: () => onDestinationTap(routeData.delivery),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.flag,
                          color: isInternational ? const Color(0xFFEF4444) : const Color(0xFF3B82F6),
                          size: 24,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            
            // Courier position markers along routes (1km from pickup)
            if (!isLoadingRoutes)
              MarkerLayer(
                markers: courierRoutePositions.entries.map((entry) {
                  final cargoId = entry.key;
                  final position = entry.value;
                  final routeData = deliveryRoutes.firstWhere(
                    (r) => r.delivery['cargo_id'] == cargoId,
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
                    ),
                  );
                  
                  return Marker(
                    point: position,
                    width: 40,
                    height: 40,
                    child: GestureDetector(
                      onTap: () => onDestinationTap(routeData.delivery),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.local_shipping,
                          color: const Color(0xFFEF4444),
                          size: 24,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            
            // Available cargo markers
            if (!isLoadingRoutes)
              MarkerLayer(
                markers: availableCargos.map((cargo) {
                  return Marker(
                    point: const LatLng(14.5995, 120.9842), // Default to Manila for available cargos
                    width: 40,
                    height: 40,
                    child: GestureDetector(
                      onTap: () => onDestinationTap(cargo),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.inventory_2,
                          color: Color(0xFF8B5CF6),
                          size: 24,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }
}

class LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  final IconData icon;

  const LegendItem({
    super.key,
    required this.color,
    required this.label,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
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