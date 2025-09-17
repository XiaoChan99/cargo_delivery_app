import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'homepage.dart';
import 'schedulepage.dart';
import 'settings_page.dart';

class LiveMapPage extends StatefulWidget {
  const LiveMapPage({super.key});

  @override
  State<LiveMapPage> createState() => _LiveMapPageState();
}

class _LiveMapPageState extends State<LiveMapPage> {
  final MapController _mapController = MapController();
  
  final LatLng _truckLocation = const LatLng(14.5547, 121.0244);
  final String _driverName = "Driver Name";
  final String _driverNo = "DRV-001";
  bool _showCargoDetails = false;
  Map<String, dynamic> _cargoData = {};
  
  final LatLng _manilaPort = const LatLng(14.5832, 120.9695);
  final LatLng _cebuPort = const LatLng(10.3157, 123.8854);
  final LatLng _davaoPort = const LatLng(7.1378, 125.6143);
  final LatLng _subicPort = const LatLng(14.7942, 120.2799);
  final LatLng _batangasPort = const LatLng(13.7565, 121.0583);
  
  List<LatLng> _deliveryRoute = [];
  
  @override
  void initState() {
    super.initState();
    _generateRealisticDeliveryRoute();
    _loadCargoData();
  }
  
  void _loadCargoData() {
    // Static cargo data
    setState(() {
      _cargoData = {
        'containerNo': 'CNTR456789',
        'contents': 'Electronics',
        'weight': '3,200kg',
        'destination': 'Batangas Port',
        'eta': '11:15 AM',
        'status': 'In Transit',
        'temperature': '20°C',
        'hazardous': 'No',
        'sealNumber': 'SEAL123K'
      };
    });
  }
  
  void _generateRealisticDeliveryRoute() {
    _deliveryRoute = [
      _manilaPort,
      const LatLng(14.5200, 121.0000),
      const LatLng(14.4500, 121.0200),
      const LatLng(14.2000, 121.1000),
      const LatLng(14.0000, 121.1500),
      const LatLng(13.9000, 121.1200),
      _batangasPort,
      
      const LatLng(13.7000, 121.0500),
      const LatLng(12.8000, 121.5000),
      const LatLng(12.0000, 122.0000),
      const LatLng(11.3000, 123.0000),
      const LatLng(10.6000, 123.5000),
      _cebuPort,
      
      const LatLng(10.2000, 123.8000),
      const LatLng(9.5000, 124.0000),
      const LatLng(8.8000, 124.5000),
      const LatLng(8.0000, 125.0000),
      const LatLng(7.5000, 125.3000),
      _davaoPort,
    ];
  }

  void _showCargoDetailsModal() {
    setState(() {
      _showCargoDetails = true;
    });
  }

  void _hideCargoDetailsModal() {
    setState(() {
      _showCargoDetails = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Stack(
        children: [
          // Map - takes the full screen
          Stack(
            children: [
              LiveMapWidget(
                truckLocation: _truckLocation,
                mapController: _mapController,
                deliveryRoute: _deliveryRoute,
                ports: [_manilaPort, _cebuPort, _davaoPort, _subicPort, _batangasPort],
                onTruckTap: _showCargoDetailsModal,
              ),
              
              // Map controls
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
                      _mapController.move(_truckLocation, 12.0);
                    }),
                  ],
                ),
              ),
              
              // Legend
              Positioned(
                top: 16,
                left: 16,
                child: Container(
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
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "Legend",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      SizedBox(height: 8),
                      LegendItem(
                        color: Color(0xFF10B981),
                        label: "Available Ports",
                      ),
                      LegendItem(
                        color: Color(0xFF3B82F6),
                        label: "Destination",
                      ),
                      LegendItem(
                        color: Color(0xFFF59E0B),
                        label: "Your Location",
                      ),
                      LegendItem(
                        color: Color(0xFFEF4444),
                        label: "Delivery Route",
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // Cargo Details Modal
          if (_showCargoDetails)
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

  Widget _buildCargoDetailsModal() {
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
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Cargo Details",
                style: TextStyle(
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
          const SizedBox(height: 16),
          _buildCargoDetailRow("Container No.", _cargoData['containerNo'] ?? 'N/A'),
          _buildCargoDetailRow("Contents", _cargoData['contents'] ?? 'N/A'),
          _buildCargoDetailRow("Weight", _cargoData['weight'] ?? 'N/A'),
          _buildCargoDetailRow("Destination", _cargoData['destination'] ?? 'N/A'),
          _buildCargoDetailRow("ETA", _cargoData['eta'] ?? 'N/A'),
          _buildCargoDetailRow("Status", _cargoData['status'] ?? 'N/A'),
          _buildCargoDetailRow("Temperature", _cargoData['temperature'] ?? 'N/A'),
          _buildCargoDetailRow("Hazardous", _cargoData['hazardous'] ?? 'N/A'),
          _buildCargoDetailRow("Seal Number", _cargoData['sealNumber'] ?? 'N/A'),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _hideCargoDetailsModal,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3B82F6),
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 48),
            ),
            child: const Text("Close Details"),
          ),
        ],
      ),
    );
  }

  Widget _buildCargoDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
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

  Widget _buildMapControl(IconData icon, VoidCallback onPressed) {
    return Container(
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

class LiveMapWidget extends StatelessWidget {
  final LatLng? truckLocation;
  final MapController? mapController;
  final List<LatLng> deliveryRoute;
  final List<LatLng> ports;
  final VoidCallback? onTruckTap;

  const LiveMapWidget({
    super.key,
    this.truckLocation,
    this.mapController,
    required this.deliveryRoute,
    required this.ports,
    this.onTruckTap,
  });

  @override
  Widget build(BuildContext context) {
    final LatLng currentTruckLocation = truckLocation ?? const LatLng(14.5547, 121.0244);

    return SizedBox(
      width: double.infinity,
      height: double.infinity,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(0),
        child: FlutterMap(
          mapController: mapController,
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
                    label: "Davao Port",
                    color: Color(0xFF3B82F6),
                  ),
                ),
                Marker(
                  point: ports[3],
                  width: 80,
                  height: 80,
                  child: const MapMarker(
                    label: "Subic Port",
                    color: Color(0xFF10B981),
                  ),
                ),
                Marker(
                  point: ports[4],
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