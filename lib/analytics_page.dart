import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'dart:math';
import 'dart:ui' as ui;

class AnalyticsPage extends StatefulWidget {
  final String userId;

  const AnalyticsPage({super.key, required this.userId});

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // Analytics data
  Map<String, dynamic> _analyticsData = {};
  List<Map<String, dynamic>> _statusDistribution = [];
  List<Map<String, dynamic>> _monthlyDeliveries = [];
  
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadAnalyticsData();
  }

  Future<void> _loadAnalyticsData() async {
    try {
      await Future.wait([
        _loadBasicStats(),
        _loadStatusDistribution(),
        _loadMonthlyData(),
      ]);
      
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = "Error loading analytics: ${e.toString()}";
        _isLoading = false;
      });
    }
  }

  Future<void> _loadBasicStats() async {
    try {
      // Get total deliveries count (only deliveries accepted by this courier)
      QuerySnapshot totalSnapshot = await _firestore
          .collection('CargoDelivery')
          .where('courier_id', isEqualTo: widget.userId)
          .get();

      // Get completed deliveries
      QuerySnapshot completedSnapshot = await _firestore
          .collection('CargoDelivery')
          .where('courier_id', isEqualTo: widget.userId)
          .where('status', isEqualTo: 'delivered')
          .get();

      // Get in-progress deliveries
      QuerySnapshot inProgressSnapshot = await _firestore
          .collection('CargoDelivery')
          .where('courier_id', isEqualTo: widget.userId)
          .where('status', whereIn: ['in-progress', 'in_transit', 'assigned'])
          .get();

      // Get delayed deliveries
      QuerySnapshot delayedSnapshot = await _firestore
          .collection('CargoDelivery')
          .where('courier_id', isEqualTo: widget.userId)
          .where('status', isEqualTo: 'delayed')
          .get();

      // Get cancelled deliveries
      QuerySnapshot cancelledSnapshot = await _firestore
          .collection('CargoDelivery')
          .where('courier_id', isEqualTo: widget.userId)
          .where('status', isEqualTo: 'cancelled')
          .get();

      // Calculate average delivery time
      double averageDeliveryTime = await _calculateAverageDeliveryTime();

      setState(() {
        _analyticsData = {
          'totalDeliveries': totalSnapshot.docs.length,
          'completedDeliveries': completedSnapshot.docs.length,
          'inProgressDeliveries': inProgressSnapshot.docs.length,
          'delayedDeliveries': delayedSnapshot.docs.length,
          'cancelledDeliveries': cancelledSnapshot.docs.length,
          'completionRate': totalSnapshot.docs.isNotEmpty 
              ? (completedSnapshot.docs.length / totalSnapshot.docs.length * 100).toStringAsFixed(1)
              : '0.0',
          'averageDeliveryTime': averageDeliveryTime.toStringAsFixed(1),
        };
      });
    } catch (e) {
      print('Error loading basic stats: $e');
    }
  }

  Future<double> _calculateAverageDeliveryTime() async {
    try {
      QuerySnapshot completedDeliveries = await _firestore
          .collection('CargoDelivery')
          .where('courier_id', isEqualTo: widget.userId)
          .where('status', isEqualTo: 'delivered')
          .get();

      if (completedDeliveries.docs.isEmpty) return 0.0;

      double totalHours = 0;
      int count = 0;

      for (var doc in completedDeliveries.docs) {
        var data = doc.data() as Map<String, dynamic>;
        Timestamp? confirmedAt = data['confirmed_at'];
        Timestamp? deliveredAt = data['delivered_at'] ?? data['updated_at'];

        if (confirmedAt != null && deliveredAt != null) {
          final confirmedTime = confirmedAt.toDate();
          final deliveredTime = deliveredAt.toDate();
          final difference = deliveredTime.difference(confirmedTime);
          totalHours += difference.inHours.toDouble();
          count++;
        }
      }

      return count > 0 ? totalHours / count : 0.0;
    } catch (e) {
      print('Error calculating average delivery time: $e');
      return 0.0;
    }
  }

  Future<void> _loadStatusDistribution() async {
    try {
      QuerySnapshot snapshot = await _firestore
          .collection('CargoDelivery')
          .where('courier_id', isEqualTo: widget.userId)
          .get();

      Map<String, int> statusCount = {
        'Completed': 0,
        'In Progress': 0,
        'Delayed': 0,
        'Cancelled': 0,
        'Pending': 0,
      };

      for (var doc in snapshot.docs) {
        var data = doc.data() as Map<String, dynamic>;
        String status = data['status']?.toString().toLowerCase() ?? '';

        if (status == 'delivered') {
          statusCount['Completed'] = statusCount['Completed']! + 1;
        } else if (status == 'in-progress' || status == 'in_transit' || status == 'assigned') {
          statusCount['In Progress'] = statusCount['In Progress']! + 1;
        } else if (status == 'delayed') {
          statusCount['Delayed'] = statusCount['Delayed']! + 1;
        } else if (status == 'cancelled') {
          statusCount['Cancelled'] = statusCount['Cancelled']! + 1;
        } else {
          statusCount['Pending'] = statusCount['Pending']! + 1;
        }
      }

      List<Map<String, dynamic>> statusData = [];
      statusCount.forEach((status, count) {
        if (count > 0) {
          statusData.add({
            'status': status,
            'count': count,
            'percentage': snapshot.docs.isNotEmpty ? (count / snapshot.docs.length * 100).toStringAsFixed(1) : '0.0',
            'color': _getStatusColor(status),
          });
        }
      });

      setState(() {
        _statusDistribution = statusData;
      });
    } catch (e) {
      print('Error loading status distribution: $e');
    }
  }

  Future<void> _loadMonthlyData() async {
    try {
      QuerySnapshot snapshot = await _firestore
          .collection('CargoDelivery')
          .where('courier_id', isEqualTo: widget.userId)
          .get();

      Map<String, int> monthlyCount = {};

      for (var doc in snapshot.docs) {
        var data = doc.data() as Map<String, dynamic>;
        Timestamp? timestamp = data['confirmed_at'] ?? data['created_at'];
        
        if (timestamp != null) {
          final date = timestamp.toDate();
          final monthKey = DateFormat('MMM yyyy').format(date);
          
          monthlyCount.update(monthKey, (value) => value + 1, ifAbsent: () => 1);
        }
      }

      List<Map<String, dynamic>> monthlyData = [];
      monthlyCount.forEach((month, count) {
        monthlyData.add({
          'month': month,
          'deliveries': count,
          'color': _getMonthColor(month),
        });
      });

      // Sort by date
      monthlyData.sort((a, b) {
        final dateA = DateFormat('MMM yyyy').parse(a['month']);
        final dateB = DateFormat('MMM yyyy').parse(b['month']);
        return dateA.compareTo(dateB);
      });

      setState(() {
        _monthlyDeliveries = monthlyData;
      });
    } catch (e) {
      print('Error loading monthly data: $e');
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Completed':
        return const Color(0xFF10B981); // Green
      case 'In Progress':
        return const Color(0xFF3B82F6); // Blue
      case 'Delayed':
        return const Color(0xFFF59E0B); // Amber
      case 'Cancelled':
        return const Color(0xFFEF4444); // Red
      case 'Pending':
        return const Color(0xFF64748B); // Slate
      default:
        return const Color(0xFF64748B);
    }
  }

  Color _getMonthColor(String month) {
    // Generate consistent colors based on month
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    
    final colors = [
      const Color(0xFF3B82F6), // Blue
      const Color(0xFF10B981), // Green
      const Color(0xFFF59E0B), // Amber
      const Color(0xFFEF4444), // Red
      const Color(0xFF8B5CF6), // Purple
      const Color(0xFF06B6D4), // Cyan
      const Color(0xFF84CC16), // Lime
      const Color(0xFFF97316), // Orange
      const Color(0xFFEC4899), // Pink
      const Color(0xFF6366F1), // Indigo
      const Color(0xFF14B8A6), // Teal
      const Color(0xFFF43F5E), // Rose
    ];
    
    final monthAbbr = month.split(' ')[0];
    final index = months.indexOf(monthAbbr);
    return index >= 0 && index < colors.length ? colors[index] : const Color(0xFF64748B);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Performance Analytics',
          style: TextStyle(
            fontWeight: FontWeight.w600,
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
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF3B82F6)),
            onPressed: _loadAnalyticsData,
          ),
        ],
      ),
      backgroundColor: const Color(0xFFF8FAFC),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text(
                    'Loading analytics...',
                    style: TextStyle(color: Color(0xFF64748B)),
                  ),
                ],
              ),
            )
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 64, color: Color(0xFF64748B)),
                      const SizedBox(height: 16),
                      Text(
                        _errorMessage!,
                        style: const TextStyle(color: Color(0xFF64748B)),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: _loadAnalyticsData,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF3B82F6),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        ),
                        child: const Text('Try Again'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadAnalyticsData,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Welcome Header
                        _buildWelcomeHeader(),
                        const SizedBox(height: 24),
                        
                        // Stats Overview
                        _buildStatsOverview(),
                        const SizedBox(height: 24),
                        
                        // Status Distribution Chart with Legends
                        _buildStatusChartWithLegends(),
                        const SizedBox(height: 24),
                        
                        // Monthly Cargo Distribution Pie Chart
                        _buildMonthlyDistribution(),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildWelcomeHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Delivery Analytics',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${_analyticsData['totalDeliveries'] ?? 0} accepted deliveries • ${_analyticsData['completionRate'] ?? '0'}% completion rate',
            style: const TextStyle(
              fontSize: 14,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsOverview() {
    return Container(
      padding: const EdgeInsets.all(20),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.analytics, color: Color(0xFF3B82F6), size: 20),
              SizedBox(width: 8),
              Text(
                'Performance Overview',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1E293B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.6,
            children: [
              _buildStatCard(
                'Total Deliveries',
                _analyticsData['totalDeliveries'].toString(),
                Icons.local_shipping_outlined,
                const Color(0xFF3B82F6),
              ),
              _buildStatCard(
                'Completed',
                _analyticsData['completedDeliveries'].toString(),
                Icons.check_circle_outline,
                const Color(0xFF10B981),
              ),
              _buildStatCard(
                'In Progress',
                _analyticsData['inProgressDeliveries'].toString(),
                Icons.schedule,
                const Color(0xFFF59E0B),
              ),
              _buildStatCard(
                'Delayed',
                _analyticsData['delayedDeliveries'].toString(),
                Icons.warning_amber_outlined,
                const Color(0xFFF59E0B),
              ),
              _buildStatCard(
                'Cancelled',
                _analyticsData['cancelledDeliveries'].toString(),
                Icons.cancel_outlined,
                const Color(0xFFEF4444),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChartWithLegends() {
    return Container(
      padding: const EdgeInsets.all(20),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.pie_chart_outline, color: Color(0xFF3B82F6), size: 20),
              SizedBox(width: 8),
              Text(
                'Delivery Status Distribution',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1E293B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _statusDistribution.isEmpty
              ? Container(
                  height: 200,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.pie_chart, size: 48, color: Color(0xFFCBD5E1)),
                        SizedBox(height: 8),
                        Text(
                          'No delivery data available',
                          style: TextStyle(color: Color(0xFF94A3B8)),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    SizedBox(
                      height: 200,
                      child: Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: PieChartWidget(
                              data: _statusDistribution,
                              total: _statusDistribution.fold<int>(0, (sum, item) => sum + (item['count'] as int)),
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: _buildStatusLegends(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildSummaryItem('Completion Rate', '${_analyticsData['completionRate']}%'),
                          _buildSummaryItem('Avg. Time', '${_analyticsData['averageDeliveryTime']}h'),
                        ],
                      ),
                    ),
                  ],
                ),
        ],
      ),
    );
  }

  Widget _buildStatusLegends() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: _statusDistribution.map((item) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: item['color'] as Color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item['status'],
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ),
              Text(
                '${item['count']} (${item['percentage']}%)',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF64748B),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSummaryItem(String title, String value) {
    return Column(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 12,
            color: Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1E293B),
          ),
        ),
      ],
    );
  }

  Widget _buildMonthlyDistribution() {
    return Container(
      padding: const EdgeInsets.all(20),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.calendar_today, color: Color(0xFF3B82F6), size: 20),
              SizedBox(width: 8),
              Text(
                'Monthly Cargo Distribution',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1E293B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _monthlyDeliveries.isEmpty
              ? Container(
                  height: 200,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.pie_chart, size: 48, color: Color(0xFFCBD5E1)),
                        SizedBox(height: 8),
                        Text(
                          'No monthly data available',
                          style: TextStyle(color: Color(0xFF94A3B8)),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    SizedBox(
                      height: 200,
                      child: Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: PieChartWidget(
                              data: _monthlyDeliveries,
                              total: _monthlyDeliveries.fold<int>(0, (sum, item) => sum + (item['deliveries'] as int)),
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: _buildMonthlyLegends(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildMonthlySummaryItem('Total Months', _monthlyDeliveries.length.toString()),
                          _buildMonthlySummaryItem('Total Deliveries', 
                            _monthlyDeliveries.fold<int>(0, (sum, item) => sum + (item['deliveries'] as int)).toString()),
                        ],
                      ),
                    ),
                  ],
                ),
        ],
      ),
    );
  }

  Widget _buildMonthlyLegends() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: _monthlyDeliveries.map((item) {
        final total = _monthlyDeliveries.fold<int>(0, (sum, i) => sum + (i['deliveries'] as int));
        final percentage = total > 0 ? ((item['deliveries'] as int) / total * 100).toStringAsFixed(1) : '0.0';
        
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: item['color'] as Color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item['month'],
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ),
              Text(
                '${item['deliveries']} ($percentage%)',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF64748B),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildMonthlySummaryItem(String title, String value) {
    return Column(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 12,
            color: Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1E293B),
          ),
        ),
      ],
    );
  }
}

