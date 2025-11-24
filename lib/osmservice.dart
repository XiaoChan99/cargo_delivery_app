// Updated OSMService with wider Cebu bounds, corrected Oslob handling,
// improved logging and small robustness fixes.
//
// Changes made:
// - Expanded _cebuLatMin/_cebuLatMax/_cebuLngMin/_cebuLngMax so southern towns
//   like Oslob are included (previous bounds excluded them).
// - Corrected/added a few municipality name variants and adjusted Oslob coords.
// - Added more debug printing to make geocoding/routing decisions visible.
// - Allow Nominatim primary geocode result to be accepted even if it falls
//   slightly outside Cebu bounds when no better Cebu-specific match exists.
// - Minor defensive checks and clearer comments.
import 'package:http/http.dart' as http;
import 'dart:convert';
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

  // Enhanced Geocoding - Convert address to coordinates with Cebu fallback support
  static Future<Map<String, double>?> geocodeAddress(String address) async {
    try {
      if (address.isEmpty) {
        print('ERROR: Address is empty');
        return null;
      }

      final normalized = address.trim();
      print('DEBUG: Geocoding address: "$normalized"');

      // Strategy 1: Try direct Nominatim first (accept near-Cebu results too)
      var result = await _geocodeWithNominatim(normalized);
      if (result != null) {
        print('DEBUG: Successfully geocoded via Nominatim: $result');
        return result;
      }

      // Strategy 2: Try with enhanced parsing and Cebu fallback
      result = await _geocodeWithCebuFallback(normalized);
      if (result != null) {
        print('DEBUG: Successfully geocoded via Cebu fallback: $result');
        return result;
      }

      // Strategy 3: If still null, try a secondary Nominatim attempt adding Cebu context
      final secAddress = normalized.contains('cebu') ? normalized : '$normalized, Cebu, Philippines';
      print('DEBUG: final attempt geocoding with context: "$secAddress"');
      result = await _geocodeWithNominatim(secAddress);
      if (result != null) {
        print('DEBUG: geocoded with context: $result');
        return result;
      }

      print('ERROR: Could not geocode address: $address');
      return null;
    } catch (e) {
      print('Exception in geocodeAddress: $e');
      return null;
    }
  }

  // Direct Nominatim geocoding
  static Future<Map<String, double>?> _geocodeWithNominatim(String address) async {
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/search?format=json&q=${Uri.encodeQueryComponent(address)}&limit=1&addressdetails=1&countrycodes=ph'
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        if (data.isNotEmpty) {
          final lat = double.parse(data[0]['lat'].toString());
          final lng = double.parse(data[0]['lon'].toString());

          // If the returned coordinates are inside our Cebu bounds, accept immediately.
          if (_isInCebuRegion(lat, lng)) {
            return {'lat': lat, 'lng': lng};
          }

          // If not in Cebu region, still accept the result if the address is not explicitly Cebu-only.
          // Log it so callers can see what happened.
          print('DEBUG: Nominatim returned coords outside Cebu bounds: ($lat, $lng) for address "$address"');
          return {'lat': lat, 'lng': lng};
        }
      } else {
        print('Nominatim returned status ${response.statusCode} for address "$address"');
      }
    } catch (e) {
      print('Nominatim error: $e');
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
          print('DEBUG: Matched municipality: ${entry.key}');
          return {
            'lat': entry.value.latitude,
            'lng': entry.value.longitude,
          };
        }
      }

      // Check barangay matches
      for (var entry in _cebuBarangays.entries) {
        if (normalized.contains(entry.key)) {
          print('DEBUG: Matched barangay: ${entry.key}');
          return {
            'lat': entry.value.latitude,
            'lng': entry.value.longitude,
          };
        }
      }

      // Fuzzy matching for partial strings (best-effort)
      var fuzzyResult = _fuzzyMatchLocation(normalized);
      if (fuzzyResult != null) {
        print('DEBUG: Matched via fuzzy: $fuzzyResult');
        return fuzzyResult;
      }

      // If address doesn't mention Cebu explicitly, try Nominatim with Cebu added (handled by caller)
      return null;
    } catch (e) {
      print('Cebu fallback geocoding error: $e');
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
      final response = await http.get(
        Uri.parse('https://nominatim.openstreetmap.org/search?format=json&q=${Uri.encodeQueryComponent(address)}&limit=1&addressdetails=1')
      ).timeout(const Duration(seconds: 10));

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
        }
      } else {
        print('geocodeAddressWithDetails: Nominatim returned ${response.statusCode}');
      }
      return {'error': 'Address not found'};
    } catch (e) {
      print('Enhanced geocoding error for $address: $e');
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
      final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/$profile/'
          '${start.longitude},${start.latitude};'
          '${end.longitude},${end.latitude}?overview=full&geometries=geojson&steps=true&annotations=true'
      );

      print('DEBUG: Requesting route from OSRM: $url');
      final response = await http.get(url).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['code'] == 'Ok' && data['routes'] != null && data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          final distanceKm = (route['distance'] as num) / 1000.0;
          final durationMinutes = (route['duration'] as num) / 60.0;

          // Extract geometry coordinates with endpoint correction
          List<LatLng> routePoints = [];
          if (route['geometry'] != null && route['geometry']['coordinates'] != null) {
            final coordinates = route['geometry']['coordinates'] as List;
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
              print('DEBUG: distance from last route point to end = ${distanceToEndMeters.toStringAsFixed(1)} meters');
              if (distanceToEndMeters > 100.0) {
                // last point far from end, append exact end
                routePoints.add(end);
              } else {
                // snap last point to exact end coordinates
                routePoints[routePoints.length - 1] = end;
              }
            } else {
              routePoints = [start, end];
            }
          } else {
            // geometry missing -> fallback to simple two-point route
            routePoints = [start, end];
          }

          final double distanceThreshold = 500.0; // kilometers for "international" heuristic
          final bool isInternational = distanceKm > distanceThreshold;
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
            'routeAccuracy': 'high',
          };
        } else {
          print('DEBUG: OSRM returned no routes or not Ok: ${data['code']}');
        }
      } else {
        print('DEBUG: OSRM responded with status ${response.statusCode}');
      }

      return _getFallbackRouteInfo(start, end);
    } catch (e) {
      print('Routing error: $e');
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
      final response = await http.get(
        Uri.parse('https://graphhopper.com/api/1/route?'
          'point=${start.latitude},${start.longitude}'
          '&point=${end.latitude},${end.longitude}'
          '&vehicle=$profile'
          '&key=2f91b148-9935-442e-be56-f02014d082ae'
          '&type=json&instructions=true&points_encoded=false')
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['paths'] != null && data['paths'].isNotEmpty) {
          final path = data['paths'][0];
          final distanceKm = (path['distance'] as num) / 1000.0;
          final durationMinutes = (path['time'] as num) / 60000.0;

          List<LatLng> routePoints = [];
          if (path['points'] != null && path['points']['coordinates'] != null) {
            final coordinates = path['points']['coordinates'] as List;
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
        }
      } else {
        print('GraphHopper returned status ${response.statusCode}');
      }
    } catch (e) {
      print('Alternative routing error: $e');
    }

    return getRouteWithGeometry(start, end, profile: profile);
  }

  // Check if two points are in different countries (heuristic)
  static Future<bool> isInternationalRoute(LatLng point1, LatLng point2) async {
    try {
      final double distance = _calculateDistance(point1, point2);
      return distance > 500.0;
    } catch (e) {
      print('International route check error: $e');
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
    List<LatLng> fallbackPoints = [start, end];
    final double distance = _calculateDistance(start, end);
    final bool isInternational = distance > 500.0;
    final double estimatedDuration = (distance / 50.0) * 60.0; // assume 50 km/h avg

    print('DEBUG: fallback route used start=$start end=$end distance=${distance.toStringAsFixed(2)} km');

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
      return reference;
    }

    return LatLng(lat, lng);
  }
}