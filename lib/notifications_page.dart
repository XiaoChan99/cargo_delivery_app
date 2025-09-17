import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationsPage extends StatefulWidget {
  final String userId;
  
  const NotificationsPage({super.key, required this.userId});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  List<Map<String, dynamic>> _notifications = [];

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    QuerySnapshot notificationsSnapshot = await _firestore
        .collection('notifications')
        .where('userId', isEqualTo: widget.userId)
        .orderBy('timestamp', descending: true)
        .get();

    List<Map<String, dynamic>> notifications = [];
    for (var doc in notificationsSnapshot.docs) {
      notifications.add(doc.data() as Map<String, dynamic>);
      
      // Mark as read
      if (!(doc.data() as Map<String, dynamic>)['read']) {
        await doc.reference.update({'read': true});
      }
    }

    setState(() {
      _notifications = notifications;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
      ),
      body: _notifications.isEmpty
          ? const Center(
              child: Text('No notifications'),
            )
          : ListView.builder(
              itemCount: _notifications.length,
              itemBuilder: (context, index) {
                final notification = _notifications[index];
                return ListTile(
                  leading: Icon(
                    notification['type'] == 'warning' 
                      ? Icons.warning_amber 
                      : Icons.info_outline,
                    color: notification['type'] == 'warning' 
                      ? Colors.orange 
                      : Colors.blue,
                  ),
                  title: Text(notification['title'] ?? 'Notification'),
                  subtitle: Text(notification['message'] ?? ''),
                  trailing: Text(
                    _formatTimestamp(notification['timestamp']),
                    style: const TextStyle(fontSize: 12),
                  ),
                );
              },
            ),
    );
  }

  String _formatTimestamp(Timestamp timestamp) {
    final date = timestamp.toDate();
    final now = DateTime.now();
    final difference = now.difference(date);
    
    if (difference.inMinutes < 60) {
      return '${difference.inMinutes} minutes ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours} hours ago';
    } else {
      return '${difference.inDays} days ago';
    }
  }
}