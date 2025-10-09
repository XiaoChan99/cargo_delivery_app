import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'container_details_page.dart';

class NotificationsPage extends StatefulWidget {
  final String userId;
  
  const NotificationsPage({super.key, required this.userId});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
    _setupNotificationsListener();
    _generateCargoNotifications();
  }

  void _setupNotificationsListener() {
  _firestore
      .collection('notifications')
      .where('userId', isEqualTo: widget.userId)
      .orderBy('timestamp', descending: true)
      .snapshots()
      .listen((snapshot) {
    if (mounted) {
      List<Map<String, dynamic>> notifications = [];
      for (var doc in snapshot.docs) {
        var notification = doc.data();
        notifications.add({
          ...notification,
          'id': doc.id,
        });
      }
      setState(() {
        _notifications = notifications;
      });
      
      // Mark all as read when page is open
      _markAllAsRead();
    }
  });
}

Future<void> _loadNotifications() async {
  try {
    QuerySnapshot notificationsSnapshot = await _firestore
        .collection('notifications')
        .where('userId', isEqualTo: widget.userId)
        .orderBy('timestamp', descending: true)
        .get();

    List<Map<String, dynamic>> notifications = [];
    for (var doc in notificationsSnapshot.docs) {
      var notification = doc.data() as Map<String, dynamic>;
      notifications.add({
        ...notification,
        'id': doc.id,
      });
    }

    setState(() {
      _notifications = notifications;
      _isLoading = false;
    });

    // Mark all as read
    await _markAllAsRead();
  } catch (e) {
    print('Error loading notifications: $e');
    // If still getting index error, try without ordering first
    try {
      QuerySnapshot notificationsSnapshot = await _firestore
          .collection('notifications')
          .where('userId', isEqualTo: widget.userId)
          .get();

      List<Map<String, dynamic>> notifications = [];
      for (var doc in notificationsSnapshot.docs) {
        var notification = doc.data() as Map<String, dynamic>;
        notifications.add({
          ...notification,
          'id': doc.id,
        });
      }

      // Sort manually
      notifications.sort((a, b) {
        Timestamp aTime = a['timestamp'] ?? Timestamp.now();
        Timestamp bTime = b['timestamp'] ?? Timestamp.now();
        return bTime.compareTo(aTime);
      });

      setState(() {
        _notifications = notifications;
        _isLoading = false;
      });

      await _markAllAsRead();
    } catch (e2) {
      print('Error with fallback loading: $e2');
      setState(() {
        _isLoading = false;
      });
    }
  }
}

  Future<void> _markAllAsRead() async {
    for (var notification in _notifications.where((n) => n['read'] == false)) {
      await _firestore.collection('notifications').doc(notification['id']).update({'read': true});
    }
  }


  // Generate notifications for existing cargos
  // Add this method to _NotificationsPageState class
