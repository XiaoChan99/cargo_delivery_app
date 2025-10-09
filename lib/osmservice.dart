import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:latlong2/latlong.dart';

class OSMService {
  // Use the Distance class from latlong2 package for accurate calculations
  static final Distance _distanceCalculator = Distance();
  
  // Geocoding - Convert address to coordinates with better international support
  static Future<Map<String, double>?> geocodeAddress(String address) async {
    try {
      final response = await http.get(
        Uri.parse('https://nominatim.openstreetmap.org/search?format=json&q=${Uri.encodeQueryComponent(address)}&limit=1&addressdetails=1')
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is List && data.isNotEmpty) {
          return {
            'lat': double.parse(data[0]['lat']),
            'lng': double.parse(data[0]['lon']),
          };
        }
      }
      return null;
    } catch (e) {
      print('Geocoding error for $address: $e');
      return null;
    }
  }

  // Enhanced geocoding with country detection
  static Future<Map<String, dynamic>> geocodeAddressWithDetails(String address) async {
    try {
      final response = await http.get(
        Uri.parse('https://nominatim.openstreetmap.org/search?format=json&q=${Uri.encodeQueryComponent(address)}&limit=1&addressdetails=1')
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is List && data.isNotEmpty) {
          final result = data[0];
          final addressDetails = result['address'] as Map<String, dynamic>?;
          final country = addressDetails?['country'] ?? addressDetails?['country_code']?.toString().toUpperCase();
          
          return {
            'lat': double.parse(result['lat']),
            'lng': double.parse(result['lon']),
            'country': country,
            'display_name': result['display_name'],
          };
        }
      }
      return {'error': 'Address not found'};
    } catch (e) {
      print('Enhanced geocoding error for $address: $e');
      return {'error': e.toString()};
    }
  }

  // Routing - Get real-time route info with geometry (international support)
  static Future<Map<String, dynamic>> getRouteWithGeometry(
    LatLng start,
    LatLng end, {
    String profile = 'driving', // driving, walking, cycling
  }) async {
    try {
      // Get route from OSRM with full geometry
      final response = await http.get(
        Uri.parse('https://router.project-osrm.org/route/v1/$profile/'
          '${start.longitude},${start.latitude};'
          '${end.longitude},${end.latitude}?overview=full&geometries=geojson&steps=true')
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['code'] == 'Ok' && data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          final distanceKm = (route['distance'] / 1000); // meters to km
          final durationMinutes = (route['duration'] / 60); // seconds to minutes
          
          // Extract geometry coordinates
          List<LatLng> routePoints = [];
          if (route['geometry'] != null && route['geometry']['coordinates'] != null) {
            final coordinates = route['geometry']['coordinates'] as List;
            for (var coord in coordinates) {
              if (coord is List && coord.length >= 2) {
                routePoints.add(LatLng(coord[1].toDouble(), coord[0].toDouble()));
              }
            }
          }
          
          // Determine if it's an international route
          final double distanceThreshold = 500.0; // km - consider international if > 500km
          final bool isInternational = distanceKm > distanceThreshold;
          
          // Determine traffic status based on duration (simplified)
          String trafficStatus = _getTrafficStatus(durationMinutes, distanceKm);
          
          return {
            'distance': distanceKm.toStringAsFixed(1),
            'distanceValue': distanceKm,
            'duration': durationMinutes.toStringAsFixed(0),
            'durationValue': durationMinutes,
            'trafficStatus': trafficStatus,
            'routePoints': routePoints,
            'geometry': route['geometry'],
            'isInternational': isInternational,
            'routeFound': true,
          };
        }
      }
      return _getFallbackRouteInfo(start, end);
    } catch (e) {
      print('Routing error: $e');
      return _getFallbackRouteInfo(start, end);
    }
  }

  // Check if two points are in different countries (simplified)
  static Future<bool> isInternationalRoute(LatLng point1, LatLng point2) async {
    try {
      final double distance = _calculateDistance(point1, point2);
      return distance > 500.0; // Consider international if distance > 500km
    } catch (e) {
      print('International route check error: $e');
      return false;
    }
  }

  // Calculate distance between two points in kilometers using latlong2
  static double _calculateDistance(LatLng point1, LatLng point2) {
    // Returns distance in meters, convert to kilometers
    return _distanceCalculator(point1, point2) / 1000;
  }
  
  static String _getTrafficStatus(double durationMinutes, double distanceKm) {
    if (distanceKm == 0) return 'Unknown';
    
    final averageSpeed = distanceKm / (durationMinutes / 60);
    
    if (averageSpeed < 20) return 'Heavy Traffic';
    if (averageSpeed < 40) return 'Moderate Traffic';
    return 'Normal';
  }
  
  static Map<String, dynamic> _getFallbackRouteInfo(LatLng start, LatLng end) {
    // Generate a straight line as fallback
    List<LatLng> fallbackPoints = [start, end];
    final double distance = _calculateDistance(start, end);
    final bool isInternational = distance > 500.0;
    
    // Estimate duration based on distance (assuming average speed of 50 km/h)
    final double estimatedDuration = (distance / 50) * 60;
    
    return {
      'distance': distance.toStringAsFixed(1),
      'distanceValue': distance,
      'duration': estimatedDuration.toStringAsFixed(0),
      'durationValue': estimatedDuration,
      'trafficStatus': 'Unknown',
      'routePoints': fallbackPoints,
      'isInternational': isInternational,
      'routeFound': false,
    };
  }
}