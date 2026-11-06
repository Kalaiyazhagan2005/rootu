import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class NominatimResult {
  final String displayName;
  final String shortName;
  final LatLng position;
  final String placeType;
  final double score;

  const NominatimResult({
    required this.displayName,
    required this.shortName,
    required this.position,
    this.placeType = 'place',
    this.score = 0.0,
  });
}

/// Pure algorithmic phonetic normalizer for Indic and South Indian transliteration patterns
class IndicQueryNormalizer {
  /// Normalize common English-Indic transliteration variations (e.g. "th" -> "t", "dh" -> "d")
  static String normalize(String query) {
    String q = query.trim().toLowerCase();

    // Algorithmic replacement of English transliteration variations:
    // e.g. "thiruvannamalai" -> "tiruvannamalai"
    if (q.startsWith('th')) {
      q = 't${q.substring(2)}';
    }
    q = q.replaceAll('dh', 'd');
    q = q.replaceAll('zh', 'l');
    q = q.replaceAll('oo', 'u');
    q = q.replaceAll('ee', 'i');

    return q;
  }
}

/// Production geocoding engine with Country-Locking, Proximity Biasing, and Administrative Hierarchy Ranking
class NominatimSearchService {
  static const String _userAgent = 'RootUApp/1.0 (contact@rootu.app)';
  static const Distance _distanceCalculator = Distance();

  static LatLng? _lastGeocodedPoint;
  static bool _isGeocoding = false;

  /// Administrative place weights to ensure major cities and towns beat small villages/temples
  static const Map<String, double> _placeWeights = {
    'city': 120.0,
    'town': 100.0,
    'administrative': 95.0,
    'municipality': 90.0,
    'suburb': 50.0,
    'village': 20.0,
    'hamlet': 10.0,
    'place_of_worship': 5.0,
    'temple': 5.0,
    'locality': 15.0,
  };

  /// Search places with Country-Locking (India only) and User Proximity Biasing
  static Future<List<NominatimResult>> search(
    String query, {
    LatLng? userLocation,
  }) async {
    final rawQuery = query.trim();
    if (rawQuery.isEmpty) return const [];

    final normalizedQuery = IndicQueryNormalizer.normalize(rawQuery);

    // Run parallel search for raw input and normalized input (e.g. "thiruvannamalai" & "tiruvannamalai")
    final List<Future<List<NominatimResult>>> searchTasks = [
      _fetchNominatimCandidates(rawQuery, userLocation: userLocation),
    ];

    if (normalizedQuery != rawQuery.toLowerCase()) {
      searchTasks.add(_fetchNominatimCandidates(normalizedQuery, userLocation: userLocation));
    }

    // Also query Photon for fast autocomplete with alt_name support
    searchTasks.add(_fetchPhotonCandidates(rawQuery, userLocation: userLocation));

    try {
      final resultsList = await Future.wait(searchTasks);
      final Map<String, NominatimResult> uniqueCandidates = {};

      for (final list in resultsList) {
        for (final item in list) {
          final key = '${item.position.latitude.toStringAsFixed(3)},${item.position.longitude.toStringAsFixed(3)}';
          if (!uniqueCandidates.containsKey(key) || (item.score > uniqueCandidates[key]!.score)) {
            uniqueCandidates[key] = item;
          }
        }
      }

      final List<NominatimResult> sorted = uniqueCandidates.values.toList();
      // Sort descending by multi-signal composite score
      sorted.sort((a, b) => b.score.compareTo(a.score));

      return sorted.take(6).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Query Nominatim with countrycodes=in and bounding box / viewbox bias
  static Future<List<NominatimResult>> _fetchNominatimCandidates(
    String q, {
    LatLng? userLocation,
  }) async {
    String viewboxParam = '';
    if (userLocation != null) {
      // Create a 3-degree (~330km) viewbox around user location to prioritize regional results
      final minLat = (userLocation.latitude - 2.5).clamp(8.0, 37.0);
      final maxLat = (userLocation.latitude + 2.5).clamp(8.0, 37.0);
      final minLon = (userLocation.longitude - 2.5).clamp(68.0, 97.0);
      final maxLon = (userLocation.longitude + 2.5).clamp(68.0, 97.0);
      viewboxParam = '&viewbox=$minLon,$maxLat,$maxLon,$minLat&bounded=0';
    }

    final Uri uri = Uri.parse(
      'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(q)}&countrycodes=in$viewboxParam&format=json&addressdetails=1&extratags=1&limit=8',
    );

    try {
      final response = await http.get(uri, headers: {
        'User-Agent': _userAgent,
      }).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final List raw = jsonDecode(response.body);
        return raw.map((item) {
          final double lat = double.parse(item['lat']);
          final double lon = double.parse(item['lon']);
          final String full = item['display_name'] ?? '';
          final String short = full.split(',').first.trim();
          final String type = (item['type'] as String?)?.toLowerCase() ?? 'place';
          final double importance = (item['importance'] as num?)?.toDouble() ?? 0.1;

          final score = _calculateScore(
            placeType: type,
            importance: importance,
            candidatePos: LatLng(lat, lon),
            userLocation: userLocation,
            shortName: short,
            searchQuery: q,
          );

          return NominatimResult(
            displayName: full,
            shortName: short,
            position: LatLng(lat, lon),
            placeType: type,
            score: score,
          );
        }).toList();
      }
    } catch (_) {}
    return const [];
  }

  /// Query Photon API for instant typeahead with proximity biasing
  static Future<List<NominatimResult>> _fetchPhotonCandidates(
    String q, {
    LatLng? userLocation,
  }) async {
    final String latLonParam = userLocation != null
        ? '&lat=${userLocation.latitude}&lon=${userLocation.longitude}'
        : '';

    final Uri uri = Uri.parse(
      'https://photon.komoot.io/api/?q=${Uri.encodeComponent(q)}$latLonParam&limit=6&bbox=68.1,6.7,97.4,35.5',
    );

    try {
      final response = await http.get(uri, headers: {
        'User-Agent': _userAgent,
      }).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        final List features = data['features'] as List? ?? [];

        final List<NominatimResult> photonResults = [];
        for (final feat in features) {
          final Map props = feat['properties'] ?? {};
          final List coords = feat['geometry']?['coordinates'] ?? [];
          if (coords.length < 2) continue;
          final double pLon = (coords[0] as num).toDouble();
          final double pLat = (coords[1] as num).toDouble();

          final String name = props['name'] ?? '';
          final String city = props['city'] ?? props['county'] ?? '';
          final String state = props['state'] ?? '';
          final String type = (props['type'] as String?)?.toLowerCase() ??
              (props['osm_value'] as String?)?.toLowerCase() ??
              'place';

          final List<String> addressParts = [
            if (name.isNotEmpty) name,
            if (city.isNotEmpty && city != name) city,
            if (state.isNotEmpty) state,
            'India',
          ];
          final String full = addressParts.join(', ');

          final score = _calculateScore(
            placeType: type,
            importance: 0.35,
            candidatePos: LatLng(pLat, pLon),
            userLocation: userLocation,
            shortName: name,
            searchQuery: q,
          );

          photonResults.add(NominatimResult(
            displayName: full,
            shortName: name.isNotEmpty ? name : full.split(',').first,
            position: LatLng(pLat, pLon),
            placeType: type,
            score: score,
          ));
        }
        return photonResults;
      }
    } catch (_) {}
    return const [];
  }

