import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'homepage.dart';
import 'schedulepage.dart';
import 'settings_page.dart';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';

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
  
  LatLng _courierLocation = const LatLng(10.3157, 123.8854); // Courier's current location
  
  List<Map<String, dynamic>> _availableCargos = [];
  List<Map<String, dynamic>> _acceptedDeliveries = [];
  List<LatLng> _destinationMarkers = [];
  Map<String, dynamic>? _selectedCargoDetails;
  
  bool _showCargoDetails = false;
  bool _isLoadingCargo = false;
  
  List<List<LatLng>> _deliveryRoutes = []; // Multiple routes for multiple deliveries
  late StreamSubscription<QuerySnapshot>? _cargoSubscription;
  late StreamSubscription<QuerySnapshot>? _deliverySubscription;
  late StreamSubscription<DocumentSnapshot>? _courierLocationSubscription;

  // Route styling and animation
  bool _showRoute = true;
  Timer? _routeAnimationTimer;

  @override
  void initState() {
    super.initState();
    _loadCourierLocation();
    _loadAvailableAndAcceptedCargos();
    _setupRealtimeListeners();
  }

  Future<void> _loadCourierLocation() async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        final courierDoc = await _firestore.collection('Couriers').doc(user.uid).get();
        if (courierDoc.exists) {
          final data = courierDoc.data();
          if (data?['currentLocation'] != null) {
            final location = data!['currentLocation'] as Map<String, dynamic>;
            setState(() {
              _courierLocation = LatLng(
                location['latitude']?.toDouble() ?? 10.3157,
                location['longitude']?.toDouble() ?? 123.8854,
              );
            });
          }
        }
      }
    } catch (e) {
      print('[v0] Error loading courier location: $e');
    }
  }

  Future<void> _loadAvailableAndAcceptedCargos() async {
    setState(() {
      _isLoadingCargo = true;
    });

    try {
      final user = _auth.currentUser;
      if (user == null) return;

      // Load available cargos (not yet accepted by any courier)
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
      List<LatLng> destinationMarkers = [];
      
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
          
          LatLng destCoords = _getCoordinatesForLocation(cargo['destination']);
          destinationMarkers.add(destCoords);
        }
      }

      QuerySnapshot acceptedSnapshot = await _firestore
          .collection('CargoDelivery')
          .where('courier_id', isEqualTo: user.uid)
          .where('status', whereIn: ['in-progress', 'in_transit', 'assigned'])
          .get();

      List<Map<String, dynamic>> acceptedDeliveries = [];
      List<List<LatLng>> routes = [];
      
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
          
          LatLng destCoords = _getCoordinatesForLocation(delivery['destination']);
          List<LatLng> route = _generateRoute(_courierLocation, destCoords);
          routes.add(route);
        }
      }

      setState(() {
        _availableCargos = availableCargos;
        _acceptedDeliveries = acceptedDeliveries;
        _destinationMarkers = destinationMarkers;
        _deliveryRoutes = routes;
        _isLoadingCargo = false;
      });
    } catch (e) {
      print('[v0] Error loading cargos: $e');
      setState(() {
        _isLoadingCargo = false;
      });
    }
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

      _courierLocationSubscription = _firestore
          .collection('Couriers')
          .doc(user.uid)
          .snapshots()
          .listen((snapshot) {
        if (snapshot.exists) {
          final data = snapshot.data();
          if (data?['currentLocation'] != null) {
            final location = data!['currentLocation'] as Map<String, dynamic>;
            setState(() {
              _courierLocation = LatLng(
                location['latitude']?.toDouble() ?? _courierLocation.latitude,
                location['longitude']?.toDouble() ?? _courierLocation.longitude,
              );
            });
            _regenerateRoutes();
          }
        }
      });
    }
  }

  void _regenerateRoutes() {
    List<List<LatLng>> routes = [];
    for (var delivery in _acceptedDeliveries) {
      LatLng destCoords = _getCoordinatesForLocation(delivery['destination']);
      List<LatLng> route = _generateRoute(_courierLocation, destCoords);
      routes.add(route);
    }
    setState(() {
      _deliveryRoutes = routes;
    });
  }

  LatLng _getCoordinatesForLocation(String location) {
    final locationMap = {
      'Manila': LatLng(14.5995, 120.9842),
      'Cebu': LatLng(10.3157, 123.8854),
      'Davao': LatLng(7.1907, 125.4553),
      'Batangas': LatLng(13.7565, 121.0583),
      'Subic': LatLng(14.7942, 120.2799),
      'Port Terminal': LatLng(14.5832, 120.9695),
      'Delivery Point': LatLng(14.6000, 121.0000),
    };
    
    for (var key in locationMap.keys) {
      if (location.toLowerCase().contains(key.toLowerCase())) {
        return locationMap[key]!;
      }
    }
    
    return const LatLng(14.5995, 120.9842);
  }

  List<LatLng> _generateRoute(LatLng start, LatLng end) {
    List<LatLng> route = [start];
    
    final double latStep = (end.latitude - start.latitude) / 4;
    final double lngStep = (end.longitude - start.longitude) / 4;
    
    for (int i = 1; i < 4; i++) {
      double lat = start.latitude + (latStep * i) + (i % 2 == 0 ? 0.01 : -0.01);
      double lng = start.longitude + (lngStep * i) + (i % 2 == 0 ? 0.01 : -0.01);
      route.add(LatLng(lat, lng));
    }
    
    route.add(end);
    return route;
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

  Future<void> _markDeliveryComplete(String deliveryId, String cargoId) async {
    try {
      await _firestore.collection('CargoDelivery').doc(deliveryId).update({
        'status': 'delivered',
        'confirmed_at': Timestamp.now(),
      });

      await _firestore.collection('Cargo').doc(cargoId).update({
        'status': 'delivered',
        'updated_at': Timestamp.now(),
      });

      final deliveredCargo = _acceptedDeliveries.firstWhere(
        (d) => d['delivery_id'] == deliveryId,
        orElse: () => {},
      );

      if (deliveredCargo.isNotEmpty) {
        LatLng newCourierLocation = _getCoordinatesForLocation(deliveredCargo['origin']);
        setState(() {
          _courierLocation = newCourierLocation;
        });

        final user = _auth.currentUser;
        if (user != null) {
          await _firestore.collection('Couriers').doc(user.uid).update({
            'currentLocation': {
              'latitude': newCourierLocation.latitude,
              'longitude': newCourierLocation.longitude,
            },
          });
        }
      }

      await _loadAvailableAndAcceptedCargos();
    } catch (e) {
      print('[v0] Error marking delivery complete: $e');
    }
  }

  @override
  void dispose() {
    _cargoSubscription?.cancel();
    _deliverySubscription?.cancel();
    _courierLocationSubscription?.cancel();
    _routeAnimationTimer?.cancel();
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
                courierLocation: _courierLocation,
                mapController: _mapController,
                deliveryRoutes: _deliveryRoutes,
                showRoute: _showRoute,
                availableCargos: _availableCargos,
                acceptedDeliveries: _acceptedDeliveries,
                destinationMarkers: _destinationMarkers,
                onDestinationTap: _showCargoDetailsForMarker,
                onCourierTap: () {
                  // Show courier info
                },
              ),
              
              Positioned(
                top: MediaQuery.of(context).padding.top + 16,
                left: 16,
                right: 16,
                child: _buildMapHeader(),
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
                      _mapController.move(_courierLocation, 12.0);
                    }),
                    const SizedBox(height: 8),
                    _buildMapControl(
                      _showRoute ? Icons.route : Icons.route_outlined,
                      () {
                        setState(() {
                          _showRoute = !_showRoute;
                        });
                      },
                      tooltip: _showRoute ? 'Hide Routes' : 'Show Routes',
                    ),
                  ],
                ),
              ),

              Positioned(
                bottom: 16,
                left: 16,
                child: _buildRouteLegend(),
              ),
            ],
          ),

          if (_showCargoDetails && _selectedCargoDetails != null)
            Positioned(
              bottom: 20,
              left: 20,
              right: 20,
              child: _buildCargoDetailsModal(),
            ),
        ],
      ),
      bottomNavigationBar: _buildBottomNavigation(context, 2),
    );
  }

  Widget _buildMapHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
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
            "Live Delivery Map",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem('${_availableCargos.length}', 'Available', Icons.inventory_2),
              _buildStatItem('${_acceptedDeliveries.length}', 'Active', Icons.local_shipping),
              _buildStatItem('${_deliveryRoutes.length}', 'Routes', Icons.route),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String value, String label, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 16, color: const Color(0xFF3B82F6)),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
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
            color: const Color(0xFFF59E0B),
            label: 'Your Location',
          ),
          LegendItem(
            color: const Color(0xFF8B5CF6),
            label: 'Available Cargo',
          ),
          LegendItem(
            color: const Color(0xFF3B82F6),
            label: 'Active Delivery',
          ),
          LegendItem(
            color: const Color(0xFF10B981),
            label: 'Delivery Routes',
          ),
        ],
      ),
    );
  }

  Widget _buildCargoDetailsModal() {
    final cargo = _selectedCargoDetails!;
    final isAccepted = _acceptedDeliveries.any((d) => d['cargo_id'] == cargo['cargo_id']);
    
    return Container(
      padding: const EdgeInsets.all(20),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                cargo['containerNo'] ?? 'N/A',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1E293B),
                ),
              ),
              IconButton(
                onPressed: _hideCargoDetailsModal,
                icon: const Icon(Icons.close, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          _buildDetailRow("Description", cargo['description'] ?? 'N/A'),
          _buildDetailRow("Origin", cargo['origin'] ?? 'N/A'),
          _buildDetailRow("Destination", cargo['destination'] ?? 'N/A'),
          _buildDetailRow("Weight", "${cargo['weight'] ?? 0} kg"),
          _buildDetailRow("Value", "\$${cargo['value'] ?? 0}"),
          _buildDetailRow("Status", cargo['status'] ?? 'pending'),
          
          const SizedBox(height: 16),
          
          if (!isAccepted)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  // Accept delivery logic here (currently just hides modal)
                  _hideCargoDetailsModal();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 48),
                ),
                child: const Text("Accept Delivery"),
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  _markDeliveryComplete(cargo['delivery_id'], cargo['cargo_id']);
                  _hideCargoDetailsModal();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3B82F6),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 48),
                ),
                child: const Text("Mark as Delivered"),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              "$label:",
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
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

