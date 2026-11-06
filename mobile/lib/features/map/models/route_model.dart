import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

enum WaypointType {
  origin,
  stop,
  destination,
}

/// Waypoint along a multi-stop itinerary (e.g. Origin, Stop A, Stop B, Destination)
class RouteWaypoint {
  final String id;
  final String name;
  final LatLng location;
  final WaypointType type;

  const RouteWaypoint({
    required this.id,
    required this.name,
    required this.location,
    required this.type,
  });

  bool get isOrigin => type == WaypointType.origin;
  bool get isStop => type == WaypointType.stop;
  bool get isDestination => type == WaypointType.destination;

  RouteWaypoint copyWith({
    String? id,
    String? name,
    LatLng? location,
    WaypointType? type,
  }) {
    return RouteWaypoint(
      id: id ?? this.id,
      name: name ?? this.name,
      location: location ?? this.location,
      type: type ?? this.type,
    );
  }
}

/// Single turn or navigation maneuver step along a route
class RouteStep {
  final String instruction;
  final double distanceMeters;
  final double durationSeconds;
  final String maneuverType;
  final String maneuverModifier;
  final LatLng location;

  const RouteStep({
    required this.instruction,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.maneuverType,
    required this.maneuverModifier,
    required this.location,
  });

  IconData get maneuverIcon {
    final mod = maneuverModifier.toLowerCase();
    final type = maneuverType.toLowerCase();

    if (type == 'arrive') return Icons.flag_rounded;
    if (type == 'depart') return Icons.navigation_rounded;
    if (type == 'roundabout' || type == 'rotary') return Icons.change_circle_outlined;

    if (mod.contains('sharp left')) return Icons.turn_sharp_left_rounded;
    if (mod.contains('sharp right')) return Icons.turn_sharp_right_rounded;
    if (mod.contains('slight left')) return Icons.turn_slight_left_rounded;
    if (mod.contains('slight right')) return Icons.turn_slight_right_rounded;
    if (mod.contains('left')) return Icons.turn_left_rounded;
    if (mod.contains('right')) return Icons.turn_right_rounded;
    if (mod.contains('uturn')) return Icons.u_turn_left_rounded;

    return Icons.straight_rounded;
  }

  String get formattedDistance {
    if (distanceMeters >= 1000) {
      return '${(distanceMeters / 1000).toStringAsFixed(1)} km';
    }
    return '${distanceMeters.toStringAsFixed(0)} m';
  }
}

/// Strongly-typed route containing road geometries, distance, duration, turn steps, and waypoints
class RouteDetails {
  final List<LatLng> polylinePoints;
  final double totalDistanceMeters;
  final double totalDurationSeconds;
  final List<RouteStep> steps;
  final LatLng destination;
  final String destinationName;
  final List<RouteWaypoint> waypoints;

  const RouteDetails({
    required this.polylinePoints,
    required this.totalDistanceMeters,
    required this.totalDurationSeconds,
    required this.steps,
    required this.destination,
    required this.destinationName,
    this.waypoints = const [],
  });

  int get intermediateStopsCount => waypoints.where((w) => w.isStop).length;

  String get formattedDistance {
    final km = totalDistanceMeters / 1000;
    if (km >= 10) {
      return '${km.toStringAsFixed(0)} km';
    } else if (km >= 1) {
      return '${km.toStringAsFixed(1)} km';
    }
    return '${totalDistanceMeters.toStringAsFixed(0)} m';
  }

  String get formattedDuration {
    final totalMinutes = (totalDurationSeconds / 60).round();
    if (totalMinutes < 60) {
      return '$totalMinutes min';
    }
    final hours = totalMinutes ~/ 60;
    final remainingMinutes = totalMinutes % 60;
    if (remainingMinutes == 0) {
      return '$hours hr';
    }
    return '$hours hr $remainingMinutes min';
  }

  String get formattedEta {
    final arrivalTime = DateTime.now().add(Duration(seconds: totalDurationSeconds.round()));
    final hour = arrivalTime.hour;
    final minute = arrivalTime.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final standardHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    return '$standardHour:$minute $period';
  }
}
