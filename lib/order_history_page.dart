import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class OrderHistoryPage extends StatefulWidget {
  const OrderHistoryPage({super.key});

  @override
  State<OrderHistoryPage> createState() => _OrderHistoryPageState();
}

class _OrderHistoryPageState extends State<OrderHistoryPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  User? _currentUser;
  
  List<Map<String, dynamic>> _completedDeliveries = [];
  List<Map<String, dynamic>> _cancelledDeliveries = [];
  List<Map<String, dynamic>> _delayedDeliveries = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _currentUser = _auth.currentUser;
    if (_currentUser != null) {
      _loadOrderHistory();
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage = "User not authenticated";
      });
    }
  }

  Future<void> _loadOrderHistory() async {
    try {
      await Future.wait([
        _loadCompletedDeliveries(),
        _loadCancelledDeliveries(),
        _loadDelayedDeliveries(),
      ]);
    } catch (e) {
      setState(() {
        _errorMessage = "Error loading order history: ${e.toString()}";
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadCompletedDeliveries() async {
    try {
      QuerySnapshot deliverySnapshot = await _firestore
          .collection('CargoDelivery')
          .where('courier_id', isEqualTo: _currentUser!.uid)
          .where('status', whereIn: ['delivered', 'completed'])
          .orderBy('confirmed_at', descending: true)
          .get();

      List<Map<String, dynamic>> completedDeliveries = [];
      
      for (var doc in deliverySnapshot.docs) {
        var deliveryData = doc.data() as Map<String, dynamic>;
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
              'status': deliveryData['status'] ?? 'delivered',
              'pickupLocation': cargoData['origin'] ?? 'Port Terminal',
              'destination': cargoData['destination'] ?? 'Delivery Point',
              'confirmed_at': deliveryData['confirmed_at'],
              'completed_at': deliveryData['completed_at'] ?? deliveryData['confirmed_at'],
              'courier_id': deliveryData['courier_id'],
              'description': cargoData['description'] ?? 'N/A',
              'weight': cargoData['weight'] ?? 0.0,
              'value': cargoData['value'] ?? 0.0,
              'hs_code': cargoData['hs_code'] ?? 'N/A',
              'quantity': cargoData['quantity'] ?? 0,
              'item_number': cargoData['item_number'] ?? 0,
              'proof_image': deliveryData['proof_image'],
              'confirmed_by': deliveryData['confirmed_by'],
              'remarks': deliveryData['remarks'] ?? '',
            };
            completedDeliveries.add(combinedData);
          }
        } catch (e) {
          print('Error loading cargo details for delivery: $e');
        }
      }

      setState(() {
        _completedDeliveries = completedDeliveries;
      });
      
      print('Found ${_completedDeliveries.length} completed deliveries');
    } catch (e) {
      print('Error loading completed deliveries: $e');
    }
  }

  Future<void> _loadCancelledDeliveries() async {
    try {
      QuerySnapshot deliverySnapshot = await _firestore
          .collection('CargoDelivery')
          .where('courier_id', isEqualTo: _currentUser!.uid)
          .where('status', whereIn: ['cancelled', 'rejected'])
          .orderBy('confirmed_at', descending: true)
          .get();

      List<Map<String, dynamic>> cancelledDeliveries = [];
      
      for (var doc in deliverySnapshot.docs) {
        var deliveryData = doc.data() as Map<String, dynamic>;
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
              'status': deliveryData['status'] ?? 'cancelled',
              'pickupLocation': cargoData['origin'] ?? 'Port Terminal',
              'destination': cargoData['destination'] ?? 'Delivery Point',
              'confirmed_at': deliveryData['confirmed_at'],
              'cancelled_at': deliveryData['cancelled_at'] ?? deliveryData['confirmed_at'],
              'courier_id': deliveryData['courier_id'],
              'description': cargoData['description'] ?? 'N/A',
              'weight': cargoData['weight'] ?? 0.0,
              'value': cargoData['value'] ?? 0.0,
              'hs_code': cargoData['hs_code'] ?? 'N/A',
              'quantity': cargoData['quantity'] ?? 0,
              'item_number': cargoData['item_number'] ?? 0,
              'cancellation_reason': deliveryData['cancellation_reason'] ?? 'No reason provided',
              'cancelled_by': deliveryData['cancelled_by'] ?? 'Unknown',
            };
            cancelledDeliveries.add(combinedData);
          }
        } catch (e) {
          print('Error loading cargo details for cancelled delivery: $e');
        }
      }

      setState(() {
        _cancelledDeliveries = cancelledDeliveries;
      });
      
      print('Found ${_cancelledDeliveries.length} cancelled deliveries');
    } catch (e) {
      print('Error loading cancelled deliveries: $e');
    }
  }

  Future<void> _loadDelayedDeliveries() async {
    try {
      QuerySnapshot deliverySnapshot = await _firestore
          .collection('CargoDelivery')
          .where('courier_id', isEqualTo: _currentUser!.uid)
          .where('status', whereIn: ['delayed', 'overdue'])
          .orderBy('confirmed_at', descending: true)
          .get();

      List<Map<String, dynamic>> delayedDeliveries = [];
      
      for (var doc in deliverySnapshot.docs) {
        var deliveryData = doc.data() as Map<String, dynamic>;
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
              'status': deliveryData['status'] ?? 'delayed',
              'pickupLocation': cargoData['origin'] ?? 'Port Terminal',
              'destination': cargoData['destination'] ?? 'Delivery Point',
              'confirmed_at': deliveryData['confirmed_at'],
              'estimated_delivery': deliveryData['estimated_delivery'],
              'delay_reason': deliveryData['delay_reason'] ?? 'Unexpected delay',
              'courier_id': deliveryData['courier_id'],
              'description': cargoData['description'] ?? 'N/A',
              'weight': cargoData['weight'] ?? 0.0,
              'value': cargoData['value'] ?? 0.0,
              'hs_code': cargoData['hs_code'] ?? 'N/A',
              'quantity': cargoData['quantity'] ?? 0,
              'item_number': cargoData['item_number'] ?? 0,
            };
            delayedDeliveries.add(combinedData);
          }
        } catch (e) {
          print('Error loading cargo details for delayed delivery: $e');
        }
      }

      setState(() {
        _delayedDeliveries = delayedDeliveries;
      });
      
      print('Found ${_delayedDeliveries.length} delayed deliveries');
    } catch (e) {
      print('Error loading delayed deliveries: $e');
    }
  }

  String _getStatusText(String status) {
    switch (status.toLowerCase()) {
      case 'delivered':
      case 'completed':
        return 'Delivered';
      case 'cancelled':
        return 'Cancelled';
      case 'rejected':
        return 'Rejected';
      case 'delayed':
      case 'overdue':
        return 'Delayed';
      default:
        return status;
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'delivered':
      case 'completed':
        return const Color(0xFF10B981);
      case 'cancelled':
      case 'rejected':
        return const Color(0xFFEF4444);
      case 'delayed':
      case 'overdue':
        return const Color(0xFFF59E0B);
      default:
        return const Color(0xFF64748B);
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'delivered':
      case 'completed':
        return Icons.check_circle;
      case 'cancelled':
      case 'rejected':
        return Icons.cancel;
      case 'delayed':
      case 'overdue':
        return Icons.schedule;
      default:
        return Icons.history;
    }
  }

  String _formatDate(Timestamp timestamp) {
    final date = timestamp.toDate();
    return '${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  String _formatDateOnly(Timestamp timestamp) {
    final date = timestamp.toDate();
    return '${date.day}/${date.month}/${date.year}';
  }

  String _formatDateTime(Timestamp timestamp) {
    final date = timestamp.toDate();
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildDeliveryCard(Map<String, dynamic> delivery, String deliveryType) {
    bool isCompleted = deliveryType == 'completed';
    bool isCancelled = deliveryType == 'cancelled';
    bool isDelayed = deliveryType == 'delayed';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with container number and status
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  delivery['containerNo'] ?? 'N/A',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getStatusColor(delivery['status']).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _getStatusIcon(delivery['status']),
                        size: 14,
                        color: _getStatusColor(delivery['status']),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _getStatusText(delivery['status']),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: _getStatusColor(delivery['status']),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // Route information
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.place, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "From: ${delivery['pickupLocation'] ?? 'Port Terminal'}",
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[700],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        "To: ${delivery['destination'] ?? 'Delivery Point'}",
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[700],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 8),
            
            // Date and Time information
            Row(
              children: [
                Icon(Icons.calendar_today, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 6),
                Text(
                  _formatDateTime(
                    isCompleted 
                      ? delivery['completed_at'] ?? delivery['confirmed_at']
                      : isCancelled
                        ? delivery['cancelled_at'] ?? delivery['confirmed_at']
                        : delivery['estimated_delivery'] ?? delivery['confirmed_at']
                  ),
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[700],
                  ),
                ),
              ],
            ),
            
            // Additional info based on delivery type
            if (isCancelled) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Colors.red[600]),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        "Reason: ${delivery['cancellation_reason'] ?? 'No reason provided'}",
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.red[600],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            
            if (isDelayed) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber, size: 16, color: Colors.orange[600]),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        "Delay: ${delivery['delay_reason'] ?? 'Unexpected delay'}",
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange[600],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            
            // Description
            if (delivery['description'] != null && delivery['description'] != 'N/A') ...[
              const SizedBox(height: 8),
              Text(
                delivery['description'],
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[600],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, List<Map<String, dynamic>> deliveries, String deliveryType) {
    if (deliveries.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        
        ...deliveries.map((delivery) => _buildDeliveryCard(delivery, deliveryType)),
        
        const SizedBox(height: 16),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Delivery History'),
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,
        elevation: 0,
        leading: Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 24),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: Colors.red,
                        size: 64,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _errorMessage!,
                        style: const TextStyle(
                          color: Colors.red,
                          fontSize: 16,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: _loadOrderHistory,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue[700],
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Completed Deliveries Section
                      _buildSection(
                        "Delivered",
                        _completedDeliveries,
                        "completed",
                      ),

                      // Delayed Deliveries Section
                      _buildSection(
                        "Delayed",
                        _delayedDeliveries,
                        "delayed",
                      ),

                      // Cancelled Deliveries Section
                      _buildSection(
                        "Cancelled",
                        _cancelledDeliveries,
                        "cancelled",
                      ),

                      // Empty state if no deliveries
                      if (_completedDeliveries.isEmpty && 
                          _cancelledDeliveries.isEmpty && 
                          _delayedDeliveries.isEmpty) ...[
                        const SizedBox(height: 60),
                        Center(
                          child: Column(
                            children: [
                              Icon(
                                Icons.history,
                                size: 80,
                                color: Colors.grey[300],
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'No delivery history',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Colors.grey,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Your delivery history will appear here',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[400],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
    );
  }
}