// Updated OSMService with mobile compatibility fixes, wider Cebu bounds,
// corrected Oslob handling, improved logging and robust HTTP requests.
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:latlong2/latlong.dart';

class OSMService {
  // Use the Distance class from latlong2 package for accurate calculations
  static final Distance _distanceCalculator = Distance();

  // Wider Cebu Province bounds for validation (include southern towns like Oslob)
  // Latitude range and longitude range chosen to comfortably include Cebu province
  // and nearby municipalities used by the app.
  static const double _cebuLatMin = 8.5;
  static const double _cebuLatMax = 11.0;
  static const double _cebuLngMin = 122.8;
  static const double _cebuLngMax = 125.2;

  // Known Cebu municipalities with coordinates (keyed lower-case, normalized)
  static const Map<String, LatLng> _cebuMunicipalities = {
    'cebu city': LatLng(10.3157, 123.8854),
    'mandaue': LatLng(10.3667, 123.9667),
    'mandaue city': LatLng(10.3667, 123.9667),
    'lapu-lapu': LatLng(10.3156, 124.0167),
    'lapu lapu': LatLng(10.3156, 124.0167),
    'lapu-lapu city': LatLng(10.3156, 124.0167),
    'talisay': LatLng(10.2833, 123.9667),
    'talisay city': LatLng(10.2833, 123.9667),
    'badian': LatLng(10.1333, 123.7667),
    'samboan': LatLng(9.9167, 123.7833),
    'alcoy': LatLng(9.95, 123.75),
    'moalboal': LatLng(9.95, 123.7667),
    'barili': LatLng(10.15, 123.7167),
    'carcar': LatLng(10.0333, 123.9667),
    'dumanjug': LatLng(10.05, 123.8833),
    // Oslob coordinates corrected/placed in southern Cebu
    'oslob': LatLng(9.3333, 123.3000),
    'cordova': LatLng(10.2333, 123.9667),
    'liloan': LatLng(10.2167, 124.0333),
    'consolacion': LatLng(10.4, 123.9333),
    'compostela': LatLng(10.3, 123.75),
    'danao': LatLng(10.4, 123.9333),
    'danao city': LatLng(10.4, 123.9333),
  };

  // Known Cebu barangays with coordinates
  static const Map<String, LatLng> _cebuBarangays = {
    'apas': LatLng(10.3167, 123.9),
    'lahug': LatLng(10.3167, 123.85),
    'banilad': LatLng(10.3333, 123.85),
    'busay': LatLng(10.35, 123.8333),
    'talamban': LatLng(10.3667, 123.85),
    'cogon': LatLng(10.3, 123.9167),
    'pung-ol': LatLng(10.3, 123.8667),
    'pung ol': LatLng(10.3, 123.8667),
    'mabolo': LatLng(10.3167, 123.8833),
    'guadalupe': LatLng(10.3, 123.9),
    'kalubihan': LatLng(10.3333, 123.8667),
    'pit-os': LatLng(10.3333, 123.9),
    'pit os': LatLng(10.3333, 123.9),
    'camputhaw': LatLng(10.35, 123.8833),
    'luz': LatLng(10.2833, 123.8833),
    'carreta': LatLng(10.3333, 123.9167),
    'basak': LatLng(10.3833, 123.9),
    'pasil': LatLng(10.3, 123.8833),
    'quiot': LatLng(10.3833, 123.85),
    'kinasang-an': LatLng(10.2667, 123.8667),
    'kinasang an': LatLng(10.2667, 123.8667),
    'casuntingan': LatLng(10.3, 123.8833),
    'kamagayan': LatLng(10.3333, 123.8833),
    'subangdaku': LatLng(10.3667, 123.8667),
    'deltang': LatLng(10.3167, 123.8667),
    'pilo': LatLng(10.3833, 123.8667),
    'paknaan': LatLng(10.3, 123.9333),
    'bacayan': LatLng(10.3667, 123.8833),
    'sirao': LatLng(10.3833, 123.8333),
    'tisa': LatLng(10.2667, 123.9167),
    'bulacao': LatLng(10.3333, 123.9333),
  };

