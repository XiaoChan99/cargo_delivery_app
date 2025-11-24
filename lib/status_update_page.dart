import 'package:flutter/material.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class StatusUpdatePage extends StatefulWidget {
  final Map<String, dynamic> containerData;

  const StatusUpdatePage({
    super.key,
    required this.containerData,
  });

  String get containerId {
    return containerData['containerId'] ?? '';
  }

  String get containerNo {
    return containerData['containerNumber'] ?? 'N/A';
  }

  String get time {
    return containerData['confirmed_at'] != null 
        ? _formatTime(containerData['confirmed_at'] as Timestamp)
        : containerData['created_at'] != null
            ? _formatTime(containerData['created_at'] as Timestamp)
            : '';
  }

  String get pickup {
    return containerData['location'] ?? 'Port Terminal';
  }

  String get destination {
    return containerData['destination'] ?? 'Delivery Point';
  }

  String _formatTime(Timestamp timestamp) {
    final date = timestamp.toDate();
    final hour = date.hour % 12;
    final period = date.hour >= 12 ? 'PM' : 'AM';
    return '${hour == 0 ? 12 : hour}:${date.minute.toString().padLeft(2, '0')} $period';
  }

  @override
  State<StatusUpdatePage> createState() => _StatusUpdatePageState();
}

class _StatusUpdatePageState extends State<StatusUpdatePage> {
  String selectedStatus = '';
  final TextEditingController notesController = TextEditingController();
  File? _selectedImage;
  final ImagePicker _imagePicker = ImagePicker();
  bool _isSubmitting = false;
  DateTime? _selectedDateTime;
  
  Map<String, dynamic>? _deliveryData;
  bool _isLoading = true;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  final Map<String, List<String>> _statusDependencies = {
    'Delivered': ['photo', 'notes'],
    'Issue Reported': ['notes'],
    'Delayed': ['notes', 'timestamp'],
    'Cancelled': ['notes'],
  };

  @override
  void initState() {
    super.initState();
    _loadDeliveryData();
  }

  // Load delivery data from ContainerDelivery collection
  Future<void> _loadDeliveryData() async {
    try {
      final containerId = widget.containerId;
      if (containerId.isNotEmpty) {
        QuerySnapshot deliveryQuery = await _firestore
            .collection('ContainerDelivery')
            .where('containerId', isEqualTo: containerId)
            .limit(1)
            .get();
        
        if (deliveryQuery.docs.isNotEmpty) {
          _deliveryData = deliveryQuery.docs.first.data() as Map<String, dynamic>;
          // Update selectedStatus based on delivery data
          final deliveryStatus = _deliveryData?['status'] ?? 'pending';
          setState(() {
            selectedStatus = _getStatusText(deliveryStatus);
          });
        } else {
          // No delivery record exists yet
          setState(() {
            selectedStatus = _getStatusText('pending');
          });
        }
      }
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading delivery data: $e');
      setState(() {
        _isLoading = false;
        selectedStatus = _getStatusText('pending');
      });
    }
  }

  String get _containerId {
    return widget.containerId;
  }

  String get _containerNo {
    return widget.containerNo;
  }

  // Get status only from ContainerDelivery
  String get _status {
    return _deliveryData?['status'] ?? 'pending';
  }

  String get _pickup {
    return widget.pickup;
  }

  String get _destination {
    return widget.destination;
  }

  String _getStatusText(String status) {
    switch (status.toLowerCase()) {
      case 'scheduled':
        return 'Scheduled';
      case 'pending':
        return 'Pending';
      case 'assigned':
        return 'Assigned';
      case 'in-progress':
      case 'in_transit':
        return 'In Progress';
      case 'delivered':
        return 'Delivered';
      case 'delayed':
        return 'Delayed';
      case 'cancelled':
        return 'Cancelled';
      default:
        return status;
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'delivered':
        return const Color(0xFF10B981);
      case 'pending':
      case 'scheduled':
        return const Color(0xFFF59E0B);
      case 'delayed':
        return const Color(0xFFEF4444);
      case 'in-progress':
      case 'in_transit':
      case 'assigned':
        return const Color(0xFF3B82F6);
      default:
        return const Color(0xFF3B82F6);
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'delivered':
        return Icons.check_circle_rounded;
      case 'pending':
      case 'scheduled':
        return Icons.schedule_rounded;
      case 'delayed':
        return Icons.watch_later_rounded;
      case 'cancelled':
        return Icons.cancel_rounded;
      case 'in-progress':
      case 'in_transit':
      case 'assigned':
        return Icons.local_shipping_rounded;
      default:
        return Icons.help_rounded;
    }
  }

  Future<void> _pickImage() async {
    final XFile? image = await _imagePicker.pickImage(source: ImageSource.camera);
    if (image != null) {
      setState(() {
        _selectedImage = File(image.path);
      });
    }
  }

