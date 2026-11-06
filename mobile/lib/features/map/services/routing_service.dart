import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../models/route_model.dart';

/// Production routing service calculating multi-stop road polylines and turn maneuvers via OSRM
class RoutingService {
  static const String _userAgent = 'RootUApp/1.0 (contact@rootu.app)';

  /// Calculate single direct route from start to destination
  static Future<RouteDetails?> calculateRoute({
    required LatLng start,
    required LatLng destination,
    required String destinationName,
  }) async {
    return calculateMultiStopRoute(waypoints: [
      RouteWaypoint(
        id: 'origin',
        name: 'Your Location',
        location: start,
        type: WaypointType.origin,
      ),
      RouteWaypoint(
        id: 'destination',
        name: destinationName,
        location: destination,
        type: WaypointType.destination,
      ),
    ]);
  }

  /// Calculate multi-stop road route connecting origin, intermediate stops, and final destination
  static Future<RouteDetails?> calculateMultiStopRoute({
    required List<RouteWaypoint> waypoints,
  }) async {
    if (waypoints.length < 2) return null;

    // 1. Snap all waypoints to the nearest drivable road edges in parallel
    final List<LatLng> snappedPoints = await Future.wait(
      waypoints.map((w) => _snapToNearestRoad(w.location)),
    );

    // 2. Build multi-coordinate OSRM path: lon1,lat1;lon2,lat2;lon3,lat3;...
    final String coordinatesString = snappedPoints
        .map((p) => '${p.longitude.toStringAsFixed(6)},${p.latitude.toStringAsFixed(6)}')
        .join(';');

    final Uri uri = Uri.parse(
      'https://router.project-osrm.org/route/v1/driving/$coordinatesString?overview=full&geometries=geojson&steps=true',
    );

    try {
      final response = await http.get(uri, headers: {
        'User-Agent': _userAgent,
      }).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        final String code = data['code'] ?? '';
        if (code != 'Ok') return null;

        final List routes = data['routes'] as List;
        if (routes.isEmpty) return null;

        final Map<String, dynamic> primaryRoute = routes.first;
        final double totalDistance = (primaryRoute['distance'] as num).toDouble();
        final double totalDuration = (primaryRoute['duration'] as num).toDouble();

        // Parse continuous road coordinates across all legs
        final Map<String, dynamic> geometry = primaryRoute['geometry'];
        final List coordinates = geometry['coordinates'] as List;
        final List<LatLng> polylinePoints = coordinates.map((c) {
          final double lon = (c[0] as num).toDouble();
          final double lat = (c[1] as num).toDouble();
          return LatLng(lat, lon);
        }).toList();

        // Parse turn-by-turn navigation steps across all itinerary legs
        final List<RouteStep> steps = [];
        final List legs = primaryRoute['legs'] as List? ?? [];
        final destination = waypoints.last;

        for (int legIndex = 0; legIndex < legs.length; legIndex++) {
          final leg = legs[legIndex];
          final List rawSteps = leg['steps'] as List? ?? [];
          final currentLegTarget = (legIndex + 1 < waypoints.length)
              ? waypoints[legIndex + 1]
              : destination;

          for (final raw in rawSteps) {
            final double stepDist = (raw['distance'] as num?)?.toDouble() ?? 0.0;
            final double stepDur = (raw['duration'] as num?)?.toDouble() ?? 0.0;
            final String name = raw['name'] as String? ?? '';
            final Map<String, dynamic>? maneuver = raw['maneuver'];

            final String type = maneuver?['type'] as String? ?? 'turn';
            final String modifier = maneuver?['modifier'] as String? ?? 'straight';
            final List? location = maneuver?['location'] as List?;

            LatLng stepLocation = currentLegTarget.location;
            if (location != null && location.length >= 2) {
              stepLocation = LatLng(
                (location[1] as num).toDouble(),
                (location[0] as num).toDouble(),
              );
            }

            final String instruction = _generateInstruction(
              type: type,
              modifier: modifier,
              roadName: name,
              isIntermediateStop: type == 'arrive' && legIndex < legs.length - 1,
              stopName: currentLegTarget.name,
            );

            steps.add(RouteStep(
              instruction: instruction,
              distanceMeters: stepDist,
              durationSeconds: stepDur,
              maneuverType: type,
              maneuverModifier: modifier,
              location: stepLocation,
            ));
          }
        }

        return RouteDetails(
          polylinePoints: polylinePoints,
          totalDistanceMeters: totalDistance,
          totalDurationSeconds: totalDuration,
          steps: steps,
          destination: destination.location,
          destinationName: destination.name,
          waypoints: waypoints,
        );
      }
    } catch (_) {}
    return null;
  }

  /// Snaps a coordinate off-road to the nearest motorized highway/street
  static Future<LatLng> _snapToNearestRoad(LatLng point) async {
    final lon = point.longitude.toStringAsFixed(6);
    final lat = point.latitude.toStringAsFixed(6);
    final Uri uri = Uri.parse(
      'https://router.project-osrm.org/nearest/v1/driving/$lon,$lat?number=1',
    );

    try {
      final response = await http.get(uri, headers: {
        'User-Agent': _userAgent,
      }).timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        final List waypoints = data['waypoints'] as List? ?? [];
        if (waypoints.isNotEmpty) {
          final List location = waypoints.first['location'] as List? ?? [];
          if (location.length >= 2) {
            final double sLon = (location[0] as num).toDouble();
            final double sLat = (location[1] as num).toDouble();
            return LatLng(sLat, sLon);
          }
        }
      }
    } catch (_) {}
    return point;
  }

  static String _generateInstruction({
    required String type,
    required String modifier,
    required String roadName,
    bool isIntermediateStop = false,
    String stopName = '',
  }) {
    if (isIntermediateStop) {
      return 'Arrive at stop: $stopName';
    }

    final cleanRoad = roadName.trim().isNotEmpty ? 'onto $roadName' : '';
    switch (type) {
      case 'depart':
        return 'Head $modifier $cleanRoad'.trim();
      case 'arrive':
        return 'Arrive at destination';
      case 'roundabout':
      case 'rotary':
        return 'Enter roundabout and take exit $cleanRoad'.trim();
      case 'fork':
        return 'Take the $modifier fork $cleanRoad'.trim();
      case 'end of road':
        return 'Turn $modifier at the end of the road $cleanRoad'.trim();
      default:
        if (modifier == 'straight') {
          return 'Continue straight $cleanRoad'.trim();
        }
        return 'Turn $modifier $cleanRoad'.trim();
    }
  }
}
