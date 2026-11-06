import 'package:latlong2/latlong.dart';

/// Model representing a user-configured proximity/wake-up arrival alarm for trips
class TripAlarm {
  final String id;
  final String placeName;
  final LatLng location;
  final double radiusMeters;
  final bool isTriggered;
  final bool isDismissed;
  final DateTime createdAt;

  const TripAlarm({
    required this.id,
    required this.placeName,
    required this.location,
    required this.radiusMeters,
    this.isTriggered = false,
    this.isDismissed = false,
    required this.createdAt,
  });

  String get formattedRadius {
    if (radiusMeters >= 1000) {
      final km = radiusMeters / 1000;
      return km == km.roundToDouble() ? '${km.toInt()} km' : '${km.toStringAsFixed(1)} km';
    }
    return '${radiusMeters.toInt()} m';
  }

  TripAlarm copyWith({
    String? id,
    String? placeName,
    LatLng? location,
    double? radiusMeters,
    bool? isTriggered,
    bool? isDismissed,
    DateTime? createdAt,
  }) {
    return TripAlarm(
      id: id ?? this.id,
      placeName: placeName ?? this.placeName,
      location: location ?? this.location,
      radiusMeters: radiusMeters ?? this.radiusMeters,
      isTriggered: isTriggered ?? this.isTriggered,
      isDismissed: isDismissed ?? this.isDismissed,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