  Future<void> _showDateTimePicker() async {
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF3B82F6),
            ),
          ),
          child: child!,
        );
      },
    );

    if (pickedDate != null) {
      final TimeOfDay? pickedTime = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.now(),
        builder: (context, child) {
          return Theme(
            data: ThemeData.light().copyWith(
              colorScheme: const ColorScheme.light(
                primary: Color(0xFF3B82F6),
              ),
            ),
            child: child!,
          );
        },
      );

      if (pickedTime != null) {
        setState(() {
          _selectedDateTime = DateTime(
            pickedDate.year,
            pickedDate.month,
            pickedDate.day,
            pickedTime.hour,
            pickedTime.minute,
          );
        });
      }
    }
  }

  void _performStatusUpdate() {
    setState(() {
      _isSubmitting = true;
    });

    _updateStatusInFirestore();
  }

  Future<void> _updateStatusInFirestore() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        _showErrorModal('User not logged in');
        return;
      }

      // Update both ContainerDelivery and Containers collections
      final deliveryQuery = await _firestore
          .collection('ContainerDelivery')
          .where('containerId', isEqualTo: _containerId)
          .limit(1)
          .get();

      final containerQuery = await _firestore
          .collection('Containers')
          .where('containerId', isEqualTo: _containerId)
          .limit(1)
          .get();

      final newStatus = selectedStatus.toLowerCase().replaceAll(' ', '-');
      final updateData = {
        'status': newStatus,
        'remarks': notesController.text.isNotEmpty ? notesController.text : 'Status updated to $selectedStatus',
        'confirmed_at': Timestamp.now(),
        'updated_at': Timestamp.now(),
        if (_selectedDateTime != null && selectedStatus == 'Delayed')
          'estimated_arrival': Timestamp.fromDate(_selectedDateTime!),
      };

      // Update ContainerDelivery collection
      if (deliveryQuery.docs.isNotEmpty) {
        // Update existing delivery record
        await deliveryQuery.docs.first.reference.update(updateData);
      } else {
        // Create new delivery record if it doesn't exist
        await _firestore.collection('ContainerDelivery').add({
          'containerId': _containerId,
          'courier_id': user.uid,
          ...updateData,
          'created_at': Timestamp.now(),
        });
      }

      // Update Containers collection status
      if (containerQuery.docs.isNotEmpty) {
        await containerQuery.docs.first.reference.update({
          'status': newStatus,
          'updated_at': Timestamp.now(),
        });
      }

      // Create notification
      await _firestore.collection('Notifications').add({
        'userId': user.uid,
        'type': 'status_update',
        'message': 'Status updated for Container $_containerNo: $selectedStatus',
        'timestamp': Timestamp.now(),
        'read': false,
        'containerId': _containerId,
        'containerNumber': _containerNo,
        'newStatus': newStatus,
      });

      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
        _showSuccessModal();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
        _showErrorModal('Failed to update status: $e');
      }
    }
  }

  void _showSuccessModal() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Colors.white, Color(0xFFFAFBFF)],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle_rounded,
                    color: Color(0xFF10B981),
                    size: 40,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  "Success!",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  "Status updated successfully!",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).pop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Done',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showErrorModal(String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Colors.white, Color(0xFFFAFBFF)],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.error_outline_rounded,
                    color: Color(0xFFEF4444),
                    size: 40,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  "Error",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEF4444),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'OK',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _saveStatusUpdate() {
    if (selectedStatus.isEmpty) {
      _showErrorModal('Please select a status');
      return;
    }

    final dependencies = _statusDependencies[selectedStatus] ?? [];
    
    if (dependencies.contains('notes') && notesController.text.trim().isEmpty) {
      _showErrorModal('Please add notes for the status update');
      return;
    }

    if (dependencies.contains('photo') && _selectedImage == null) {
      _showErrorModal('Please add a photo for this status');
      return;
    }

    if (dependencies.contains('timestamp') && _selectedDateTime == null) {
      _showErrorModal('Please select estimated arrival time for delayed status');
      return;
    }

    _performStatusUpdate();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF3B82F6)),
              ),
              const SizedBox(height: 16),
              const Text(
                'Loading delivery data...',
                style: TextStyle(
                  color: Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 375;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              child: Column(
                children: [
                  // Header
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.fromLTRB(
                      isSmallScreen ? 16 : 24,
                      MediaQuery.of(context).padding.top + 8,
                      isSmallScreen ? 16 : 24,
                      16,
                    ),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFF1E40AF),
                          Color(0xFF3B82F6),
                        ],
                      ),
                    ),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.arrow_back_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        const Icon(
                          Icons.update_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          "Update Status",
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Delivery Info Card
                  _buildSectionContainer(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.local_shipping_rounded,
                              color: Color(0xFF3B82F6),
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              "Delivery Information",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1E293B),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
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
                                children: [
                                  const Icon(
                                    Icons.schedule_rounded,
                                    color: Color(0xFF64748B),
                                    size: 16,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    "${widget.time} - $_containerNo",
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF1E293B),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.place_rounded,
                                    color: Color(0xFF64748B),
                                    size: 14,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      _pickup,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: Color(0xFF64748B),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.flag_rounded,
                                    color: Color(0xFF64748B),
                                    size: 14,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      _destination,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: Color(0xFF64748B),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.circle_rounded,
                                    color: Color(0xFF64748B),
                                    size: 14,
                                  ),
                                  const SizedBox(width: 6),
                                  const Text(
                                    "Current Status: ",
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Color(0xFF64748B),
                                    ),
                                  ),
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: _getStatusColor(_status),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    _getStatusText(_status),
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: _getStatusColor(_status),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Status Selection
                  _buildSectionContainer(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.flag_rounded,
                              color: Color(0xFF3B82F6),
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              "Select New Status",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1E293B),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            'Delivered',
                            'In Progress',
                            'Delayed',
                            'Issue Reported',
                            'Cancelled'
                          ].map((status) {
                            return ChoiceChip(
                              label: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _getStatusIcon(status),
                                    size: 16,
                                    color: selectedStatus == status 
                                        ? Colors.white 
                                        : const Color(0xFF64748B),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(status),
                                ],
                              ),
                              selected: selectedStatus == status,
                              onSelected: (selected) {
                                setState(() {
                                  selectedStatus = selected ? status : '';
                                  if (status != 'Delayed') {
                                    _selectedDateTime = null;
                                  }
                                });
                              },
                              selectedColor: const Color(0xFF3B82F6),
                              labelStyle: TextStyle(
                                color: selectedStatus == status 
                                    ? Colors.white 
                                    : const Color(0xFF64748B),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Notes Section
                  _buildSectionContainer(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.notes_rounded,
                              color: Color(0xFF3B82F6),
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              "Notes",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1E293B),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: notesController,
                          maxLines: 4,
                          decoration: InputDecoration(
                            hintText: 'Add notes about the status update...',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0xFF3B82F6)),
                            ),
                            contentPadding: const EdgeInsets.all(16),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Estimated Arrival Time (for Delayed status)
                  if (selectedStatus == 'Delayed') ...[
                    const SizedBox(height: 16),
                    _buildSectionContainer(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.access_time_rounded,
                                color: Color(0xFF3B82F6),
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                "Estimated Arrival Time",
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF1E293B),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          GestureDetector(
                            onTap: _showDateTimePicker,
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.calendar_today_rounded,
                                    color: _selectedDateTime != null 
                                        ? const Color(0xFF3B82F6)
                                        : const Color(0xFF64748B),
                                    size: 20,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      _selectedDateTime != null
                                          ? DateFormat('MMM dd, yyyy - HH:mm').format(_selectedDateTime!)
                                          : 'Select date and time',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: _selectedDateTime != null
                                            ? const Color(0xFF1E293B)
                                            : const Color(0xFF94A3B8),
                                        fontWeight: _selectedDateTime != null
                                            ? FontWeight.w500
                                            : FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                  Icon(
                                    Icons.arrow_forward_ios_rounded,
                                    color: const Color(0xFF64748B),
                                    size: 16,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 16),

                  // Photo Section
                  _buildSectionContainer(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.photo_camera_rounded,
                              color: Color(0xFF3B82F6),
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              "Photo",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1E293B),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              selectedStatus == 'Delivered' ? '(Required)' : '(Optional)',
                              style: const TextStyle(
                                fontSize: 14,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _selectedImage != null
                            ? Column(
                                children: [
                                  Container(
                                    height: 150,
                                    width: double.infinity,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      image: DecorationImage(
                                        image: FileImage(_selectedImage!),
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  OutlinedButton.icon(
                                    onPressed: _pickImage,
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: const Color(0xFF3B82F6),
                                      side: const BorderSide(color: Color(0xFF3B82F6)),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    icon: const Icon(Icons.camera_alt_rounded),
                                    label: const Text('Retake Photo'),
                                  ),
                                ],
                              )
                            : Container(
                                height: 150,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                ),
                                child: Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.add_a_photo_rounded, size: 40),
                                        color: const Color(0xFF64748B),
                                        onPressed: _pickImage,
                                      ),
                                      const SizedBox(height: 8),
                                      const Text(
                                        'Add Photo',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Color(0xFF64748B),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Action Buttons
                  Container(
                    margin: EdgeInsets.symmetric(
                      horizontal: isSmallScreen ? 12 : 16,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF64748B),
                              side: const BorderSide(color: Color(0xFF64748B)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              backgroundColor: Colors.white,
                            ),
                            onPressed: _isSubmitting ? null : () => Navigator.pop(context),
                            icon: const Icon(Icons.cancel_rounded),
                            label: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF3B82F6),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            onPressed: _isSubmitting ? null : _saveStatusUpdate,
                            icon: _isSubmitting
                                ? Container(
                                    width: 16,
                                    height: 16,
                                    margin: const EdgeInsets.all(2),
                                    child: const CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                    ),
                                  )
                                : const Icon(Icons.check_circle_rounded),
                            label: _isSubmitting
                                ? const Text('Updating...')
                                : const Text('Update Status'),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),
                ],
              ),
            ),

            // Loading Overlay
            if (_isSubmitting)
              Container(
                color: Colors.black.withOpacity(0.5),
                child: const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF3B82F6)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionContainer({required Widget child}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}