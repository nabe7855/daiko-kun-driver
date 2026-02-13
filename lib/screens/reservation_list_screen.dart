import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../providers/auth_provider.dart';

class ReservationListScreen extends ConsumerStatefulWidget {
  const ReservationListScreen({super.key});

  @override
  ConsumerState<ReservationListScreen> createState() =>
      _ReservationListScreenState();
}

class _ReservationListScreenState extends ConsumerState<ReservationListScreen> {
  bool _isLoading = true;
  List<dynamic> _reservations = [];

  @override
  void initState() {
    super.initState();
    _fetchReservations();
  }

  Future<void> _fetchReservations() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.get(
        Uri.parse('http://localhost:8080/driver/reserved-requests'),
      );

      if (response.statusCode == 200) {
        setState(() {
          _reservations = json.decode(response.body);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching reservations: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _acceptReservation(String requestId) async {
    final driver = ref.read(driverProvider);
    if (driver == null) return;

    try {
      final response = await http.post(
        Uri.parse(
          'http://localhost:8080/driver/ride-requests/$requestId/accept',
        ),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'driver_id': driver.id}),
      );

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('予約を受諾しました')));
          _fetchReservations();
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('受諾に失敗しました（既に他の事業者が受諾した可能性があります）')),
          );
        }
      }
    } catch (e) {
      debugPrint('Error accepting reservation: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('予約リスト'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchReservations,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _reservations.isEmpty
          ? const Center(child: Text('現在、予約可能な依頼はありません'))
          : ListView.builder(
              itemCount: _reservations.length,
              itemBuilder: (context, index) {
                final res = _reservations[index];
                final scheduledAt = DateTime.parse(res['scheduled_at']);
                final pickupDate = DateFormat('MM/dd').format(scheduledAt);
                final pickupTime = DateFormat('HH:mm').format(scheduledAt);

                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.deepPurple.shade100,
                      child: const Icon(
                        Icons.calendar_today,
                        color: Colors.deepPurple,
                      ),
                    ),
                    title: Text('$pickupDate $pickupTime お迎え'),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('お客様: ${res['customer_id']}'),
                        Text('お迎え: ${res['pickup_address'] ?? '住所未設定'}'),
                        Text('目的地: ${res['destination_address'] ?? '住所未設定'}'),
                        Text(
                          '推定料金: ¥${(res['estimated_fare'] as num).toInt()}',
                        ),
                      ],
                    ),
                    isThreeLine: true,
                    trailing: ElevatedButton(
                      onPressed: () => _showAcceptDialog(res['id']),
                      child: const Text('受諾'),
                    ),
                  ),
                );
              },
            ),
    );
  }

  void _showAcceptDialog(String requestId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('予約の受諾'),
        content: const Text('この予約を引き受けますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _acceptReservation(requestId);
            },
            child: const Text('受諾する'),
          ),
        ],
      ),
    );
  }
}
