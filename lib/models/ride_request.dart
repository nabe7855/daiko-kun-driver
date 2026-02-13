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

  final String status;
  final DateTime? scheduledAt;

  RideRequest({
    required this.id,
    required this.status,
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
    this.scheduledAt,
  });

  RideRequest copyWith({
    String? id,
    String? status,
    LatLng? pickupLocation,
    LatLng? destinationLocation,
    String? customerName,
    double? estimatedFare,
    double? estimatedDistanceKm,
    int? estimatedTimeMinutes,
    List<LatLng>? routePoints,
    List<LatLng>? pickupRoutePoints,
    double? pickupDistanceKm,
    int? pickupTimeMinutes,
    DateTime? scheduledAt,
  }) {
    return RideRequest(
      id: id ?? this.id,
      status: status ?? this.status,
      pickupLocation: pickupLocation ?? this.pickupLocation,
      destinationLocation: destinationLocation ?? this.destinationLocation,
      customerName: customerName ?? this.customerName,
      estimatedFare: estimatedFare ?? this.estimatedFare,
      estimatedDistanceKm: estimatedDistanceKm ?? this.estimatedDistanceKm,
      estimatedTimeMinutes: estimatedTimeMinutes ?? this.estimatedTimeMinutes,
      routePoints: routePoints ?? this.routePoints,
      pickupRoutePoints: pickupRoutePoints ?? this.pickupRoutePoints,
      pickupDistanceKm: pickupDistanceKm ?? this.pickupDistanceKm,
      pickupTimeMinutes: pickupTimeMinutes ?? this.pickupTimeMinutes,
      scheduledAt: scheduledAt ?? this.scheduledAt,
    );
  }

  factory RideRequest.fromMap(Map<String, dynamic> map) {
    return RideRequest(
      id: map['id'],
      status: map['status'] ?? 'pending',
      pickupLocation: LatLng(map['pickup_lat'], map['pickup_lng']),
      destinationLocation: LatLng(
        map['destination_lat'],
        map['destination_lng'],
      ),
      customerName: map['customer_id'] ?? 'お客様',
      estimatedFare: (map['estimated_fare'] as num).toDouble(),
      estimatedDistanceKm: 0,
      estimatedTimeMinutes: 0,
      routePoints: [],
      pickupRoutePoints: [],
      pickupDistanceKm: 0,
      pickupTimeMinutes: 0,
      scheduledAt: map['scheduled_at'] != null
          ? DateTime.parse(map['scheduled_at'])
          : null,
    );
  }
}