class LiveMapWidget extends StatelessWidget {
  final LatLng courierLocation;
  final MapController? mapController;
  final List<List<LatLng>> deliveryRoutes;
  final bool showRoute;
  final List<Map<String, dynamic>> availableCargos;
  final List<Map<String, dynamic>> acceptedDeliveries;
  final List<LatLng> destinationMarkers;
  final Function(Map<String, dynamic>) onDestinationTap;
  final VoidCallback? onCourierTap;

  const LiveMapWidget({
    super.key,
    required this.courierLocation,
    this.mapController,
    required this.deliveryRoutes,
    required this.showRoute,
    required this.availableCargos,
    required this.acceptedDeliveries,
    required this.destinationMarkers,
    required this.onDestinationTap,
    this.onCourierTap,
  });

  @override
  Widget build(BuildContext context) {
    final routeColors = [
      const Color(0xFF10B981),
      const Color(0xFF3B82F6),
      const Color(0xFFF59E0B),
      const Color(0xFF8B5CF6),
      const Color(0xFFEF4444),
    ];

    return SizedBox(
      width: double.infinity,
      height: double.infinity,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(0),
        child: FlutterMap(
          mapController: mapController,
          options: MapOptions(
            initialCenter: courierLocation,
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
            
            if (showRoute)
              ...deliveryRoutes.asMap().entries.map((entry) {
                int index = entry.key;
                List<LatLng> route = entry.value;
                Color routeColor = routeColors[index % routeColors.length];
                
                return PolylineLayer(
                  polylines: [
                    Polyline(
                      points: route,
                      color: routeColor.withOpacity(0.7),
                      strokeWidth: 4.0,
                      borderColor: Colors.white.withOpacity(0.5),
                      borderStrokeWidth: 1.0,
                    ),
                  ],
                );
              }).toList(),
            
            MarkerLayer(
              markers: [
                Marker(
                  point: courierLocation,
                  width: 80,
                  height: 80,
                  child: MapMarker(
                    label: "You",
                    color: const Color(0xFFF59E0B),
                    isCourier: true,
                    onTap: onCourierTap,
                  ),
                ),
                
                ...availableCargos.asMap().entries.map((entry) {
                  int index = entry.key;
                  var cargo = entry.value;
                  if (index < destinationMarkers.length) {
                    return Marker(
                      point: destinationMarkers[index],
                      width: 80,
                      height: 80,
                      child: MapMarker(
                        label: cargo['containerNo'] ?? 'Cargo',
                        color: const Color(0xFF8B5CF6),
                        icon: Icons.location_on,
                        onTap: () => onDestinationTap(cargo),
                      ),
                    );
                  }
                  return null;
                }).whereType<Marker>().toList(),
                
                ...acceptedDeliveries.map((delivery) {
                  LatLng destCoords = _getCoordinatesForLocation(delivery['destination']);
                  return Marker(
                    point: destCoords,
                    width: 80,
                    height: 80,
                    child: MapMarker(
                      label: delivery['containerNo'] ?? 'Delivery',
                      color: const Color(0xFF3B82F6),
                      icon: Icons.flag,
                      onTap: () => onDestinationTap(delivery),
                    ),
                  );
                }).toList(),
              ],
            ),
          ],
        ),
      ),
    );
  }

  LatLng _getCoordinatesForLocation(String location) {
    final locationMap = {
      'Manila': LatLng(14.5995, 120.9842),
      'Cebu': LatLng(10.3157, 123.8854),
      'Davao': LatLng(7.1907, 125.4553),
      'Batangas': LatLng(13.7565, 121.0583),
      'Subic': LatLng(14.7942, 120.2799),
      'Port Terminal': LatLng(14.5832, 120.9695),
      'Delivery Point': LatLng(14.6000, 121.0000),
    };
    
    for (var key in locationMap.keys) {
      if (location.toLowerCase().contains(key.toLowerCase())) {
        return locationMap[key]!;
      }
    }
    
    return const LatLng(14.5995, 120.9842);
  }
}

class MapMarker extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  final bool isCourier;
  final VoidCallback? onTap;

  const MapMarker({
    super.key,
    required this.label,
    required this.color,
    this.icon = Icons.location_on,
    this.isCourier = false,
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
          Container(
            padding: const EdgeInsets.all(8),
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
            child: Icon(
              isCourier ? Icons.person_pin_circle : icon,
              color: Colors.white,
              size: 20,
            ),
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