Future<void> _generateCargoNotifications() async {
  try {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    // Get all cargo documents
    QuerySnapshot cargoSnapshot = await _firestore
        .collection('Cargo')
        .orderBy('created_at', descending: true)
        .get();

    // Get all cargo IDs that have delivery records
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

    // Create notifications for unassigned cargos
    for (var doc in cargoSnapshot.docs) {
      var cargoData = doc.data() as Map<String, dynamic>;
      
      // Only create notifications for cargos not assigned to any delivery
      if (!assignedCargoIds.contains(doc.id)) {
        // Check if notification already exists for this cargo
        QuerySnapshot existingNotification = await _firestore
            .collection('notifications')
            .where('cargoId', isEqualTo: doc.id)
            .where('userId', isEqualTo: widget.userId)
            .where('type', isEqualTo: 'new_cargo')
            .get();

        if (existingNotification.docs.isEmpty) {
          // Create new cargo notification
          await _firestore.collection('notifications').add({
            'userId': widget.userId,
            'type': 'new_cargo',
            'message': 'New cargo available: ${cargoData['description'] ?? 'Cargo'} from ${cargoData['origin'] ?? 'Unknown'} to ${cargoData['destination'] ?? 'Unknown'}',
            'timestamp': cargoData['created_at'] ?? Timestamp.now(),
            'read': false,
            'cargoId': doc.id,
            'containerNo': 'CONT-${cargoData['item_number'] ?? 'N/A'}',
          });
        }
      }
    }

    print('Cargo notifications generated successfully');
  } catch (e) {
    print('Error generating cargo notifications: $e');
  }
}

  IconData _getNotificationIcon(String type) {
    switch (type) {
      case 'warning':
        return Icons.warning_amber;
      case 'info':
        return Icons.info_outline;
      case 'success':
        return Icons.check_circle_outline;
      case 'error':
        return Icons.error_outline;
      case 'new_cargo':
        return Icons.local_shipping;
      case 'delivery_assigned':
        return Icons.assignment_turned_in;
      case 'status_update':
        return Icons.update;
      case 'delivery_completed':
        return Icons.done_all;
      case 'delivery_cancelled':
        return Icons.cancel;
      default:
        return Icons.notifications;
    }
  }

  Color _getNotificationColor(String type) {
    switch (type) {
      case 'warning':
        return const Color(0xFFF59E0B);
      case 'info':
        return const Color(0xFF3B82F6);
      case 'success':
      case 'delivery_completed':
        return const Color(0xFF10B981);
      case 'error':
      case 'delivery_cancelled':
        return const Color(0xFFEF4444);
      case 'new_cargo':
        return const Color(0xFF8B5CF6);
      case 'delivery_assigned':
        return const Color(0xFF6366F1);
      case 'status_update':
        return const Color(0xFFF59E0B);
      default:
        return const Color(0xFF3B82F6);
    }
  }

  String _getNotificationTitle(String type) {
    switch (type) {
      case 'new_cargo':
        return 'New Cargo Available';
      case 'delivery_assigned':
        return 'Delivery Assigned';
      case 'delivery_completed':
        return 'Delivery Completed';
      case 'delivery_cancelled':
        return 'Delivery Cancelled';
      case 'status_update':
        return 'Status Updated';
      case 'warning':
        return 'Warning';
      case 'info':
        return 'Information';
      case 'success':
        return 'Success';
      case 'error':
        return 'Error';
      default:
        return 'Notification';
    }
  }

  String _formatTimestamp(Timestamp timestamp) {
    final date = timestamp.toDate();
    final now = DateTime.now();
    final difference = now.difference(date);
    
    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return DateFormat('MMM d, yyyy').format(date);
    }
  }

  void _handleNotificationTap(Map<String, dynamic> notification) {
    final type = notification['type'];
    final cargoId = notification['cargoId'];
    final containerNo = notification['containerNo'];

    if ((type == 'new_cargo' || type == 'delivery_assigned' || type == 'status_update') && cargoId != null) {
      // Navigate to container details page
      _navigateToContainerDetails(cargoId, containerNo);
    } else {
      // Show notification details for other types
      _showNotificationDetails(notification);
    }
  }

  Future<void> _navigateToContainerDetails(String cargoId, String? containerNo) async {
    try {
      // Fetch cargo data from Firestore
      DocumentSnapshot cargoDoc = await _firestore
          .collection('Cargo')
          .doc(cargoId)
          .get();
      
      if (cargoDoc.exists) {
        final cargoData = cargoDoc.data() as Map<String, dynamic>;
        
        // Also try to get delivery data if available
        QuerySnapshot deliverySnapshot = await _firestore
            .collection('CargoDelivery')
            .where('cargo_id', isEqualTo: cargoId)
            .limit(1)
            .get();
            
        Map<String, dynamic> combinedData = {
          ...cargoData,
          'cargo_id': cargoId,
          'containerNo': containerNo ?? 'CONT-${cargoData['item_number'] ?? 'N/A'}',
        };
        
        bool isAvailable = deliverySnapshot.docs.isEmpty;
        
        if (deliverySnapshot.docs.isNotEmpty) {
          final deliveryData = deliverySnapshot.docs.first.data() as Map<String, dynamic>;
          combinedData = {
            ...combinedData,
            'delivery_id': deliverySnapshot.docs.first.id,
            'confirmed_at': deliveryData['confirmed_at'],
            'status': deliveryData['status'],
            'courier_id': deliveryData['courier_id'],
          };
        }
        
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ContainerDetailsPage(
              containerData: combinedData,
              isAvailable: isAvailable,
            ),
          ),
        );
      } else {
        // If cargo not found, create basic data
        final basicData = {
          'cargo_id': cargoId,
          'containerNo': containerNo ?? 'N/A',
          'status': 'pending',
          'origin': 'Unknown',
          'destination': 'Unknown',
        };
        
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ContainerDetailsPage(
              containerData: basicData,
              isAvailable: true,
            ),
          ),
        );
      }
    } catch (e) {
      print('Error navigating to container details: $e');
      // Fallback navigation with basic data
      final basicData = {
        'cargo_id': cargoId,
        'containerNo': containerNo ?? 'N/A',
        'status': 'pending',
        'origin': 'Unknown',
        'destination': 'Unknown',
      };
      
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ContainerDetailsPage(
            containerData: basicData,
            isAvailable: true,
          ),
        ),
      );
    }
  }

  void _showNotificationDetails(Map<String, dynamic> notification) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(
                _getNotificationIcon(notification['type']),
                color: _getNotificationColor(notification['type']),
              ),
              const SizedBox(width: 8),
              Text(_getNotificationTitle(notification['type'])),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                notification['message'] ?? 'No message',
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 8),
              if (notification['containerNo'] != null)
                Text(
                  'Container: ${notification['containerNo']}',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                _formatTimestamp(notification['timestamp'] ?? Timestamp.now()),
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteNotification(String notificationId) async {
    try {
      await _firestore.collection('Notifications').doc(notificationId).delete();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error deleting notification: $e')),
      );
    }
  }

  Widget _buildNotificationCard(Map<String, dynamic> notification, bool isRead) {
    final type = notification['type'] ?? 'info';
    final message = notification['message'] ?? 'Notification';
    final timestamp = notification['timestamp'] ?? Timestamp.now();
    final containerNo = notification['containerNo'];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _getNotificationColor(type).withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            _getNotificationIcon(type),
            color: _getNotificationColor(type),
            size: 24,
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _getNotificationTitle(type),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: _getNotificationColor(type),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              message,
              style: TextStyle(
                fontWeight: isRead ? FontWeight.normal : FontWeight.w600,
                color: const Color(0xFF1E293B),
                fontSize: 14,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (containerNo != null) ...[
              const SizedBox(height: 4),
              Text(
                'Container: $containerNo',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF64748B),
                ),
              ),
            ],
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            _formatTimestamp(timestamp),
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF64748B),
            ),
          ),
        ),
        trailing: !isRead
            ? Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Color(0xFFEF4444),
                  shape: BoxShape.circle,
                ),
              )
            : null,
        onTap: () => _handleNotificationTap(notification),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Notifications',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: Color(0xFF1E293B),
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF1E293B)),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_notifications.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Color(0xFFEF4444)),
              onPressed: () {
                _showClearAllDialog();
              },
            ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF3B82F6)),
            onPressed: () {
              _generateCargoNotifications();
            },
            tooltip: 'Refresh Cargo Notifications',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _notifications.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.notifications_off,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'No notifications yet',
                        style: TextStyle(
                          fontSize: 16,
                          color: Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: _generateCargoNotifications,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF3B82F6),
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Load Cargo Notifications'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadNotifications,
                  child: Column(
                    children: [
                      // Statistics bar
                      Container(
                        padding: const EdgeInsets.all(16),
                        color: Colors.white,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildStatItem(
                              'Total',
                              _notifications.length.toString(),
                              Colors.blue,
                            ),
                            _buildStatItem(
                              'Unread',
                              _notifications.where((n) => n['read'] == false).length.toString(),
                              Colors.red,
                            ),
                            _buildStatItem(
                              'Cargos',
                              _notifications.where((n) => n['type'] == 'new_cargo').length.toString(),
                              Colors.green,
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _notifications.length,
                          itemBuilder: (context, index) {
                            final notification = _notifications[index];
                            final isRead = notification['read'] == true;
                            
                            return Dismissible(
                              key: Key(notification['id']),
                              direction: DismissDirection.endToStart,
                              background: Container(
                                color: Colors.red,
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 20),
                                child: const Icon(Icons.delete, color: Colors.white),
                              ),
                              onDismissed: (direction) {
                                _deleteNotification(notification['id']);
                              },
                              child: _buildNotificationCard(notification, isRead),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }

  void _showClearAllDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Clear All Notifications"),
          content: const Text("Are you sure you want to delete all notifications?"),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("Cancel"),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                for (var notification in _notifications) {
                  await _deleteNotification(notification['id']);
                }
              },
              child: const Text(
                "Clear All",
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        );
      },
    );
  }
}