  // Enhanced HTTP request with proper headers for mobile
  static Future<http.Response> _makeHttpRequest(Uri uri, {Duration? timeout}) async {
    final headers = {
      'User-Agent': 'CargoDeliveryApp/1.0 (com.example.cargo_delivery_app)',
      'Accept': 'application/json',
      'Accept-Language': 'en-US,en;q=0.9',
    };
    
    developer.log('HTTP Request: $uri', name: 'OSMService');
    
    try {
      final response = await http.get(uri, headers: headers).timeout(
        timeout ?? const Duration(seconds: 25), // Increased timeout for mobile
      );
      
      developer.log('HTTP Response: ${response.statusCode}', name: 'OSMService');
      return response;
    } catch (e) {
      developer.log('HTTP Request Error: $e', error: e, name: 'OSMService');
      rethrow;
    }
  }

  // Enhanced Geocoding - Convert address to coordinates with Cebu fallback support
  static Future<Map<String, double>?> geocodeAddress(String address) async {
    try {
      if (address.isEmpty) {
        developer.log('ERROR: Address is empty', name: 'OSMService');
        return null;
      }

      final normalized = address.trim();
      developer.log('Geocoding address: "$normalized"', name: 'OSMService');

      // Strategy 1: Try direct Nominatim first (accept near-Cebu results too)
      var result = await _geocodeWithNominatim(normalized);
      if (result != null) {
        developer.log('Successfully geocoded via Nominatim: $result', name: 'OSMService');
        return result;
      }

      // Strategy 2: Try with enhanced parsing and Cebu fallback
      result = await _geocodeWithCebuFallback(normalized);
      if (result != null) {
        developer.log('Successfully geocoded via Cebu fallback: $result', name: 'OSMService');
        return result;
      }

      // Strategy 3: If still null, try a secondary Nominatim attempt adding Cebu context
      final secAddress = normalized.contains('cebu') ? normalized : '$normalized, Cebu, Philippines';
      developer.log('Final attempt geocoding with context: "$secAddress"', name: 'OSMService');
      result = await _geocodeWithNominatim(secAddress);
      if (result != null) {
        developer.log('Geocoded with context: $result', name: 'OSMService');
        return result;
      }

      developer.log('ERROR: Could not geocode address: $address', name: 'OSMService');
      return null;
    } catch (e) {
      developer.log('Exception in geocodeAddress: $e', error: e, name: 'OSMService');
      return null;
    }
  }

  // Direct Nominatim geocoding
  static Future<Map<String, double>?> _geocodeWithNominatim(String address) async {
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/search?format=json&q=${Uri.encodeQueryComponent(address)}&limit=1&addressdetails=1&countrycodes=ph'
      );
      
      final response = await _makeHttpRequest(uri);

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        developer.log('Nominatim found ${data.length} results for "$address"', name: 'OSMService');
        
