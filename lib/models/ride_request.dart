import 'package:latlong2/latlong.dart';

class RideRequest {
  final String id;
  final LatLng pickupLocation;
  final LatLng destinationLocation;
  final String customerName;
  final double estimatedFare;
  final double estimatedDistanceKm;
  final int estimatedTimeMinutes;
  final List<LatLng> routePoints;
  final List<LatLng> pickupRoutePoints;
  final double pickupDistanceKm;
  final int pickupTimeMinutes;

  RideRequest({
    required this.id,
    required this.pickupLocation,
    required this.destinationLocation,
    required this.customerName,
    required this.estimatedFare,
    required this.estimatedDistanceKm,
    required this.estimatedTimeMinutes,
    required this.routePoints,
    required this.pickupRoutePoints,
    required this.pickupDistanceKm,
    required this.pickupTimeMinutes,
  });
}
