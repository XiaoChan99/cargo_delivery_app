import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'homepage.dart';
import 'live_location_page.dart';
import 'container_details_page.dart';
import 'status_update_page.dart';
import 'livemap_page.dart';
import 'settings_page.dart';
import 'dart:convert';
import 'dart:typed_data';

class SchedulePage extends StatefulWidget {
  const SchedulePage({super.key});

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> with AutoRefreshMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  Map<String, dynamic>? _userData;
  Uint8List? _cachedAvatarImage;
  String _licenseNumber = '';
  bool _isLoading = true;

  List<Map<String, dynamic>> _availableCargos = [];
  List<Map<String, dynamic>> _inProgressDeliveries = [];

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadCargoData();
    _setupRealTimeListeners();
  }

  Future<void> _loadUserData() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      DocumentSnapshot userDoc = await _firestore.collection('Couriers').doc(user.uid).get();
      if (userDoc.exists) {
        var userData = userDoc.data() as Map<String, dynamic>;
        String role = userData['role']?.toString() ?? 'courier';
        await _processUserData(userData, role);
      }
    } catch (e) {
      print('Error loading user data: $e');
    }
  }

  void _setupRealTimeListeners() {
    setupCargoListener(_loadAvailableCargos);
    if (_auth.currentUser != null) {
      setupDeliveryListener(_auth.currentUser!.uid, _loadInProgressDeliveries);
    }
  }

  Future<void> _loadCargoData() async {
    try {
      await Future.wait([
        _loadAvailableCargos(),
        _loadInProgressDeliveries(),
      ]);
    } catch (e) {
      print('Error loading cargo data: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadAvailableCargos() async {
    try {
      QuerySnapshot cargoSnapshot = await _firestore
          .collection('Cargo')
          .orderBy('created_at', descending: true)
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
        var cargoData = doc.data() as Map<String, dynamic>;
        final status = cargoData['status']?.toString().toLowerCase() ?? 'pending';

        // Only include cargos that are not assigned to any delivery and not delayed
        if (!assignedCargoIds.contains(doc.id) && status != 'delayed') {
          Map<String, dynamic> combinedData = {
            'cargo_id': doc.id,
            'containerNo': 'CONT-${cargoData['item_number']?.toString() ?? 'N/A'}',
            'status': cargoData['status']?.toString() ?? 'pending',
            'pickupLocation': cargoData['origin']?.toString() ?? 'Port Terminal',
            'destination': cargoData['destination']?.toString() ?? 'Delivery Point',
            'created_at': cargoData['created_at'],
            'description': cargoData['description']?.toString() ?? 'N/A',
            'weight': cargoData['weight'] ?? 0.0,
            'value': cargoData['value'] ?? 0.0,
            'hs_code': cargoData['hs_code']?.toString() ?? 'N/A',
            'quantity': cargoData['quantity'] ?? 0,
            'item_number': cargoData['item_number'] ?? 0,
            'additional_info': cargoData['additional_info']?.toString() ?? '',
            'submanifest_id': cargoData['submanifest_id']?.toString() ?? '',
          };
          availableCargos.add(combinedData);
        }
      }

      setState(() {
        _availableCargos = availableCargos;
      });
    } catch (e) {
      print('Error loading available cargos: $e');
    }
  }

  Future<void> _loadInProgressDeliveries() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      QuerySnapshot deliverySnapshot = await _firestore
          .collection('CargoDelivery')
          .where('courier_id', isEqualTo: user.uid)
          .get();

      List<Map<String, dynamic>> inProgressDeliveries = [];
      
      for (var doc in deliverySnapshot.docs) {
        var deliveryData = doc.data() as Map<String, dynamic>;
        String status = deliveryData['status']?.toString().toLowerCase() ?? '';
        
        // Only include in-progress, in_transit, assigned, or delayed statuses
        if (status == 'in-progress' || status == 'in_transit' || status == 'assigned' || status == 'delayed') {
          try {
            DocumentSnapshot cargoDoc = await _firestore
                .collection('Cargo')
                .doc(deliveryData['cargo_id'].toString())
                .get();

            if (cargoDoc.exists) {
              var cargoData = cargoDoc.data() as Map<String, dynamic>;
              
              Map<String, dynamic> combinedData = {
                'delivery_id': doc.id,
                'cargo_id': deliveryData['cargo_id'],
                'containerNo': 'CONT-${cargoData['item_number'] ?? 'N/A'}',
                'status': deliveryData['status'] ?? 'in-progress',
                'pickupLocation': cargoData['origin'] ?? 'Port Terminal',
                'destination': cargoData['destination'] ?? 'Delivery Point',
                'confirmed_at': deliveryData['confirmed_at'],
                'courier_id': deliveryData['courier_id'],
                'description': cargoData['description'] ?? 'N/A',
                'weight': cargoData['weight'] ?? 0.0,
                'value': cargoData['value'] ?? 0.0,
                'hs_code': cargoData['hs_code'] ?? 'N/A',
                'quantity': cargoData['quantity'] ?? 0,
                'item_number': cargoData['item_number'] ?? 0,
                'proof_image': deliveryData['proof_image'],
                'confirmed_by': deliveryData['confirmed_by'],
                'remarks': deliveryData['remarks'],
              };
              inProgressDeliveries.add(combinedData);
            }
          } catch (e) {
            print('Error loading cargo details for delivery: $e');
          }
        }
      }

      setState(() {
        _inProgressDeliveries = inProgressDeliveries;
      });
    } catch (e) {
      print('Error loading in-progress deliveries: $e');
    }
  }
  Future<void> _processUserData(Map<String, dynamic> data, String role) async {
    Uint8List? decodedImage;
    
    if (data['profile_image_base64'] != null && data['profile_image_base64'].toString().isNotEmpty) {
      try {
        decodedImage = await _decodeImage(data['profile_image_base64']);
      } catch (e) {
        print('Failed to decode profile image: $e');
      }
    }

    setState(() {
      _userData = data;
      _cachedAvatarImage = decodedImage;
      _licenseNumber = data['license_number'] ?? 'N/A';
    });
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'scheduled':
        return Icons.schedule_rounded;
      case 'in progress':
      case 'in-progress':
      case 'in_transit':
        return Icons.local_shipping_rounded;
      case 'delayed':
        return Icons.warning_rounded;
      case 'delivered':
      case 'confirmed':
        return Icons.check_circle_rounded;
      case 'pending':
        return Icons.pending_rounded;
      case 'assigned':
        return Icons.assignment_turned_in_rounded;
      case 'cancelled':
        return Icons.cancel_rounded;
      default:
        return Icons.info_rounded;
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'scheduled':
        return const Color(0xFF10B981);
      case 'in progress':
      case 'in-progress':
      case 'in_transit':
        return const Color(0xFFF59E0B);
      case 'delayed':
        return const Color(0xFFEF4444);
      case 'delivered':
      case 'confirmed':
        return const Color(0xFF10B981);
      case 'pending':
        return const Color(0xFF64748B);
      case 'assigned':
        return const Color(0xFF3B82F6);
      case 'cancelled':
        return const Color(0xFFEF4444);
      default:
        return const Color(0xFF64748B);
    }
  }

  String _formatTime(Timestamp timestamp) {
    final date = timestamp.toDate();
    final hour = date.hour % 12;
    final period = date.hour >= 12 ? 'PM' : 'AM';
    return '${hour == 0 ? 12 : hour}:${date.minute.toString().padLeft(2, '0')} $period';
  }

  String _formatDate(Timestamp timestamp) {
    final date = timestamp.toDate();
    return '${date.day}/${date.month}/${date.year} ${_formatTime(timestamp)}';
  }

  Future<Uint8List> _decodeImage(String imageData) async {
    try {
      if (imageData.startsWith('data:image')) {
        final commaIndex = imageData.indexOf(',');
        if (commaIndex != -1) {
          final base64Data = imageData.substring(commaIndex + 1);
          return base64Decode(base64Data);
        }
      }
      
      return base64Decode(imageData);
    } catch (e) {
      print('Error decoding image: $e');
      rethrow;
    }
  }

  void _handleCargoTap(Map<String, dynamic> cargoData) {
    final status = cargoData['status']?.toString().toLowerCase() ?? 'pending';
    
    if (status == 'in-progress' || status == 'in_transit') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => LiveLocationPage(
            cargoData: cargoData,
          ),
        ),
      );
    } else if (status == 'delayed') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => StatusUpdatePage(
            cargoData: cargoData,
          ),
        ),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ContainerDetailsPage(
            containerData: cargoData,
            isAvailable: true,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final firstName = _userData?['first_name'] ?? 'First Name';
    final lastName = _userData?['last_name'] ?? 'Last Name';
    final fullName = _userData != null ? '$firstName $lastName' : 'Loading User...';
    final hasAvatarImage = _cachedAvatarImage != null && _cachedAvatarImage!.isNotEmpty;
    final licenseNumber = _licenseNumber.isNotEmpty ? _licenseNumber : 'Loading license...';

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                children: [
                  // Header
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 30, 16, 20),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF1E40AF), Color(0xFF3B82F6)],
                      ),
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(16),
                        bottomRight: Radius.circular(16),
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                hasAvatarImage
                                    ? CircleAvatar(
                                        radius: 20,
                                        backgroundImage: MemoryImage(_cachedAvatarImage!),
                                        backgroundColor: Colors.transparent,
                                      )
                                    : CircleAvatar(
                                        radius: 20,
                                        backgroundColor: Colors.white.withOpacity(0.2),
                                        child: const Icon(Icons.person, color: Colors.white, size: 20),
                                      ),
                                const SizedBox(width: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      fullName,
                                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
                                    ),
                                    Text(
                                      "License No: $licenseNumber",
                                      style: const TextStyle(fontSize: 12, color: Colors.white70),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          "Today's Schedule",
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  if (_availableCargos.isNotEmpty)
                    _buildCargoSection(
                      "Available Cargos",
                      _availableCargos,
                      true,
                    ),

                  const SizedBox(height: 16),

                  if (_inProgressDeliveries.isNotEmpty)
                    _buildCargoSection(
                      "Your Active Deliveries",
                      _inProgressDeliveries,
                      false,
                    ),

                  if (_availableCargos.isEmpty && _inProgressDeliveries.isEmpty)
                    _buildNoCargo(),

                  const SizedBox(height: 100),
                ],
              ),
            ),
      bottomNavigationBar: _buildBottomNavigation(context, 1),
    );
  }

  Widget _buildCargoSection(String title, List<Map<String, dynamic>> cargos, bool isAvailable) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Colors.white, Color(0xFFFAFBFF)]),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 20, offset: const Offset(0, 4)),
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
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF1E293B)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF3B82F6).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  cargos.length.toString(),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF3B82F6),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            isAvailable ? "Cargos available for delivery" : "Deliveries in progress",
            style: const TextStyle(fontSize: 14, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 20),
          ...cargos.map((cargo) {
            return Column(
              children: [
                _buildCargoCard(cargo, isAvailable),
                const SizedBox(height: 16),
              ],
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildCargoCard(Map<String, dynamic> cargo, bool isAvailable) {
    final containerNo = cargo['containerNo'] ?? 'CONT-${cargo['item_number'] ?? 'N/A'}';
    final pickup = cargo['pickupLocation'] ?? cargo['origin'] ?? 'Port Terminal';
    final destination = cargo['destination'] ?? 'Delivery Point';
    final description = cargo['description'] ?? 'No description';
    final status = cargo['status']?.toString().toLowerCase() ?? 'pending';
    final time = cargo['created_at'] != null 
        ? _formatDate(cargo['created_at'] as Timestamp)
        : cargo['confirmed_at'] != null
            ? _formatDate(cargo['confirmed_at'] as Timestamp)
            : 'No time';

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
              Text(
                time,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _getStatusColor(status).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      _getStatusIcon(status),
                      size: 14,
                      color: _getStatusColor(status),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      status.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _getStatusColor(status),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            containerNo,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
          Text(
            'From: $pickup',
            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
          Text(
            'To: $destination',
            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF3B82F6),
                    side: const BorderSide(color: Color(0xFF3B82F6)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  onPressed: () => _handleCargoTap(cargo),
                  child: const Text("View Details", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNoCargo() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Colors.white, Color(0xFFFAFBFF)]),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 20, offset: const Offset(0, 4)),
        ],
      ),
      child: const Column(
        children: [
          Icon(Icons.local_shipping, size: 64, color: Color(0xFF64748B)),
          SizedBox(height: 16),
          Text(
            'No cargo items found',
            style: TextStyle(fontSize: 16, color: Color(0xFF64748B)),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 8),
          Text(
            'Cargo items will appear here when added to the system',
            style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
            textAlign: TextAlign.center,
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