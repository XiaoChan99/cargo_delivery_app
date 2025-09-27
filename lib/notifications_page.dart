import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'container_details_page.dart';

class NotificationsPage extends StatefulWidget {
  final String userId;
  
  const NotificationsPage({super.key, required this.userId});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
    _setupNotificationsListener();
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

  Future<void> _markAllAsRead() async {
    for (var notification in _notifications.where((n) => n['read'] == false)) {
      await _firestore.collection('notifications').doc(notification['id']).update({'read': true});
    }
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
      setState(() {
        _isLoading = false;
      });
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
      case 'shipping':
        return Icons.local_shipping;
      case 'delivery_assigned':
        return Icons.assignment;
      case 'status_update':
        return Icons.update;
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
        return const Color(0xFF10B981);
      case 'error':
        return const Color(0xFFEF4444);
      case 'shipping':
      case 'delivery_assigned':
        return const Color(0xFF8B5CF6);
      case 'status_update':
        return const Color(0xFF6366F1);
      default:
        return const Color(0xFF3B82F6);
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
    final deliveryId = notification['deliveryId'];
    final containerNo = notification['containerNo'];

    if ((type == 'shipping' || type == 'delivery_assigned') && deliveryId != null) {
      // Navigate to container details page
      _navigateToContainerDetails(deliveryId, containerNo);
    } else if (type == 'status_update' && deliveryId != null) {
      // Navigate to container details for status updates
      _navigateToContainerDetails(deliveryId, containerNo);
    }
    // For other notification types, just show a dialog or do nothing
  }

  Future<void> _navigateToContainerDetails(String deliveryId, String? containerNo) async {
    try {
      // Try to fetch delivery data from Firestore first
      DocumentSnapshot deliveryDoc = await _firestore
          .collection('cargo_delivery')
          .doc(deliveryId)
          .get();

      if (deliveryDoc.exists) {
        final deliveryData = deliveryDoc.data() as Map<String, dynamic>;
        
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ContainerDetailsPage(
              containerNo: deliveryData['containerNo'] ?? containerNo ?? 'N/A',
              time: deliveryData['scheduleTime'] ?? deliveryData['createdAt']?.toString() ?? '',
              pickup: deliveryData['pickupLocation'] ?? deliveryData['origin'] ?? 'Unknown',
              destination: deliveryData['destination'] ?? 'Unknown',
              status: deliveryData['status'] ?? 'pending',
              deliveryDocId: deliveryId,
            ),
          ),
        );
      } else {
        // If not found in Firestore, try to create from notification data
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ContainerDetailsPage(
              containerNo: containerNo ?? 'N/A',
              time: '',
              pickup: 'Unknown',
              destination: 'Unknown',
              status: 'pending',
              deliveryDocId: deliveryId,
            ),
          ),
        );
      }
    } catch (e) {
      // Fallback navigation with basic data
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ContainerDetailsPage(
            containerNo: containerNo ?? 'N/A',
            time: '',
            pickup: 'Unknown',
            destination: 'Unknown',
            status: 'pending',
            deliveryDocId: deliveryId,
          ),
        ),
      );
    }
  }

  Future<void> _deleteNotification(String notificationId) async {
    try {
      await _firestore.collection('notifications').doc(notificationId).delete();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error deleting notification: $e')),
      );
    }
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
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadNotifications,
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
                        child: Card(
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
                                color: _getNotificationColor(notification['type'] ?? 'info')
                                    .withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                _getNotificationIcon(notification['type'] ?? 'info'),
                                color: _getNotificationColor(notification['type'] ?? 'info'),
                                size: 24,
                              ),
                            ),
                            title: Text(
                              notification['message'] ?? 'Notification',
                              style: TextStyle(
                                fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
                                color: const Color(0xFF1E293B),
                                fontSize: 14,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                _formatTimestamp(notification['timestamp'] ?? Timestamp.now()),
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
                        ),
                      );
                    },
                  ),
                ),
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