        if (data.isNotEmpty) {
          final lat = double.parse(data[0]['lat'].toString());
          final lng = double.parse(data[0]['lon'].toString());

          // If the returned coordinates are inside our Cebu bounds, accept immediately.
          if (_isInCebuRegion(lat, lng)) {
            return {'lat': lat, 'lng': lng};
          }

          // If not in Cebu region, still accept the result if the address is not explicitly Cebu-only.
          developer.log('Nominatim returned coords outside Cebu bounds: ($lat, $lng) for address "$address"', name: 'OSMService');
          return {'lat': lat, 'lng': lng};
        } else {
          developer.log('No Nominatim results for address: "$address"', name: 'OSMService');
        }
      } else {
        developer.log('Nominatim returned status ${response.statusCode} for address "$address"', name: 'OSMService');
      }
    } catch (e) {
      developer.log('Nominatim error: $e', error: e, name: 'OSMService');
    }
    return null;
  }

  // Cebu-specific fallback geocoding
  static Future<Map<String, double>?> _geocodeWithCebuFallback(String address) async {
    try {
      final lowerAddress = address.toLowerCase().trim();

      // Normalize hyphens and multiple spaces for matching keys
      final normalized = lowerAddress.replaceAll('-', ' ').replaceAll(RegExp(r'\s+'), ' ');

      // Check exact municipality matches
      for (var entry in _cebuMunicipalities.entries) {
        if (normalized.contains(entry.key)) {
          developer.log('Matched municipality: ${entry.key}', name: 'OSMService');
          return {
            'lat': entry.value.latitude,
            'lng': entry.value.longitude,
          };
        }
      }

      // Check barangay matches
      for (var entry in _cebuBarangays.entries) {
        if (normalized.contains(entry.key)) {
          developer.log('Matched barangay: ${entry.key}', name: 'OSMService');
          return {
            'lat': entry.value.latitude,
            'lng': entry.value.longitude,
          };
        }
      }

      // Fuzzy matching for partial strings (best-effort)
      var fuzzyResult = _fuzzyMatchLocation(normalized);
      if (fuzzyResult != null) {
        developer.log('Matched via fuzzy: $fuzzyResult', name: 'OSMService');
        return fuzzyResult;
      }

      // If address doesn't mention Cebu explicitly, try Nominatim with Cebu added (handled by caller)
      return null;
    } catch (e) {
      developer.log('Cebu fallback geocoding error: $e', error: e, name: 'OSMService');
      return null;
    }
  }

  // Fuzzy matching for location names
  static Map<String, double>? _fuzzyMatchLocation(String input) {
    final allLocations = {..._cebuMunicipalities, ..._cebuBarangays};

    // Extract key terms
    final terms = input.split(RegExp(r'[,\s]+'))
        .where((term) => term.isNotEmpty && term.length > 2)
        .toList();

    String? bestMatch;
    int maxMatchCount = 0;

    for (var locationName in allLocations.keys) {
      int matchCount = 0;
      for (var term in terms) {
        if (locationName.contains(term) || term.contains(locationName)) {
          matchCount++;
        }
      }

      if (matchCount > maxMatchCount) {
        maxMatchCount = matchCount;
        bestMatch = locationName;
      }
    }

    if (bestMatch != null && maxMatchCount > 0) {
      final location = allLocations[bestMatch]!;
      return {
        'lat': location.latitude,
        'lng': location.longitude,
      };
    }

    return null;
  }

  // Validate if coordinates are within Cebu region
  static bool _isInCebuRegion(double lat, double lng) {
    return lat >= _cebuLatMin &&
        lat <= _cebuLatMax &&
        lng >= _cebuLngMin &&
        lng <= _cebuLngMax;
  }

  // Enhanced geocoding with country detection
  static Future<Map<String, dynamic>> geocodeAddressWithDetails(String address) async {
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/search?format=json&q=${Uri.encodeQueryComponent(address)}&limit=1&addressdetails=1'
      );
      
      final response = await _makeHttpRequest(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is List && data.isNotEmpty) {
          final result = data[0];
          final addressDetails = result['address'] as Map<String, dynamic>?;
          final country = addressDetails?['country'] ?? addressDetails?['country_code']?.toString().toUpperCase();

          return {
            'lat': double.parse(result['lat'].toString()),
            'lng': double.parse(result['lon'].toString()),
            'country': country,
            'display_name': result['display_name'],
          };
        } else {
          developer.log('No results in geocodeAddressWithDetails for: $address', name: 'OSMService');
        }
      } else {
        developer.log('geocodeAddressWithDetails: Nominatim returned ${response.statusCode}', name: 'OSMService');
      }
      return {'error': 'Address not found'};
    } catch (e) {
      developer.log('Enhanced geocoding error for $address: $e', error: e, name: 'OSMService');
      return {'error': e.toString()};
    }
  }

  // Enhanced Routing - Get more accurate route with better waypoint handling
  static Future<Map<String, dynamic>> getRouteWithGeometry(
    LatLng start,
    LatLng end, {
    String profile = 'driving',
  }) async {
    try {
      developer.log('Getting route from $start to $end', name: 'OSMService');
      
      final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/$profile/'
          '${start.longitude},${start.latitude};'
          '${end.longitude},${end.latitude}?overview=full&geometries=geojson&steps=true&annotations=true'
      );

      final response = await _makeHttpRequest(url);

      developer.log('OSRM response status: ${response.statusCode}', name: 'OSMService');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        developer.log('OSRM data received: ${data['code']}', name: 'OSMService');
        
        if (data['code'] == 'Ok' && data['routes'] != null && data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          final distanceKm = (route['distance'] as num) / 1000.0;
          final durationMinutes = (route['duration'] as num) / 60.0;

          developer.log('Route found: ${distanceKm.toStringAsFixed(1)} km, ${durationMinutes.toStringAsFixed(0)} min', name: 'OSMService');
          
          // Extract geometry coordinates with endpoint correction
          List<LatLng> routePoints = [];
          if (route['geometry'] != null && route['geometry']['coordinates'] != null) {
            final coordinates = route['geometry']['coordinates'] as List;
            developer.log('Route has ${coordinates.length} coordinate points', name: 'OSMService');
            
            for (var coord in coordinates) {
              if (coord is List && coord.length >= 2) {
                // OSRM returns [lng, lat]
                final double lng = (coord[0] as num).toDouble();
                final double lat = (coord[1] as num).toDouble();
                routePoints.add(LatLng(lat, lng));
              }
            }

            // Ensure the route ends exactly at the destination (or append the destination)
            if (routePoints.isNotEmpty) {
              final lastPoint = routePoints.last;
              final distanceToEndMeters = _distanceCalculator(lastPoint, end); // meters
              developer.log('Distance from last route point to end = ${distanceToEndMeters.toStringAsFixed(1)} meters', name: 'OSMService');
              
              if (distanceToEndMeters > 100.0) {
                // last point far from end, append exact end
                routePoints.add(end);
                developer.log('Appended destination point to route', name: 'OSMService');
              } else {
                // snap last point to exact end coordinates
                routePoints[routePoints.length - 1] = end;
                developer.log('Snapped last point to destination', name: 'OSMService');
              }
            } else {
              routePoints = [start, end];
              developer.log('No geometry points, using fallback start-end route', name: 'OSMService');
            }
          } else {
            // geometry missing -> fallback to simple two-point route
            routePoints = [start, end];
            developer.log('Missing geometry, using fallback start-end route', name: 'OSMService');
          }

          final double distanceThreshold = 500.0; // kilometers for "international" heuristic
          final bool isInternational = distanceKm > distanceThreshold;
          String trafficStatus = _getTrafficStatus(durationMinutes, distanceKm);

          developer.log('Route processing complete. Points: ${routePoints.length}, International: $isInternational', name: 'OSMService');

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
            'routeAccuracy': 'high',
          };
        } else {
          developer.log('DEBUG: OSRM returned no routes or not Ok: ${data['code']}', name: 'OSMService');
        }
      } else {
        developer.log('DEBUG: OSRM responded with status ${response.statusCode}', name: 'OSMService');
      }

      return _getFallbackRouteInfo(start, end);
    } catch (e) {
      developer.log('Routing error: $e', error: e, name: 'OSMService');
      return _getFallbackRouteInfo(start, end);
    }
  }

  // Alternative routing service for better accuracy in some regions (GraphHopper)
  static Future<Map<String, dynamic>> getAlternativeRoute(
    LatLng start,
    LatLng end, {
    String profile = 'driving',
  }) async {
    try {
      developer.log('Trying alternative route via GraphHopper', name: 'OSMService');
      
      final uri = Uri.parse('https://graphhopper.com/api/1/route?'
        'point=${start.latitude},${start.longitude}'
        '&point=${end.latitude},${end.longitude}'
        '&vehicle=$profile'
        '&key=2f91b148-9935-442e-be56-f02014d082ae'
        '&type=json&instructions=true&points_encoded=false');
      
      final response = await _makeHttpRequest(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['paths'] != null && data['paths'].isNotEmpty) {
          final path = data['paths'][0];
          final distanceKm = (path['distance'] as num) / 1000.0;
          final durationMinutes = (path['time'] as num) / 60000.0;

          developer.log('GraphHopper route found: ${distanceKm.toStringAsFixed(1)} km', name: 'OSMService');

          List<LatLng> routePoints = [];
          if (path['points'] != null && path['points']['coordinates'] != null) {
            final coordinates = path['points']['coordinates'] as List;
            developer.log('GraphHopper route has ${coordinates.length} points', name: 'OSMService');
            
            for (var coord in coordinates) {
              if (coord is List && coord.length >= 2) {
                // GraphHopper points usually [lng, lat] or [lat, lng] depending on output;
                // We assume [lng, lat] similar to GeoJSON style and convert.
                final double lng = (coord[0] as num).toDouble();
                final double lat = (coord[1] as num).toDouble();
                routePoints.add(LatLng(lat, lng));
              }
            }

            if (routePoints.isNotEmpty) {
              routePoints[routePoints.length - 1] = end;
            }
          }

          return {
            'distance': distanceKm.toStringAsFixed(1),
            'distanceValue': distanceKm,
            'duration': durationMinutes.toStringAsFixed(0),
            'durationValue': durationMinutes,
            'trafficStatus': _getTrafficStatus(durationMinutes, distanceKm),
            'routePoints': routePoints.isNotEmpty ? routePoints : [start, end],
            'isInternational': distanceKm > 500.0,
            'routeFound': true,
            'routeAccuracy': 'high',
          };
        } else {
          developer.log('GraphHopper returned no paths', name: 'OSMService');
        }
      } else {
        developer.log('GraphHopper returned status ${response.statusCode}', name: 'OSMService');
      }
    } catch (e) {
      developer.log('Alternative routing error: $e', error: e, name: 'OSMService');
    }

    developer.log('Falling back to OSRM for route', name: 'OSMService');
    return getRouteWithGeometry(start, end, profile: profile);
  }

  // Check if two points are in different countries (heuristic)
  static Future<bool> isInternationalRoute(LatLng point1, LatLng point2) async {
    try {
      final double distance = _calculateDistance(point1, point2);
      final isInternational = distance > 500.0;
      developer.log('International route check: $distance km -> $isInternational', name: 'OSMService');
      return isInternational;
    } catch (e) {
      developer.log('International route check error: $e', error: e, name: 'OSMService');
      return false;
    }
  }

  // Calculate distance between two points in kilometers using latlong2
  static double _calculateDistance(LatLng point1, LatLng point2) {
    return _distanceCalculator(point1, point2) / 1000.0;
  }

  static String _getTrafficStatus(double durationMinutes, double distanceKm) {
    if (distanceKm == 0) return 'Unknown';

    final averageSpeed = distanceKm / (durationMinutes / 60.0);

    if (averageSpeed.isNaN) return 'Unknown';
    if (averageSpeed < 20) return 'Heavy Traffic';
    if (averageSpeed < 40) return 'Moderate Traffic';
    return 'Normal';
  }

  static Map<String, dynamic> _getFallbackRouteInfo(LatLng start, LatLng end) {
    developer.log('Using fallback route calculation', name: 'OSMService');
    
    List<LatLng> fallbackPoints = [start, end];
    final double distance = _calculateDistance(start, end);
    final bool isInternational = distance > 500.0;
    final double estimatedDuration = (distance / 50.0) * 60.0; // assume 50 km/h avg

    developer.log('Fallback route: start=$start end=$end distance=${distance.toStringAsFixed(2)} km', name: 'OSMService');

    return {
      'distance': distance.toStringAsFixed(1),
      'distanceValue': distance,
      'duration': estimatedDuration.toStringAsFixed(0),
      'durationValue': estimatedDuration,
      'trafficStatus': 'Unknown',
      'routePoints': fallbackPoints,
      'isInternational': isInternational,
      'routeFound': false,
      'routeAccuracy': 'low',
    };
  }

  // Enhanced coordinate validation and correction
  static LatLng validateAndCorrectCoordinates(LatLng point, LatLng reference) {
    double lat = point.latitude.clamp(-90.0, 90.0);
    double lng = point.longitude.clamp(-180.0, 180.0);

    if ((lat - 0.0).abs() < 0.000001 && (lng - 0.0).abs() < 0.000001) {
      // suspicious zero coordinates -> return reference
      developer.log('Suspicious zero coordinates detected, using reference point', name: 'OSMService');
      return reference;
    }

    return LatLng(lat, lng);
  }

  // Test connectivity to OSM services
  static Future<bool> testConnectivity() async {
    try {
      developer.log('Testing OSM service connectivity', name: 'OSMService');
      
      // Test Nominatim
      final nominatimUri = Uri.parse('https://nominatim.openstreetmap.org/search?format=json&q=Cebu&limit=1');
      final nominatimResponse = await _makeHttpRequest(nominatimUri, timeout: Duration(seconds: 10));
      
      // Test OSRM
      final osrmUri = Uri.parse('https://router.project-osrm.org/route/v1/driving/123.8854,10.3157;123.8854,10.3157?overview=false');
      final osrmResponse = await _makeHttpRequest(osrmUri, timeout: Duration(seconds: 10));
      
      final isConnected = nominatimResponse.statusCode == 200 || osrmResponse.statusCode == 200;
      developer.log('OSM Connectivity test: $isConnected', name: 'OSMService');
      
      return isConnected;
    } catch (e) {
      developer.log('Connectivity test failed: $e', error: e, name: 'OSMService');
      return false;
    }
  }
}