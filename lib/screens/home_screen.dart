import 'dart:convert';

import 'package:daiko_kun_driver/models/ride_request.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _isOnline = false;
  LatLng? _currentPosition;
  final MapController _mapController = MapController();
  RideRequest? _pendingRequest;

  @override
  void initState() {
    super.initState();
    _initializeLocation();
  }

  Future<void> _initializeLocation() async {
    await _checkLocationPermission();
    _getCurrentLocation();
  }

  Future<void> _checkLocationPermission() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Future.error('Location services are disabled.');
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return Future.error('Location permissions are denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return Future.error(
        'Location permissions are permanently denied, we cannot request permissions.',
      );
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      setState(() {
        _currentPosition = LatLng(position.latitude, position.longitude);
      });
      _mapController.move(_currentPosition!, 15.0);
    } catch (e) {
      debugPrint("Error getting location: $e");
    }
  }

  void _toggleStatus(bool value) {
    setState(() {
      _isOnline = value;
    });
  }

  // OSRM APIを使用して実際の走行ルートを取得
  Future<Map<String, dynamic>> _getRouteData(LatLng start, LatLng dest) async {
    try {
      final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/'
        '${start.longitude},${start.latitude};${dest.longitude},${dest.latitude}'
        '?overview=full&geometries=geojson',
      );

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final route = data['routes'][0];
        final double distanceInMeters = route['distance'].toDouble();
        final double durationInSeconds = route['duration'].toDouble();

        final List<dynamic> coordinates = route['geometry']['coordinates'];
        final List<LatLng> points = coordinates
            .map((coord) => LatLng(coord[1].toDouble(), coord[0].toDouble()))
            .toList();

        return {
          'points': points,
          'distanceKm': distanceInMeters / 1000,
          'durationMinutes': (durationInSeconds / 60).round(),
        };
      }
    } catch (e) {
      debugPrint('Error fetching route: $e');
    }

    // Fallback to straight line if API fails
    final distanceInMeters = const Distance().as(LengthUnit.Meter, start, dest);

    return {
      'points': [start, dest],
      'distanceKm': distanceInMeters / 1000,
      'durationMinutes': (distanceInMeters / 1000 * 5)
          .round(), // Rough estimate
    };
  }

  // デバッグ用：依頼を受信した動作をシミュレート
  Future<void> _simulateRideRequest() async {
    if (!_isOnline) return;

    if (_currentPosition == null) return;

    // Show loading indicator or similar if needed
    // For now just simulation logic

    // 現在地から少し離れた場所をピックアップ地点とする
    final pickup = LatLng(
      _currentPosition!.latitude + 0.005,
      _currentPosition!.longitude + 0.005,
    );
    // Destination further away
    final destination = LatLng(
      _currentPosition!.latitude + 0.02,
      _currentPosition!.longitude + 0.02,
    );

    // Fetch actual route data
    final routeData = await _getRouteData(pickup, destination);
    final List<LatLng> routePoints = routeData['points'];
    final double distanceKm = routeData['distanceKm'];
    final int durationMinutes = routeData['durationMinutes'];

    // お迎え場所までのルートデータを取得
    final pickupRouteData = await _getRouteData(_currentPosition!, pickup);
    final double pickupDistanceKm = pickupRouteData['distanceKm'];
    final int pickupTimeMinutes = pickupRouteData['durationMinutes'];

    final request = RideRequest(
      id: 'req_123',
      pickupLocation: pickup,
      destinationLocation: destination,
      customerName: '佐藤 太郎',
      estimatedFare: (3000 + (distanceKm * 200)).round().toDouble(),
      estimatedDistanceKm: double.parse(distanceKm.toStringAsFixed(1)),
      estimatedTimeMinutes: durationMinutes,
      routePoints: routePoints,
      pickupRoutePoints: pickupRouteData['points'],
      pickupDistanceKm: double.parse(pickupDistanceKm.toStringAsFixed(1)),
      pickupTimeMinutes: pickupTimeMinutes,
    );

    setState(() {
      _pendingRequest = request;
    });

    if (mounted) {
      // Adjust map to fit all points: Driver, Pickup, Destination
      final allPoints = [
        _currentPosition!,
        request.pickupLocation,
        request.destinationLocation,
        ...request.pickupRoutePoints,
        ...request.routePoints,
      ];
      _mapController.fitCamera(
        CameraFit.coordinates(
          coordinates: allPoints,
          padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 100),
        ),
      );
    }
  }

  Widget _buildRequestInfoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, color: Colors.grey[600]),
        const SizedBox(width: 16),
        Text(
          text,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ホーム'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (_isOnline) // シミュレーションボタンをオンライン時のみ表示
            IconButton(
              icon: const Icon(Icons.notifications_active),
              onPressed: _simulateRideRequest,
              tooltip: '依頼シミュレーション',
            ),
          Row(
            children: [
              Text(
                _isOnline ? 'オンライン' : 'オフライン',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: _isOnline ? Colors.green : Colors.grey,
                ),
              ),
              Switch(
                value: _isOnline,
                onChanged: _toggleStatus,
                activeTrackColor: Colors.green.withAlpha(128),
                activeColor: Colors
                    .green, // Although deprecated in some contexts, let's use thumbColor if it really complained
              ),
              const SizedBox(width: 16),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter:
                  _currentPosition ??
                  const LatLng(
                    35.681236,
                    139.767125,
                  ), // Default to Tokyo if null
              initialZoom: 14.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.daiko_kun_driver',
              ),
              if (_currentPosition != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _currentPosition!,
                      width: 80,
                      height: 80,
                      child: const Icon(
                        Icons.local_taxi,
                        color: Colors.blue,
                        size: 40,
                      ),
                    ),
                    if (_pendingRequest != null) ...[
                      // Pickup (Green)
                      Marker(
                        point: _pendingRequest!.pickupLocation,
                        width: 80,
                        height: 80,
                        child: const Icon(
                          Icons.location_on,
                          color: Colors.green,
                          size: 40,
                        ),
                      ),
                      // Destination (Red)
                      Marker(
                        point: _pendingRequest!.destinationLocation,
                        width: 80,
                        height: 80,
                        child: const Icon(
                          Icons.flag,
                          color: Colors.red,
                          size: 40,
                        ),
                      ),
                    ],
                  ],
                ),
              if (_pendingRequest != null)
                PolylineLayer(
                  polylines: [
                    // お迎えルート (緑色の点線風/細め)
                    Polyline(
                      points: _pendingRequest!.pickupRoutePoints,
                      strokeWidth: 3.0,
                      color: Colors.green.withAlpha((0.7 * 255).round()),
                    ),
                    // 送迎ルート (青色の太線)
                    Polyline(
                      points: _pendingRequest!.routePoints,
                      strokeWidth: 5.0,
                      color: Colors.blue,
                    ),
                  ],
                ),
            ],
          ),
          // Overlay for Status
          if (_pendingRequest == null) // 依頼受信中は隠す
            Positioned(
              bottom: 30,
              left: 20,
              right: 20,
              child: Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _isOnline ? '乗車依頼を探しています...' : 'オフライン中',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: _isOnline ? Colors.green : Colors.grey,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_isOnline)
                        const LinearProgressIndicator()
                      else
                        const Text('オンラインにして依頼待ちを開始してください'),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => _toggleStatus(!_isOnline),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isOnline
                                ? Colors.red
                                : Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: Text(_isOnline ? '待機を終了する' : '待機を開始する'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          // Request Overlay
          if (_pendingRequest != null)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(50),
                      blurRadius: 10,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '新しい乗車依頼を受信！',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.deepPurple,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    _buildRequestInfoRow(
                      Icons.person,
                      _pendingRequest!.customerName,
                    ),
                    const SizedBox(height: 12),
                    _buildRequestInfoRow(
                      Icons.attach_money,
                      '¥${_pendingRequest!.estimatedFare.toInt()} (推定)',
                    ),
                    const SizedBox(height: 12),
                    _buildRequestInfoRow(
                      Icons.directions_car,
                      '走行距離: ${_pendingRequest!.estimatedDistanceKm} km / ${_pendingRequest!.estimatedTimeMinutes} 分',
                    ),
                    const SizedBox(height: 12),
                    _buildRequestInfoRow(
                      Icons.location_on,
                      'お迎えまで：約${_pendingRequest!.pickupDistanceKm}km / ${_pendingRequest!.pickupTimeMinutes}分',
                    ),
                    const SizedBox(height: 32),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              setState(() {
                                _pendingRequest = null;
                              });
                            },
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              side: const BorderSide(color: Colors.red),
                              foregroundColor: Colors.red,
                            ),
                            child: const Text('拒否'),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              setState(() {
                                _pendingRequest = null;
                              });
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('依頼を受けました！お迎えに向かってください。'),
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('承認して向かう'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          // Center current location button
          Positioned(
            bottom: _pendingRequest != null
                ? 380
                : 240, // Adjust position based on card height
            right: 20,
            child: FloatingActionButton(
              onPressed: _getCurrentLocation,
              child: const Icon(Icons.my_location),
            ),
          ),
        ],
      ),
    );
  }
}
