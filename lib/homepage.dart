import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'schedulepage.dart';
import 'livemap_page.dart';
import 'settings_page.dart';
import 'notifications_page.dart';
import 'dart:convert'; 

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  User? _currentUser;
  Map<String, dynamic> _userData = {};
  String _userRole = '';
  int _notificationCount = 0;
  List<Map<String, dynamic>> _upcomingTasks = [];
  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;
  String? _errorMessage;
  
  // New state variables for Today's Summary
  int _deliveredToday = 0;
  int _pendingToday = 0;
  int _delayedToday = 0;
  Map<String, dynamic>? _currentDelivery;

  @override
  void initState() {
    super.initState();
    _currentUser = _auth.currentUser;
    if (_currentUser != null) {
      _loadData();
      _setupNotificationsListener();
    } else {
      _isLoading = false;
      _errorMessage = "User not authenticated";
    }
  }

  Future<void> _loadData() async {
    try {
      await Future.wait([
        _loadUserData(),
        _loadNotifications(),
        _loadUpcomingTasks(),
        _loadTodaysSummary(),
        _loadCurrentDelivery(),
      ]);
    } catch (e) {
      setState(() {
        _errorMessage = "Error loading data: ${e.toString()}";
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _setupNotificationsListener() {
    if (_currentUser != null) {
      _firestore
          .collection('notifications')
          .where('userId', isEqualTo: _currentUser!.uid)
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
            _notificationCount = notifications.where((n) => n['read'] == false).length;
          });
        }
      });
    }
  }

  Future<void> _loadUserData() async {
    if (_currentUser != null) {
      try {
        // Only look for couriers (remove shipper logic)
        DocumentSnapshot courierDoc = await _firestore
            .collection('Couriers')
            .doc(_currentUser!.uid)
            .get();
        
        if (courierDoc.exists) {
          setState(() {
            _userData = courierDoc.data() as Map<String, dynamic>;
            _userRole = 'courier';
          });
          return;
        }
        
        // If user not found in couriers collection
        print('User data not found in Firestore');
        setState(() {
          _errorMessage = "User profile not found";
        });
        
      } catch (e) {
        print('Error loading user data: $e');
        setState(() {
          _errorMessage = "Error loading user profile";
        });
      }
    }
  }

  Future<void> _loadNotifications() async {
    if (_currentUser != null) {
      try {
        QuerySnapshot notificationsSnapshot = await _firestore
            .collection('notifications')
            .where('userId', isEqualTo: _currentUser!.uid)
            .orderBy('timestamp', descending: true)
            .limit(5)
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
          _notificationCount = notifications.where((n) => n['read'] == false).length;
        });
      } catch (e) {
        print('Error loading notifications: $e');
        // Silently handle error - notifications are optional
      }
    }
  }

  Future<void> _loadUpcomingTasks() async {
    if (_currentUser != null) {
      try {
        DateTime now = DateTime.now();
        DateTime startOfToday = DateTime(now.year, now.month, now.day);
        
        // Get all tasks and filter locally
        QuerySnapshot tasksSnapshot = await _firestore
            .collection('tasks')
            .where('userId', isEqualTo: _currentUser!.uid)
            .get();

        List<Map<String, dynamic>> tasks = [];
        for (var doc in tasksSnapshot.docs) {
          var task = doc.data() as Map<String, dynamic>;
          
          // Check if task date is today or future
          if (task['scheduleDate'] != null) {
            DateTime scheduleDate = (task['scheduleDate'] as Timestamp).toDate();
            if (scheduleDate.isAfter(startOfToday) || 
                scheduleDate.isAtSameMomentAs(startOfToday)) {
              tasks.add({
                ...task,
                'id': doc.id,
              });
            }
          }
        }

        // Sort by date and time
        tasks.sort((a, b) {
          DateTime dateA = (a['scheduleDate'] as Timestamp).toDate();
          DateTime dateB = (b['scheduleDate'] as Timestamp).toDate();
          
          // If same date, compare times
          if (dateA.isAtSameMomentAs(dateB)) {
            TimeOfDay timeA = _parseTimeFromString(a['scheduleTime']);
            TimeOfDay timeB = _parseTimeFromString(b['scheduleTime']);
            return timeA.hour * 60 + timeA.minute - (timeB.hour * 60 + timeB.minute);
          }
          
          return dateA.compareTo(dateB);
        });

        // Take only first 3 tasks
        setState(() {
          _upcomingTasks = tasks.take(3).toList();
        });
      } catch (e) {
        print('Error loading tasks: $e');
        // Silently handle error - tasks are optional
      }
    }
  }

  Future<void> _loadTodaysSummary() async {
    if (_currentUser != null) {
      try {
        DateTime now = DateTime.now();
        DateTime startOfToday = DateTime(now.year, now.month, now.day);
        DateTime endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59);
        
        QuerySnapshot tasksSnapshot = await _firestore
            .collection('tasks')
            .where('userId', isEqualTo: _currentUser!.uid)
            .where('scheduleDate', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfToday))
            .where('scheduleDate', isLessThanOrEqualTo: Timestamp.fromDate(endOfToday))
            .get();

        int delivered = 0;
        int pending = 0;
        int delayed = 0;
        
        for (var doc in tasksSnapshot.docs) {
          var task = doc.data() as Map<String, dynamic>;
          String status = task['status']?.toString().toLowerCase() ?? 'pending';
          
          if (status == 'delivered') {
            delivered++;
          } else if (status == 'pending') {
            pending++;
          } else if (status == 'delayed') {
            delayed++;
          }
        }
        
        setState(() {
          _deliveredToday = delivered;
          _pendingToday = pending;
          _delayedToday = delayed;
        });
      } catch (e) {
        print('Error loading today\'s summary: $e');
        // Silently handle error - summary is optional
      }
    }
  }

  Future<void> _loadCurrentDelivery() async {
    if (_currentUser != null) {
      try {
        DateTime now = DateTime.now();
        
        // Get the first active delivery (status not delivered)
        QuerySnapshot tasksSnapshot = await _firestore
            .collection('tasks')
            .where('userId', isEqualTo: _currentUser!.uid)
            .where('status', whereIn: ['pending', 'in-progress', 'delayed'])
            .orderBy('scheduleDate')
            .limit(1)
            .get();

        if (tasksSnapshot.docs.isNotEmpty) {
          var task = tasksSnapshot.docs.first.data() as Map<String, dynamic>;
          
          // Calculate distance (this would normally come from your mapping service)
          String origin = task['origin'] ?? 'Gothong Port';
          String destination = task['destination'] ?? 'Carcar';
          int distance = _calculateDistance(origin, destination);
          
          setState(() {
            _currentDelivery = {
              ...task,
              'origin': origin,
              'destination': destination,
              'distance': distance,
            };
          });
        } else {
          setState(() {
            _currentDelivery = null;
          });
        }
      } catch (e) {
        print('Error loading current delivery: $e');
        // Silently handle error - current delivery is optional
      }
    }
  }

  // Simple distance calculation (in a real app, you'd use a mapping API)
  int _calculateDistance(String origin, String destination) {
    // This is a simplified mock calculation
    if (origin.contains('Gothong') && destination.contains('Carcar')) {
      return 100;
    } else if (origin.contains('Gothong') && destination.contains('Toledo')) {
      return 85;
    } else if (origin.contains('Gothong') && destination.contains('Naga')) {
      return 45;
    } else {
      return 60; // Default distance
    }
  }

  String _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'delivered':
        return '0xFF10B981';
      case 'pending':
        return '0xFFF59E0B';
      case 'delayed':
        return '0xFFEF4444';
      default:
        return '0xFF3B82F6';
    }
  }

  String _getDayAbbreviation(DateTime date) {
    switch (date.weekday) {
      case 1: return 'Mon';
      case 2: return 'Tue';
      case 3: return 'Wed';
      case 4: return 'Thu';
      case 5: return 'Fri';
      case 6: return 'Sat';
      case 7: return 'Sun';
      default: return '';
    }
  }

  String _formatTime(TimeOfDay time) {
    final hour = time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  String _formatTimeAgo(Timestamp timestamp) {
    final now = DateTime.now();
    final time = timestamp.toDate();
    final difference = now.difference(time);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} minutes ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours} hours ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      return '${time.day}/${time.month}/${time.year}';
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
        return const Color(0xFF8B5CF6);
      default:
        return const Color(0xFF3B82F6);
    }
  }

  // Helper method to get full name from user data
  String _getFullName() {
    String firstName = _userData['first_name'] ?? '';
    String lastName = _userData['last_name'] ?? '';
    
    if (firstName.isNotEmpty && lastName.isNotEmpty) {
      return '$firstName $lastName';
    } else if (firstName.isNotEmpty) {
      return firstName;
    } else if (lastName.isNotEmpty) {
      return lastName;
    } else {
      return 'Driver';
    }
  }

  // Helper method to get driver ID from user data
  String _getDriverId() {
    return _userData['driverId'] ?? _userData['license_number'] ?? 'N/A';
  }

  // Helper method to display role-specific text
  String _getRoleText() {
    return "License No.";
  }

  // Helper method to display profile image
  Widget _getProfileWidget() {
    String? profileImageBase64 = _userData['profile_image_base64'];
    
    if (profileImageBase64 != null && profileImageBase64.isNotEmpty) {
      // Check if it's a data URL format
      if (profileImageBase64.contains('base64,')) {
        profileImageBase64 = profileImageBase64.split('base64,').last;
      }
      
      try {
        return CircleAvatar(
          radius: 20,
          backgroundImage: MemoryImage(base64Decode(profileImageBase64)),
        );
      } catch (e) {
        print('Error decoding profile image: $e');
        return _buildDefaultProfile();
      }
    } else {
      return _buildDefaultProfile();
    }
  }

  Widget _buildDefaultProfile() {
    return CircleAvatar(
      radius: 20,
      backgroundColor: Colors.white.withOpacity(0.2),
      child: const Icon(
        Icons.person,
        color: Colors.white,
        size: 20,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _loadData,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Updated Header to match SchedulePage
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 30, 16, 20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF1E40AF),
                    Color(0xFF3B82F6),
                  ],
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
                          _getProfileWidget(),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _getFullName(),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                "${_getRoleText()} ${_getDriverId()}",
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      GestureDetector(
                        onTap: () {
                          if (_currentUser != null) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => NotificationsPage(userId: _currentUser!.uid),
                              ),
                            ).then((_) {
                              _loadNotifications();
                            });
                          }
                        },
                        child: Stack(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.notifications_outlined,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                            if (_notificationCount > 0)
                              Positioned(
                                right: 4,
                                top: 4,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFEF4444),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Text(
                                    _notificationCount > 9 ? '9+' : _notificationCount.toString(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  StreamBuilder<QuerySnapshot>(
                    stream: _firestore
                        .collection('tasks')
                        .where('userId', isEqualTo: _currentUser?.uid)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return Row(
                          children: [
                            Expanded(child: _buildStatusCard("0", "Delivered", const Color(0xFF10B981))),
                            const SizedBox(width: 12),
                            Expanded(child: _buildStatusCard("0", "Pending", const Color(0xFFF59E0B))),
                            const SizedBox(width: 12),
                            Expanded(child: _buildStatusCard("0", "Delayed", const Color(0xFFEF4444))),
                          ],
                        );
                      }
                      
                      int delivered = 0;
                      int pending = 0;
                      int delayed = 0;
                      
                      for (var doc in snapshot.data!.docs) {
                        var task = doc.data() as Map<String, dynamic>;
                        String status = task['status']?.toString().toLowerCase() ?? 'pending';
                        
                        if (status == 'delivered') {
                          delivered++;
                        } else if (status == 'pending') {
                          pending++;
                        } else if (status == 'delayed') {
                          delayed++;
                        }
                      }
                      
                      return Row(
                        children: [
                          Expanded(child: _buildStatusCard(delivered.toString(), "Delivered", const Color(0xFF10B981))),
                          const SizedBox(width: 12),
                          Expanded(child: _buildStatusCard(pending.toString(), "Pending", const Color(0xFFF59E0B))),
                          const SizedBox(width: 12),
                          Expanded(child: _buildStatusCard(delayed.toString(), "Delayed", const Color(0xFFEF4444))),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
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
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Upcoming Schedule",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const SchedulePage()),
                          );
                        },
                        child: const Text(
                          "View All",
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF3B82F6),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_upcomingTasks.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16.0),
                      child: Text(
                        "No upcoming tasks",
                        style: TextStyle(
                          color: Color(0xFF64748B),
                        ),
                      ),
                    )
                  else
                    ..._upcomingTasks.map((task) {
                      DateTime scheduleDate = (task['scheduleDate'] as Timestamp).toDate();
                      TimeOfDay scheduleTime = _parseTimeFromString(task['scheduleTime']);
                      
                      return Column(
                        children: [
                          _buildScheduleItem(
                            _getDayAbbreviation(scheduleDate),
                            _formatTime(scheduleTime),
                            "Container No. ${task['containerNo']}",
                            Color(int.parse(_getStatusColor(task['status'])))
                          ),
                          if (_upcomingTasks.indexOf(task) < _upcomingTasks.length - 1)
                            const SizedBox(height: 12),
                        ],
                      );
                    }),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
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
                  const Text(
                    "Today's Summary",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _buildSummaryItem(_deliveredToday.toString(), "DELIVERED", const Color(0xFF10B981)),
                      ),
                      Expanded(
                        child: _buildSummaryItem(_pendingToday.toString(), "PENDING", const Color(0xFFF59E0B)),
                      ),
                      Expanded(
                        child: _buildSummaryItem(_delayedToday.toString(), "DELAYED", const Color(0xFFEF4444)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_currentDelivery != null)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF3B82F6).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.local_shipping,
                              color: Color(0xFF3B82F6),
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "${_currentDelivery!['origin']} - ${_currentDelivery!['destination']}",
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF1E293B),
                                  ),
                                ),
                                Text(
                                  "Container No. ${_currentDelivery!['containerNo'] ?? 'N/A'}",
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            "Distance ${_currentDelivery!['distance']}km",
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: const Center(
                        child: Text(
                          "No active deliveries",
                          style: TextStyle(
                            fontSize: 14,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
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
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Notifications",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      if (_notifications.isNotEmpty)
                        TextButton(
                          onPressed: () {
                            if (_currentUser != null) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => NotificationsPage(userId: _currentUser!.uid),
                                ),
                              ).then((_) {
                                _loadNotifications();
                              });
                            }
                          },
                          child: const Text(
                            "View All",
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF3B82F6),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  if (_notifications.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8.0),
                      child: Text(
                        "No notifications yet",
                        style: TextStyle(
                          color: Color(0xFF64748B),
                        ),
                      ),
                    )
                  else
                    ..._notifications.take(2).map((notification) {
                      return Column(
                        children: [
                          _buildNotificationItem(
                            _getNotificationIcon(notification['type'] ?? 'info'),
                            _getNotificationColor(notification['type'] ?? 'info'),
                            notification['message'] ?? 'No message',
                            _formatTimeAgo(notification['timestamp'] ?? Timestamp.now()),
                            isRead: notification['read'] ?? false,
                          ),
                          if (_notifications.indexOf(notification) < _notifications.length - 1 && 
                              _notifications.indexOf(notification) < 1)
                            const SizedBox(height: 12),
                        ],
                      );
                    }),
                ],
              ),
            ),
            
            const SizedBox(height: 100),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNavigation(context, 0),
    );
  }

  TimeOfDay _parseTimeFromString(String timeString) {
    try {
      List<String> parts = timeString.split(':');
      int hour = int.parse(parts[0]);
      int minute = int.parse(parts[1]);
      return TimeOfDay(hour: hour, minute: minute);
    } catch (e) {
      return const TimeOfDay(hour: 12, minute: 0);
    }
  }

  Widget _buildStatusCard(String number, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            number,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.white70,
            ),
          ),
        ],
      )
    );
  }

  Widget _buildScheduleItem(String day, String time, String container, Color color) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    day,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  Text(
                    time,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                container,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryItem(String number, String label, Color color) {
    return Column(
      children: [
        Text(
          number,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: Color(0xFF64748B),
          ),
        ),
      ],
    );
  }

  Widget _buildNotificationItem(IconData icon, Color color, String message, String time, {bool isRead = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            color: color,
            size: 16,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                message,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isRead ? FontWeight.w500 : FontWeight.w700,
                  color: const Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                time,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
        if (!isRead)
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Color(0xFFEF4444),
              shape: BoxShape.circle,
            ),
          ),
      ],
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
      )
    );
  }
}