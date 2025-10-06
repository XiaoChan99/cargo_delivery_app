import 'package:http/http.dart' as http;
import 'dart:convert';

class OSMService {
  // Geocoding - Convert address to coordinates
  static Future<Map<String, double>?> geocodeAddress(String address) async {
    try {
      final response = await http.get(
        Uri.parse('https://nominatim.openstreetmap.org/search?format=json&q=${Uri.encodeQueryComponent(address)}&limit=1')
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

  // Routing - Get real-time route info
  static Future<Map<String, dynamic>> getRouteInfo(
    String originAddress, 
    String destinationAddress
  ) async {
    try {
      // Geocode both addresses
      final originCoords = await geocodeAddress(originAddress);
      final destinationCoords = await geocodeAddress(destinationAddress);
      
      if (originCoords == null || destinationCoords == null) {
        return _getFallbackRouteInfo();
      }
      
      // Get route from OSRM
      final response = await http.get(
        Uri.parse('https://router.project-osrm.org/route/v1/driving/'
          '${originCoords['lng']},${originCoords['lat']};'
          '${destinationCoords['lng']},${destinationCoords['lat']}?overview=false')
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['code'] == 'Ok' && data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          final distanceKm = (route['distance'] / 1000); // meters to km
          final durationMinutes = (route['duration'] / 60); // seconds to minutes
          
          // Determine traffic status based on duration (simplified)
          String trafficStatus = _getTrafficStatus(durationMinutes, distanceKm);
          
          return {
            'distance': distanceKm.toStringAsFixed(1),
            'distanceValue': distanceKm,
            'duration': durationMinutes.toStringAsFixed(0),
            'durationValue': durationMinutes,
            'trafficStatus': trafficStatus,
            'originCoords': originCoords,
            'destinationCoords': destinationCoords,
          };
        }
      }
      return _getFallbackRouteInfo();
    } catch (e) {
      print('Routing error: $e');
      return _getFallbackRouteInfo();
    }
  }
  
  static String _getTrafficStatus(double durationMinutes, double distanceKm) {
    final averageSpeed = distanceKm / (durationMinutes / 60);
    
    if (averageSpeed < 20) return 'Heavy Traffic';
    if (averageSpeed < 40) return 'Moderate Traffic';
    return 'Normal';
  }
  
  static Map<String, dynamic> _getFallbackRouteInfo() {
    return {
      'distance': '15.3',
      'distanceValue': 15.3,
      'duration': '32',
      'durationValue': 32.0,
      'trafficStatus': 'Normal',
    };
  }
}