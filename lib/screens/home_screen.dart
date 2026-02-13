import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../models/ride_request.dart';
import '../providers/auth_provider.dart';
import '../providers/ride_provider.dart';
import 'chat_screen.dart';
import 'history_screen.dart';
import 'my_reservations_screen.dart';
import 'reservation_list_screen.dart';

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
  Timer? _pollingTimer;
  StreamSubscription<Position>? _positionStream;

  @override
  void initState() {
    super.initState();
    _initializeLocation();
  }

  @override
  void dispose() {
    _stopPolling();
    _positionStream?.cancel();
    super.dispose();
  }

  String _getApiUrl(String path) {
    String baseUrl = 'http://localhost:8080';
    return '$baseUrl$path';
  }

  Future<void> _initializeLocation() async {
    await _checkLocationPermission();
    _startLocationUpdates();
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

  void _startLocationUpdates() {
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );
    _positionStream =
        Geolocator.getPositionStream(
          locationSettings: locationSettings,
        ).listen((Position position) {
          if (mounted) {
            setState(() {
              _currentPosition = LatLng(position.latitude, position.longitude);
            });

            if (_isOnline) {
              _updateDriverLocation(position);
            }
          }
        });
  }

  Future<void> _updateDriverLocation(Position position) async {
    final driver = ref.read(driverProvider);
    if (driver == null) return;

    try {
      await http.patch(
        Uri.parse(_getApiUrl('/driver/drivers/${driver.id}/location')),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'lat': position.latitude,
          'lng': position.longitude,
        }),
      );
    } catch (e) {
      debugPrint('Error updating location: $e');
    }
  }

  void _startPolling() {
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (!_isOnline || _pendingRequest != null) return;

      try {
        final response = await http.get(
          Uri.parse(_getApiUrl('/driver/available-requests')),
        );

        if (response.statusCode == 200) {
          final List<dynamic> requests = json.decode(response.body);
          if (requests.isNotEmpty) {
            _handleIncomingRequest(requests.first);
          }
        }
      } catch (e) {
        debugPrint('Polling error: $e');
      }
    });
  }

  void _stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  Future<void> _handleIncomingRequest(Map<String, dynamic> data) async {
    final pickup = LatLng(data['pickup_lat'], data['pickup_lng']);
    final dest = LatLng(data['destination_lat'], data['destination_lng']);

    // Fetch actual route data
    final routeData = await _getRouteData(pickup, dest);
    final pickupRouteData = await _getRouteData(_currentPosition!, pickup);

    final request = RideRequest(
      id: data['id'],
      status: data['status'] ?? 'pending',
      pickupLocation: pickup,
      destinationLocation: dest,
      customerName: data['customer_id'],
      estimatedFare: (data['estimated_fare'] as num).toDouble(),
      estimatedDistanceKm: routeData['distanceKm'],
      estimatedTimeMinutes: routeData['durationMinutes'],
      routePoints: routeData['points'],
      pickupRoutePoints: pickupRouteData['points'],
      pickupDistanceKm: pickupRouteData['distanceKm'],
      pickupTimeMinutes: pickupRouteData['durationMinutes'],
    );

    ref.read(rideProvider.notifier).setRequest(request);
    setState(() {
      _pendingRequest = request;
    });

    _fitMapToRequest(
      pickup,
      dest,
      pickupRouteData['points'],
      routeData['points'],
    );
  }

  Future<void> _handleReservationSelected(RideRequest reservation) async {
    final pickup = reservation.pickupLocation;
    final dest = reservation.destinationLocation;

    // Fetch actual route data (since fromMap doesn't have it)
    final routeData = await _getRouteData(pickup, dest);
    final pickupRouteData = await _getRouteData(_currentPosition!, pickup);

    final updatedRequest = reservation.copyWith(
      estimatedDistanceKm: routeData['distanceKm'],
      estimatedTimeMinutes: routeData['durationMinutes'],
      routePoints: routeData['points'],
      pickupRoutePoints: pickupRouteData['points'],
      pickupDistanceKm: pickupRouteData['distanceKm'],
      pickupTimeMinutes: pickupRouteData['durationMinutes'],
    );

    ref.read(rideProvider.notifier).setRequest(updatedRequest);
    setState(() {
      _pendingRequest = updatedRequest;
    });

    _fitMapToRequest(
      pickup,
      dest,
      pickupRouteData['points'],
      routeData['points'],
    );
  }

  void _fitMapToRequest(
    LatLng pickup,
    LatLng dest,
    List<LatLng> pickupPoints,
    List<LatLng> routePoints,
  ) {
    if (mounted) {
      final allPoints = <LatLng>[
        _currentPosition!,
        pickup,
        dest,
        ...pickupPoints,
        ...routePoints,
      ];
      _mapController.fitCamera(
        CameraFit.coordinates(
          coordinates: allPoints,
          padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 100),
        ),
      );
    }
  }

  Future<void> _updateRideStatus(
    String newStatus, {
    double? actualFare,
    String? paymentMethod,
  }) async {
    if (_pendingRequest == null) return;
    final requestId = _pendingRequest!.id;

    try {
      final Map<String, dynamic> body = {'status': newStatus};
      if (actualFare != null) body['actual_fare'] = actualFare;
      if (paymentMethod != null) body['payment_method'] = paymentMethod;

      final response = await http.patch(
        Uri.parse(_getApiUrl('/driver/ride-requests/$requestId/status')),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(body),
      );

      if (response.statusCode == 200) {
        if (newStatus == 'completed' || newStatus == 'cancelled') {
          ref.read(rideProvider.notifier).clear();
          setState(() {
            _pendingRequest = null;
          });
        } else {
          if (_pendingRequest != null) {
            final updated = _pendingRequest!.copyWith(status: newStatus);
            ref.read(rideProvider.notifier).setRequest(updated);
            setState(() {
              _pendingRequest = updated;
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Error updating status: $e');
    }
  }

  Future<void> _showFinishDialog() async {
    if (_pendingRequest == null) return;
    final fareController = TextEditingController(
      text: _pendingRequest!.estimatedFare.toInt().toString(),
    );
    String paymentMethod = 'cash';

    if (!mounted) return;

    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('走行完了確認'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('最終的なお支払い金額を確認してください'),
              const SizedBox(height: 16),
              TextField(
                controller: fareController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '金額 (¥)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: paymentMethod,
                decoration: const InputDecoration(
                  labelText: '支払い方法',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'cash', child: Text('現金')),
                  DropdownMenuItem(value: 'card', child: Text('クレジットカード')),
                  DropdownMenuItem(value: 'paypay', child: Text('PayPay')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setDialogState(() {
                      paymentMethod = val;
                    });
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('戻る'),
            ),
            ElevatedButton(
              onPressed: () {
                final fareText = fareController.text;
                final fare =
                    double.tryParse(fareText) ?? _pendingRequest!.estimatedFare;
                Navigator.pop(context);
                _updateRideStatus(
                  'completed',
                  actualFare: fare,
                  paymentMethod: paymentMethod,
                );
              },
              child: const Text('完了（確定）'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _acceptRideRequest() async {
    if (_pendingRequest == null) return;
    final driver = ref.read(driverProvider);
    if (driver == null) return;

    final requestId = _pendingRequest!.id;

    try {
      final response = await http.post(
        Uri.parse(_getApiUrl('/driver/ride-requests/$requestId/accept')),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'driver_id': driver.id}),
      );

      if (response.statusCode == 200) {
        setState(() {
          if (_pendingRequest != null) {
            _pendingRequest = RideRequest(
              id: _pendingRequest!.id,
              status: 'accepted',
              pickupLocation: _pendingRequest!.pickupLocation,
              destinationLocation: _pendingRequest!.destinationLocation,
              customerName: _pendingRequest!.customerName,
              estimatedFare: _pendingRequest!.estimatedFare,
              estimatedDistanceKm: _pendingRequest!.estimatedDistanceKm,
              estimatedTimeMinutes: _pendingRequest!.estimatedTimeMinutes,
              routePoints: _pendingRequest!.routePoints,
              pickupRoutePoints: _pendingRequest!.pickupRoutePoints,
              pickupDistanceKm: _pendingRequest!.pickupDistanceKm,
              pickupTimeMinutes: _pendingRequest!.pickupTimeMinutes,
            );
          }
        });
      }
    } catch (e) {
      debugPrint('Accept error: $e');
    }
  }

  Future<void> _toggleStatus(bool value) async {
    final driver = ref.read(driverProvider);
    if (driver == null) return;

    setState(() => _isOnline = value);
    if (value) {
      _startPolling();
    } else {
      _stopPolling();
    }

    try {
      final status = value ? 'active' : 'inactive';
      await http.patch(
        Uri.parse(_getApiUrl('/driver/drivers/${driver.id}/status')),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'status': status}),
      );
    } catch (e) {
      debugPrint('Status toggle error: $e');
    }
  }

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

    final distanceInMeters = const Distance().as(LengthUnit.Meter, start, dest);
    return {
      'points': [start, dest],
      'distanceKm': distanceInMeters / 1000,
      'durationMinutes': (distanceInMeters / 1000 * 5).round(),
    };
  }

  Future<void> _simulateRideRequest() async {
    if (!_isOnline || _currentPosition == null) return;

    final pickup = LatLng(
      _currentPosition!.latitude + 0.005,
      _currentPosition!.longitude + 0.005,
    );
    final destination = LatLng(
      _currentPosition!.latitude + 0.02,
      _currentPosition!.longitude + 0.02,
    );

    final routeData = await _getRouteData(pickup, destination);
    final pickupRouteData = await _getRouteData(_currentPosition!, pickup);

    setState(() {
      _pendingRequest = RideRequest(
        id: 'sim_req_${DateTime.now().millisecondsSinceEpoch}',
        status: 'pending',
        pickupLocation: pickup,
        destinationLocation: destination,
        customerName: '佐藤 太郎 (シミュレーション)',
        estimatedFare: (3000 + (routeData['distanceKm'] * 200))
            .round()
            .toDouble(),
        estimatedDistanceKm: double.parse(
          routeData['distanceKm'].toStringAsFixed(1),
        ),
        estimatedTimeMinutes: routeData['durationMinutes'],
        routePoints: routeData['points'],
        pickupRoutePoints: pickupRouteData['points'],
        pickupDistanceKm: double.parse(
          pickupRouteData['distanceKm'].toStringAsFixed(1),
        ),
        pickupTimeMinutes: pickupRouteData['durationMinutes'],
      );
    });

    if (mounted) {
      final allPoints = <LatLng>[
        _currentPosition!,
        pickup,
        destination,
        ...(pickupRouteData['points'] as List<LatLng>),
        ...(routeData['points'] as List<LatLng>),
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

  Future<void> _showEmergencyDialog() async {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('緊急停止・報告'),
        content: const Text('現在走行中のサービスを緊急停止し、運営に報告しますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _reportEmergency();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('停止・報告する'),
          ),
        ],
      ),
    );
  }

  Future<void> _reportEmergency() async {
    if (_pendingRequest == null) return;
    final driver = ref.read(driverProvider);
    if (driver == null) return;

    try {
      final response = await http.post(
        Uri.parse(
          _getApiUrl('/ride-requests/${_pendingRequest!.id}/emergency'),
        ),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'reporter_id': driver.id,
          'reporter_type': 'driver',
          'reason': 'Driver triggered emergency stop from app',
        }),
      );

      if (response.statusCode == 201) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('緊急報告しました。サービスを停止します。')));
          setState(() {
            _pendingRequest = null;
          });
        }
      }
    } catch (e) {
      debugPrint('Error reporting emergency: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(rideProvider, (previous, next) {
      if (next != null && (previous == null || next.id != previous.id)) {
        if (next.routePoints.isEmpty) {
          _handleReservationSelected(next);
        } else if (_pendingRequest == null || _pendingRequest!.id != next.id) {
          setState(() {
            _pendingRequest = next;
          });
        }
      } else if (next == null && _pendingRequest != null) {
        setState(() {
          _pendingRequest = null;
        });
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('ホーム'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        actions: [
          if (_isOnline)
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
                activeColor: Colors.green,
              ),
              const SizedBox(width: 16),
            ],
          ),
        ],
      ),
      drawer: Drawer(
        child: Column(
          children: [
            DrawerHeader(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.person, size: 48),
                    const SizedBox(height: 8),
                    Text(
                      ref.read(driverProvider)?.name ?? 'ドライバー',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.search),
              title: const Text('予約案件を探す'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ReservationListScreen(),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.event_available),
              title: const Text('自分の予約リスト'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const MyReservationsScreen(),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('売上履歴 (カレンダー)'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const HistoryScreen(),
                  ),
                );
              },
            ),
            const Spacer(),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.grey),
              title: const Text('ログアウト'),
              onTap: () {
                Navigator.pop(context);
                ref.read(driverProvider.notifier).logout();
              },
            ),
            ListTile(
              leading: const Icon(Icons.person_off, color: Colors.grey),
              title: const Text(
                '退会（アカウント削除）',
                style: TextStyle(
                  fontSize: 12,
                  decoration: TextDecoration.underline,
                  color: Colors.grey,
                ),
              ),
              onTap: () {
                _showDeleteAccountConfirmation();
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter:
                  _currentPosition ?? const LatLng(35.681236, 139.767125),
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
                    Polyline(
                      points: _pendingRequest!.pickupRoutePoints,
                      strokeWidth: 3.0,
                      color: Colors.green.withAlpha((0.7 * 255).round()),
                    ),
                    Polyline(
                      points: _pendingRequest!.routePoints,
                      strokeWidth: 5.0,
                      color: Colors.blue,
                    ),
                  ],
                ),
            ],
          ),
          if (_pendingRequest == null)
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
                      _pendingRequest!.status == 'pending'
                          ? '新しい乗車依頼を受信！'
                          : _pendingRequest!.status == 'accepted'
                          ? 'お客様の場所へ向かっています'
                          : _pendingRequest!.status == 'arrived'
                          ? 'お迎え場所に到着しました'
                          : '目的地へ向かっています',
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
                      _pendingRequest!.status == 'started'
                          ? '目的地まで：走行中'
                          : 'お迎えまで：約${_pendingRequest!.pickupDistanceKm}km / ${_pendingRequest!.pickupTimeMinutes}分',
                    ),
                    const SizedBox(height: 32),
                    if (_pendingRequest!.status == 'pending')
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () =>
                                  setState(() => _pendingRequest = null),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                side: const BorderSide(color: Colors.red),
                                foregroundColor: Colors.red,
                              ),
                              child: const Text('拒否'),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _acceptRideRequest,
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                              ),
                              child: const Text('承認して向かう'),
                            ),
                          ),
                        ],
                      )
                    else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ElevatedButton(
                            onPressed: () {
                              if (_pendingRequest!.status == 'accepted') {
                                _updateRideStatus('arrived');
                              } else if (_pendingRequest!.status == 'arrived') {
                                _updateRideStatus('started');
                              } else if (_pendingRequest!.status == 'started') {
                                _showFinishDialog();
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              backgroundColor: Colors.indigo,
                              foregroundColor: Colors.white,
                            ),
                            child: Text(
                              _pendingRequest!.status == 'accepted'
                                  ? 'お迎え場所に到着した'
                                  : _pendingRequest!.status == 'arrived'
                                  ? '乗車を開始する'
                                  : '目的地に到着（完了）',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    final driver = ref.read(driverProvider);
                                    if (_pendingRequest != null &&
                                        driver != null) {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => ChatScreen(
                                            rideId: _pendingRequest!.id,
                                            senderId: driver.id,
                                            senderType: 'driver',
                                          ),
                                        ),
                                      );
                                    }
                                  },
                                  icon: const Icon(Icons.chat),
                                  label: const Text('チャット'),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _showEmergencyDialog,
                                  icon: const Icon(
                                    Icons.report_problem,
                                    color: Colors.orange,
                                  ),
                                  label: const Text(
                                    '緊急停止',
                                    style: TextStyle(color: Colors.orange),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    side: const BorderSide(
                                      color: Colors.orange,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: () => _updateRideStatus('cancelled'),
                            child: const Text(
                              'キャンセルする',
                              style: TextStyle(color: Colors.red),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          Positioned(
            bottom: _pendingRequest != null ? 400 : 240,
            right: 20,
            child: FloatingActionButton(
              onPressed: _moveToCurrentLocation,
              child: const Icon(Icons.my_location),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _moveToCurrentLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      setState(
        () => _currentPosition = LatLng(position.latitude, position.longitude),
      );
      _mapController.move(_currentPosition!, 15.0);
    } catch (e) {
      debugPrint("Error getting location: $e");
    }
  }

  void _showDeleteAccountConfirmation() {
    final driver = ref.read(driverProvider);
    if (driver == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('アカウントを削除しますか？'),
        content: const Text(
          'アカウントを削除すると、これまでの売上履歴やドライバー情報がすべて消去され、元に戻すことはできません。本当に削除しますか？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context); // ダイアログを閉じる
              Navigator.pop(context); // ドロワーも閉じる
              final success = await ref
                  .read(driverProvider.notifier)
                  .deleteAccount(driver.id);
              if (success && mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('アカウントを削除しました。')));
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('削除する', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
