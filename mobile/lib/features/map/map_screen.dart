import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../../core/theme/app_theme.dart';
import 'models/gps_telemetry.dart';
import 'models/route_model.dart';
import 'models/trip_alarm.dart';
import 'services/gps_glider_controller.dart';
import 'services/native_gps_service.dart';
import 'services/nominatim_search_service.dart';
import 'services/routing_service.dart';
import 'services/trip_alarm_service.dart';
import 'widgets/active_navigation_hud.dart';
import 'widgets/alarm_setup_sheet.dart';
import 'widgets/alarm_triggered_dialog.dart';
import 'widgets/google_maps_location_marker.dart';
import 'widgets/gps_lock_overlay.dart';
import 'widgets/map_compass_widget.dart';
import 'widgets/map_search_sheet.dart';
import 'widgets/map_telemetry_hud.dart';
import 'widgets/multi_stop_planner_card.dart';
import 'widgets/route_preview_sheet.dart';
import 'widgets/route_search_bar.dart';

enum MapStyleMode {
  riderDark,
  osmStandard,
}

enum NavigationState {
  browsing,
  routePreview,
  activeNavigating,
}

/// Production Google Maps-Style Map, Route Directions & Location Alarm Screen
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  late final GpsGliderController _gliderController;

  LatLng? _glidedPosition;
  double _glidedHeading = 0.0;
  double _glidedAccuracy = 15.0;

  StreamSubscription<GpsTelemetry>? _telemetrySubscription;
  GpsTelemetry? _telemetry;
  String? _errorMessage;

  bool _isFollowingUser = true;
  bool _isLoadingGps = true;
  bool _isCalculatingRoute = false;
  MapStyleMode _selectedStyle = MapStyleMode.riderDark;
  double _mapBearing = 0.0;

  NavigationState _navState = NavigationState.browsing;
  RouteDetails? _activeRoute;
  RouteStep? _currentNavStep;
  TripAlarm? _activeAlarm;
  List<RouteWaypoint> _itineraryWaypoints = [];

  static const LatLng _worldFallbackCenter = LatLng(0, 0);

  @override
  void initState() {
    super.initState();
    _gliderController = GpsGliderController(
      vsync: this,
      onTick: (pos, heading, accuracy) {
        if (!mounted) return;
        setState(() {
          _glidedPosition = pos;
          _glidedHeading = heading;
          _glidedAccuracy = accuracy;
        });
        if (_isFollowingUser) {
          _mapController.move(
            pos,
            _navState == NavigationState.activeNavigating ? 17.5 : 17.0,
          );
        }
      },
    );
    _startLiveGpsTracking();
  }

  @override
  void dispose() {
    _gliderController.dispose();
    _telemetrySubscription?.cancel();
    TripAlarmService.stopNativeAlarm();
    super.dispose();
  }

  Future<void> _startLiveGpsTracking() async {
    setState(() {
      _isLoadingGps = true;
      _errorMessage = null;
    });

    try {
      final bool serviceEnabled = await NativeGpsService.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          setState(() {
            _errorMessage = 'Location services are OFF. Please enable GPS in device settings.';
            _isLoadingGps = false;
          });
        }
        return;
      }

      final LocationPermission permission =
          await NativeGpsService.checkAndRequestPermissions();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() {
            _errorMessage = 'Precise Location permission is required for real-time navigation.';
            _isLoadingGps = false;
          });
        }
        return;
      }

      // Query immediate cached hardware GPS fix with pipeline smoothing
      final initialFix = await NativeGpsService.getImmediateSmoothedFix();
      if (initialFix != null && mounted) {
        _applyTelemetry(initialFix, recenter: true);
      }

      // Subscribe to continuous Kalman-smoothed and heading-fused hardware satellite stream
      await _telemetrySubscription?.cancel();
      _telemetrySubscription = NativeGpsService.smoothedTelemetryStream.listen(
        (telemetry) {
          if (!mounted) return;
          _applyTelemetry(telemetry, recenter: false);
        },
        onError: (err) {
          if (mounted && _telemetry == null) {
            setState(() {
              _errorMessage = 'GPS Error: $err';
              _isLoadingGps = false;
            });
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Could not access GPS hardware: $e';
          _isLoadingGps = false;
        });
      }
    }
  }

  void _applyTelemetry(GpsTelemetry data, {required bool recenter}) {
    setState(() {
      _telemetry = data;
      _isLoadingGps = false;
      _errorMessage = null;
    });

    // Feed telemetry into 60 FPS Glider Controller
    _gliderController.onNewTelemetry(data);

    if (recenter) {
      _mapController.move(data.position, _navState == NavigationState.activeNavigating ? 17.5 : 17.0);
    }

    // When in active navigation, track the nearest upcoming turn step
    if (_navState == NavigationState.activeNavigating && _activeRoute != null) {
      _updateActiveNavigationProgress(data.position);
    }

    // Check location alarm trigger
    if (_activeAlarm != null && !_activeAlarm!.isTriggered && !_activeAlarm!.isDismissed) {
      final shouldFire = TripAlarmService.shouldTrigger(
        alarm: _activeAlarm!,
        riderPosition: data.position,
        speedKmh: data.speedKmh,
      );
      if (shouldFire && mounted) {
        setState(() {
          _activeAlarm = _activeAlarm!.copyWith(isTriggered: true);
        });
        TripAlarmService.triggerNativeAlarm();
        AlarmTriggeredDialog.show(
          context: context,
          alarm: _activeAlarm!,
          onDismiss: () {
            setState(() {
              _activeAlarm = _activeAlarm!.copyWith(isDismissed: true);
            });
          },
        );
      }
    }
  }

  void _updateActiveNavigationProgress(LatLng currentPos) {
    if (_activeRoute == null || _activeRoute!.steps.isEmpty) return;

    const distanceCalc = Distance();
    RouteStep? nextStep;
    double minDistance = double.infinity;

    for (final step in _activeRoute!.steps) {
      final double dist = distanceCalc.as(LengthUnit.Meter, currentPos, step.location);
      if (dist < minDistance && dist > 15) {
        minDistance = dist;
        nextStep = step;
      }
    }

    if (nextStep != null && nextStep != _currentNavStep) {
      setState(() {
        _currentNavStep = nextStep;
      });
    }
  }

  Future<void> _handleDestinationSelected(NominatimResult destination) async {
    if (_telemetry == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Waiting for GPS lock before calculating route.'),
          backgroundColor: AppTheme.primaryDark,
        ),
      );
      return;
    }

    _itineraryWaypoints = [
      RouteWaypoint(
        id: 'origin',
        name: 'Your Location',
        location: _telemetry!.position,
        type: WaypointType.origin,
      ),
      RouteWaypoint(
        id: 'destination',
        name: destination.shortName,
        location: destination.position,
        type: WaypointType.destination,
      ),
    ];

    await _recalculateItineraryRoute();
  }

  Future<void> _recalculateItineraryRoute() async {
    if (_itineraryWaypoints.length < 2) return;

    setState(() => _isCalculatingRoute = true);

    final route = await RoutingService.calculateMultiStopRoute(
      waypoints: _itineraryWaypoints,
    );

    if (!mounted) return;
    setState(() => _isCalculatingRoute = false);

    if (route != null) {
      setState(() {
        _activeRoute = route;
        _navState = NavigationState.routePreview;
        _isFollowingUser = false;
        // Pre-configure alarm to destination if none exists
        final destWaypoint = _itineraryWaypoints.last;
        _activeAlarm ??= TripAlarm(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          placeName: destWaypoint.name,
          location: destWaypoint.location,
          radiusMeters: 1000.0,
          createdAt: DateTime.now(),
        );
      });

      // Fit map camera to display all waypoints and the complete polyline
      final allPoints = [
        ..._itineraryWaypoints.map((w) => w.location),
        ...route.polylinePoints,
      ];

      if (allPoints.isNotEmpty) {
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(allPoints),
            padding: const EdgeInsets.fromLTRB(40, 220, 40, 260),
          ),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not calculate driving route for this itinerary.'),
          backgroundColor: AppTheme.errorRed,
        ),
      );
    }
  }

  void _handleAddStop() {
    MapSearchSheet.show(
      context: context,
      title: 'Add Stop Along Route',
      userLocation: _telemetry?.position,
      onLocationSelected: (result) {
        final newStop = RouteWaypoint(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          name: result.shortName,
          location: result.position,
          type: WaypointType.stop,
        );
        setState(() {
          _itineraryWaypoints.insert(_itineraryWaypoints.length - 1, newStop);
        });
        _recalculateItineraryRoute();
      },
    );
  }

  void _handleRemoveStop(int index) {
    if (index <= 0 || index >= _itineraryWaypoints.length - 1) return;
    setState(() {
      _itineraryWaypoints.removeAt(index);
    });
    _recalculateItineraryRoute();
  }

  void _handleEditWaypoint(int index) {
    if (index < 0 || index >= _itineraryWaypoints.length) return;

    final currentWp = _itineraryWaypoints[index];
    final String title = currentWp.isOrigin
        ? 'Change Starting Point'
        : (currentWp.isDestination ? 'Change Destination' : 'Change Stop');

    MapSearchSheet.show(
      context: context,
      title: title,
      userLocation: _telemetry?.position,
      onLocationSelected: (result) {
        setState(() {
          _itineraryWaypoints[index] = RouteWaypoint(
            id: currentWp.id,
            name: result.shortName,
            location: result.position,
            type: currentWp.type,
          );
        });
        _recalculateItineraryRoute();
      },
    );
  }

  void _handleSwapEndpoints() {
    if (_itineraryWaypoints.length < 2) return;

    setState(() {
      final reversed = _itineraryWaypoints.reversed.toList();
      _itineraryWaypoints = [
        reversed.first.copyWith(type: WaypointType.origin),
        for (int i = 1; i < reversed.length - 1; i++)
          reversed[i].copyWith(type: WaypointType.stop),
        reversed.last.copyWith(type: WaypointType.destination),
      ];
    });
    _recalculateItineraryRoute();
  }

  void _showAlarmSetupSheet() {
    if (_itineraryWaypoints.length > 2) {
      _showWaypointSelectionForAlarm();
    } else {
      final targetLocation = _activeRoute?.destination ?? _telemetry?.position ?? _worldFallbackCenter;
      final targetName = _activeRoute?.destinationName ?? 'Trip Destination';
      _openAlarmSheetForTarget(targetName, targetLocation);
    }
  }

  void _showWaypointSelectionForAlarm() {
    final stopsAndDest = _itineraryWaypoints.sublist(1);
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.primaryDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Set Proximity Alarm For:',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              for (int i = 0; i < stopsAndDest.length; i++) ...[
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  tileColor: Colors.white.withValues(alpha: 0.06),
                  leading: Icon(
                    stopsAndDest[i].isDestination
                        ? Icons.flag_rounded
                        : Icons.location_on_rounded,
                    color: stopsAndDest[i].isDestination
                        ? Colors.redAccent
                        : Colors.orangeAccent,
                  ),
                  title: Text(
                    stopsAndDest[i].name,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    stopsAndDest[i].isDestination
                        ? 'Final Destination'
                        : 'Stop ${String.fromCharCode(65 + i)}',
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white60),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _openAlarmSheetForTarget(stopsAndDest[i].name, stopsAndDest[i].location);
                  },
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _openAlarmSheetForTarget(String targetName, LatLng targetLocation) {
    AlarmSetupSheet.show(
      context: context,
      defaultPlaceName: targetName,
      targetLocation: targetLocation,
      existingAlarm: _activeAlarm,
      onAlarmConfigured: (alarm) {
        setState(() {
          _activeAlarm = alarm;
        });
        if (alarm != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Arrival Alarm set: ${alarm.formattedRadius} before ${alarm.placeName}'),
              backgroundColor: AppTheme.primaryDark,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      },
    );
  }

  void _startActiveNavigation() {
    if (_activeRoute == null || _telemetry == null) return;

    setState(() {
      _navState = NavigationState.activeNavigating;
      _isFollowingUser = true;
      _currentNavStep = _activeRoute!.steps.isNotEmpty ? _activeRoute!.steps.first : null;
    });

    _mapController.move(_telemetry!.position, 17.5);
  }

  void _stopNavigation() {
    setState(() {
      _navState = NavigationState.browsing;
      _activeRoute = null;
      _currentNavStep = null;
      _itineraryWaypoints = [];
      _isFollowingUser = true;
    });

    if (_telemetry != null) {
      _mapController.move(_telemetry!.position, 17.0);
    }
  }

  void _recenterOnRider() {
    final pos = _glidedPosition ?? _telemetry?.position;
    if (pos != null) {
      setState(() => _isFollowingUser = true);
      _mapController.move(pos, _navState == NavigationState.activeNavigating ? 17.5 : 17.0);
    } else {
      _startLiveGpsTracking();
    }
  }

  void _zoomIn() {
    final double currentZoom = _mapController.camera.zoom;
    if (currentZoom < 19.0) {
      _mapController.move(_mapController.camera.center, currentZoom + 1.0);
    }
  }

  void _zoomOut() {
    final double currentZoom = _mapController.camera.zoom;
    if (currentZoom > 3.0) {
      _mapController.move(_mapController.camera.center, currentZoom - 1.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final LatLng centerPoint = _glidedPosition ?? _telemetry?.position ?? _worldFallbackCenter;

    return Scaffold(
      backgroundColor: _selectedStyle == MapStyleMode.riderDark
          ? const Color(0xFF121614)
          : AppTheme.backgroundCream,
      body: Stack(
        children: [
          // 1. OPENSTREETMAP RENDERER WITH DYNAMIC ROUTE POLYLINE & ALARM RADIUS
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: centerPoint,
              initialZoom: (_glidedPosition != null || _telemetry != null) ? 17.0 : 3.0,
              minZoom: 2.0,
              maxZoom: 19.0,
              onPositionChanged: (camera, hasGesture) {
                if (hasGesture && _isFollowingUser) {
                  setState(() => _isFollowingUser = false);
                }
                // Track map rotation for compass widget
                final double bearing = camera.rotation;
                if ((bearing - _mapBearing).abs() > 0.1) {
                  setState(() => _mapBearing = bearing);
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.rootu_mobile',
                tileBuilder: _selectedStyle == MapStyleMode.riderDark
                    ? darkModeTileBuilder
                    : null,
                maxZoom: 19,
              ),

              // Road Route Polyline Layer
              if (_activeRoute != null)
                PolylineLayer(
                  polylines: [
                    // Outer dark border
                    Polyline(
                      points: _activeRoute!.polylinePoints,
                      color: AppTheme.primaryDark,
                      strokeWidth: 7.0,
                    ),
                    // Inner glowing neon route path
                    Polyline(
                      points: _activeRoute!.polylinePoints,
                      color: AppTheme.accentLightGreen,
                      strokeWidth: 4.5,
                    ),
                  ],
                ),

              // Alarm Proximity Geofence Radius Circle Layer
              if (_activeAlarm != null)
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: _activeAlarm!.location,
                      radius: _activeAlarm!.radiusMeters,
                      useRadiusInMeter: true,
                      color: AppTheme.accentLightGreen.withValues(alpha: 0.12),
                      borderColor: AppTheme.accentLightGreen,
                      borderStrokeWidth: 2.0,
                    ),
                  ],
                ),

              // GPS Accuracy Circle Layer (Google Maps Blue style, scaled to physical meters)
              if (_telemetry != null)
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: _glidedPosition ?? _telemetry!.position,
                      radius: _glidedAccuracy.clamp(5.0, 150.0),
                      useRadiusInMeter: true,
                      color: const Color(0x224285F4),
                      borderColor: const Color(0x664285F4),
                      borderStrokeWidth: 1.5,
                    ),
                  ],
                ),

              // Markers Layer: Google Maps User Location Marker, Custom Origin, Intermediate Stops, Destination Pin, and Alarm Pin
              MarkerLayer(
                markers: [
                  // Google Maps-Style User Location Marker (60 FPS Animated Glider)
                  if (_telemetry != null)
                    Marker(
                      point: _glidedPosition ?? _telemetry!.position,
                      width: 140,
                      height: 140,
                      alignment: Alignment.center,
                      child: GoogleMapsLocationMarker(
                        heading: _glidedHeading,
                        speedKmh: _telemetry!.speedKmh,
                        isMoving: _telemetry!.speedKmh > 2.0,
                      ),
                    ),

                  // Custom Origin Pin (if origin is not rider's current location)
                  if (_itineraryWaypoints.isNotEmpty &&
                      _navState != NavigationState.browsing &&
                      !_itineraryWaypoints.first.name.contains('Your Location'))
                    Marker(
                      point: _itineraryWaypoints.first.location,
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppTheme.accentLightGreen,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.4),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Icon(Icons.trip_origin_rounded, color: AppTheme.primaryDark, size: 20),
                        ),
                      ),
                    ),

                  // Intermediate Stops Pins (A, B, C...)
                  if (_navState != NavigationState.browsing && _itineraryWaypoints.length > 2)
                    for (int i = 0; i < _itineraryWaypoints.sublist(1, _itineraryWaypoints.length - 1).length; i++)
                      Marker(
                        point: _itineraryWaypoints[i + 1].location,
                        width: 36,
                        height: 36,
                        alignment: Alignment.center,
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.orangeAccent,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.4),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              String.fromCharCode(65 + i),
                              style: const TextStyle(
                                color: Colors.black,
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                      ),

                  // Destination Pin
                  if (_activeRoute != null)
                    Marker(
                      point: _activeRoute!.destination,
                      width: 48,
                      height: 48,
                      alignment: Alignment.topCenter,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppTheme.primaryDark,
                          border: Border.all(color: AppTheme.accentLightGreen, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.4),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.location_on_rounded,
                          color: Colors.redAccent,
                          size: 28,
                        ),
                      ),
                    ),

                  // Alarm Location Pin
                  if (_activeAlarm != null)
                    Marker(
                      point: _activeAlarm!.location,
                      width: 42,
                      height: 42,
                      alignment: Alignment.center,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppTheme.primaryDark,
                          border: Border.all(color: AppTheme.accentLightGreen, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.4),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.notifications_active_rounded,
                          color: AppTheme.accentLightGreen,
                          size: 20,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),

          // 2. TOP FLOATING GOOGLE MAPS STYLE SEARCH BAR & MULTI-STOP PLANNER
          if (_navState == NavigationState.browsing)
            RouteSearchBar(
              userLocation: _telemetry?.position,
              isDarkTheme: _selectedStyle == MapStyleMode.riderDark,
              onThemeToggle: () {
                setState(() {
                  _selectedStyle = _selectedStyle == MapStyleMode.riderDark
                      ? MapStyleMode.osmStandard
                      : MapStyleMode.riderDark;
                });
              },
              onDestinationSelected: _handleDestinationSelected,
            )
          else if (_navState == NavigationState.routePreview && _itineraryWaypoints.length >= 2)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: MultiStopPlannerCard(
                waypoints: _itineraryWaypoints,
                onAddStop: _handleAddStop,
                onRemoveStop: _handleRemoveStop,
                onEditWaypoint: _handleEditWaypoint,
                onSwapEndpoints: _handleSwapEndpoints,
                onClose: _stopNavigation,
              ),
            ),

          // 3. ROUTE CALCULATION LOADING OVERLAY
          if (_isCalculatingRoute)
            Positioned(
              top: 80,
              left: 20,
              right: 20,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryDark,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppTheme.accentLightGreen),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppTheme.accentLightGreen,
                        ),
                      ),
                      SizedBox(width: 10),
                      Text(
                        'Calculating fastest route...',
                        style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // 4a. GOOGLE MAPS-STYLE COMPASS ROSE (top-right, fades at North)
          Positioned(
            top: MediaQuery.of(context).padding.top + 90,
            right: 16,
            child: MapCompassWidget(
              mapBearingDegrees: _mapBearing,
              onNorthTap: () {
                _mapController.rotate(0);
                setState(() => _mapBearing = 0.0);
              },
            ),
          ),

          // 4. FLOATING RECENTER, ALARM & ZOOM BUTTONS
          Positioned(
            right: 16,
            bottom: _navState == NavigationState.routePreview
                ? 310
                : (_navState == NavigationState.activeNavigating ? 110 : 120),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Set / Configure Trip Alarm FAB
                FloatingActionButton.small(
                  heroTag: 'alarm_setup_btn',
                  tooltip: _activeAlarm != null ? 'Alarm Active' : 'Set Location Alarm',
                  backgroundColor: _activeAlarm != null
                      ? AppTheme.accentLightGreen
                      : AppTheme.primaryDark.withValues(alpha: 0.94),
                  onPressed: _showAlarmSetupSheet,
                  child: Icon(
                    _activeAlarm != null
                        ? Icons.notifications_active_rounded
                        : Icons.alarm_add_rounded,
                    color: _activeAlarm != null ? AppTheme.primaryDark : Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(height: 10),

                // Recenter Button
                FloatingActionButton.small(
                  heroTag: 'recenter_btn',
                  tooltip: 'Recenter on Rider',
                  backgroundColor: _isFollowingUser
                      ? AppTheme.accentLightGreen
                      : AppTheme.primaryDark.withValues(alpha: 0.94),
                  onPressed: _recenterOnRider,
                  child: Icon(
                    Icons.my_location_rounded,
                    color: _isFollowingUser ? AppTheme.primaryDark : Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(height: 10),

                // Zoom In Button
                FloatingActionButton.small(
                  heroTag: 'zoom_in_btn',
                  tooltip: 'Zoom In',
                  backgroundColor: AppTheme.primaryDark.withValues(alpha: 0.94),
                  onPressed: _zoomIn,
                  child: const Icon(Icons.add_rounded, color: Colors.white, size: 20),
                ),
                const SizedBox(height: 8),

                // Zoom Out Button
                FloatingActionButton.small(
                  heroTag: 'zoom_out_btn',
                  tooltip: 'Zoom Out',
                  backgroundColor: AppTheme.primaryDark.withValues(alpha: 0.94),
                  onPressed: _zoomOut,
                  child: const Icon(Icons.remove_rounded, color: Colors.white, size: 20),
                ),
              ],
            ),
          ),

          // 5. BOTTOM ROUTE PREVIEW SHEET (Google Maps Style Summary with Alarm Toggle)
          if (_navState == NavigationState.routePreview && _activeRoute != null)
            RoutePreviewSheet(
              route: _activeRoute!,
              activeAlarm: _activeAlarm,
              onConfigureAlarm: _showAlarmSetupSheet,
              onStartNavigation: _startActiveNavigation,
              onClose: _stopNavigation,
            ),

          // 6. ACTIVE NAVIGATION HUD (Turn-by-turn driving mode with Alarm Pill)
          if (_navState == NavigationState.activeNavigating && _activeRoute != null)
            ActiveNavigationHud(
              route: _activeRoute!,
              currentStep: _currentNavStep,
              activeAlarm: _activeAlarm,
              onConfigureAlarm: _showAlarmSetupSheet,
              onStopNavigation: _stopNavigation,
            ),

          // 7. BOTTOM TELEMETRY HUD BAR (Visible in browsing mode)
          if (_navState == NavigationState.browsing)
            MapTelemetryHud(
              telemetry: _telemetry,
              isFollowingUser: _isFollowingUser,
            ),

          // 8. GPS ACQUISITION / PERMISSIONS OVERLAY (Shown until hardware fix is locked)
          if (_telemetry == null || _isLoadingGps)
            GpsLockOverlay(
              errorMessage: _errorMessage,
              onRetry: _startLiveGpsTracking,
            ),
        ],
      ),
    );
  }
}