// Pie Chart Widget
class PieChartWidget extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  final int total;

  const PieChartWidget({super.key, required this.data, required this.total});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(160, 160),
      painter: _PieChartPainter(data: data, total: total),
    );
  }
}

class _PieChartPainter extends CustomPainter {
  final List<Map<String, dynamic>> data;
  final int total;

  _PieChartPainter({required this.data, required this.total});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty || total == 0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 10;

    double startAngle = -pi / 2; // Start from top

    // Draw the pie chart
    for (final item in data) {
      final value = item['deliveries'] as int? ?? item['count'] as int;
      final sweepAngle = 2 * pi * value / total;
      
      final paint = Paint()
        ..color = item['color'] as Color
        ..style = PaintingStyle.fill;

      // Draw the arc
      final rect = Rect.fromCircle(center: center, radius: radius);
      canvas.drawArc(rect, startAngle, sweepAngle, true, paint);

      // Add a subtle shadow effect
      final shadowPaint = Paint()
        ..color = Colors.black.withOpacity(0.1)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
      
      canvas.drawArc(rect, startAngle, sweepAngle, true, shadowPaint);

      startAngle += sweepAngle;
    }

    // Draw center circle for donut effect
    final centerPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    
    canvas.drawCircle(center, radius * 0.6, centerPaint);

    // Draw total count in center
    final textStyle = TextStyle(
      color: const Color(0xFF1E293B),
      fontSize: radius * 0.3,
      fontWeight: FontWeight.w700,
    );
    
    final textSpan = TextSpan(
      text: total.toString(),
      style: textStyle,
    );
    
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: ui.TextDirection.ltr,
    );
    
    textPainter.layout();
    textPainter.paint(
      canvas,
      center - Offset(textPainter.width / 2, textPainter.height / 2),
    );

    // Draw "Total" label
    final labelStyle = TextStyle(
      color: const Color(0xFF64748B),
      fontSize: radius * 0.15,
    );
    
    final labelSpan = TextSpan(
      text: 'Total',
      style: labelStyle,
    );
    
    final labelPainter = TextPainter(
      text: labelSpan,
      textDirection: ui.TextDirection.ltr,
    );
    
    labelPainter.layout();
    labelPainter.paint(
      canvas,
      center - Offset(labelPainter.width / 2, -textPainter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}