  /// Multi-signal ranking algorithm prioritizing Major Administrative Centers over small villages
  static double _calculateScore({
    required String placeType,
    required double importance,
    required LatLng candidatePos,
    required LatLng? userLocation,
    required String shortName,
    required String searchQuery,
  }) {
    // 1. Base weight by administrative hierarchy
    final double typeWeight = _placeWeights[placeType] ?? 15.0;

    // 2. OpenStreetMap / Wikidata prominence factor
    final double prominenceScore = (importance.clamp(0.0, 1.0)) * 100.0;

    // 3. Distance decay bonus centered on user GPS
    double distanceBonus = 0.0;
    if (userLocation != null) {
      final double distKm = _distanceCalculator.as(LengthUnit.Kilometer, userLocation, candidatePos);
      distanceBonus = 60.0 / (1.0 + (distKm / 120.0));
    }

    // 4. Exact prefix match bonus
    double matchBonus = 0.0;
    if (shortName.toLowerCase().startsWith(searchQuery.toLowerCase())) {
      matchBonus = 35.0;
    }

    return typeWeight + prominenceScore + distanceBonus + matchBonus;
  }

  /// Reverse geocode coordinates to human-readable area name (with 150m throttling)
  static Future<String?> reverseGeocode(LatLng point) async {
    if (_isGeocoding) return null;
    if (_lastGeocodedPoint != null) {
      final double dist = _distanceCalculator.as(LengthUnit.Meter, _lastGeocodedPoint!, point);
      if (dist < 150) return null;
    }

    _isGeocoding = true;
    _lastGeocodedPoint = point;

    try {
      final Uri uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?lat=${point.latitude}&lon=${point.longitude}&format=json',
      );
      final response = await http.get(uri, headers: {
        'User-Agent': _userAgent,
      }).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        final Map<String, dynamic>? address = data['address'];
        if (address != null) {
          final String village = address['village'] ??
              address['hamlet'] ??
              address['suburb'] ??
              address['town'] ??
              address['city'] ??
              address['road'] ??
              '';
          final String county = address['county'] ?? address['state_district'] ?? '';
          final String postcode = address['postcode'] ?? '';

          if (village.isNotEmpty && county.isNotEmpty) {
            return '$village, $county';
          } else if (county.isNotEmpty) {
            return '$county ($postcode)';
          }
        }
        return data['display_name']?.split(',').take(2).join(',') ?? '';
      }
    } catch (_) {
      // Non-critical network lookup
    } finally {
      _isGeocoding = false;
    }
    return null;
  }
}
