import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../models/ride_request.dart';
import '../providers/auth_provider.dart';
import '../providers/ride_provider.dart';

class MyReservationsScreen extends ConsumerStatefulWidget {
  const MyReservationsScreen({super.key});

  @override
  ConsumerState<MyReservationsScreen> createState() =>
      _MyReservationsScreenState();
}

class _MyReservationsScreenState extends ConsumerState<MyReservationsScreen> {
  bool _isLoading = true;
  List<dynamic> _reservations = [];

  @override
  void initState() {
    super.initState();
    _fetchMyReservations();
  }

  Future<void> _fetchMyReservations() async {
    final driver = ref.read(driverProvider);
    if (driver == null) return;

    setState(() => _isLoading = true);
    try {
      final response = await http.get(
        Uri.parse(
          'http://localhost:8080/driver/drivers/${driver.id}/reservations',
        ),
      );

      if (response.statusCode == 200) {
        setState(() {
          _reservations = json.decode(response.body);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching my reservations: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('受諾済みの予約'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchMyReservations,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _reservations.isEmpty
          ? const Center(child: Text('受諾済みの予約はありません'))
          : ListView.builder(
              itemCount: _reservations.length,
              itemBuilder: (context, index) {
                final res = _reservations[index];
                final scheduledAt = DateTime.parse(res['scheduled_at']);
                final pickupDate = DateFormat('MM/dd (E)').format(scheduledAt);
                final pickupTime = DateFormat('HH:mm').format(scheduledAt);

                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: ExpansionTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.green.shade100,
                      child: const Icon(
                        Icons.event_available,
                        color: Colors.green,
                      ),
                    ),
                    title: Text('$pickupDate $pickupTime'),
                    subtitle: Text('お客様: ${res['customer_id']} 様'),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildInfoRow(
                              Icons.location_on,
                              'お迎え先:',
                              res['pickup_address'] ?? '住所未設定',
                            ),
                            const SizedBox(height: 8),
                            _buildInfoRow(
                              Icons.flag,
                              '目的地:',
                              res['destination_address'] ?? '住所未設定',
                            ),
                            const SizedBox(height: 8),
                            _buildInfoRow(
                              Icons.attach_money,
                              '推定料金:',
                              '¥${(res['estimated_fare'] as num).toInt()}',
                            ),
                            const SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () => _startTrip(res),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.indigo,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                ),
                                child: const Text('お迎えを開始する'),
                              ),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                onPressed: () => _showCancelDialog(res['id']),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.red,
                                ),
                                child: const Text('予約を辞退する'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: Colors.grey),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(width: 8),
        Expanded(child: Text(value)),
      ],
    );
  }

  void _startTrip(dynamic res) {
    final ride = RideRequest.fromMap(res);
    ref.read(rideProvider.notifier).setRequest(ride);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('お迎えを開始しました。ホーム画面で詳細を確認してください。')),
    );
    Navigator.pop(context); // ホームに戻る
  }

  void _showCancelDialog(String requestId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('予約の辞退'),
        content: const Text('この予約を辞退しますか？（他の事業者が受諾可能な状態に戻ります）'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _cancelReservation(requestId);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('辞退する'),
          ),
        ],
      ),
    );
  }

  Future<void> _cancelReservation(String requestId) async {
    try {
      final response = await http.patch(
        Uri.parse(
          'http://localhost:8080/driver/ride-requests/$requestId/status',
        ),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'status': 'pending'}), // driver_idを消す処理がバックエンドに必要かも
      );

      if (response.statusCode == 200) {
        final activeRide = ref.read(rideProvider);
        if (activeRide != null && activeRide.id == requestId) {
          ref.read(rideProvider.notifier).clear();
        }
        _fetchMyReservations();
      }
    } catch (e) {
      debugPrint('Error resigning reservation: $e');
    }
  }
}
