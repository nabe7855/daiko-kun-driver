import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../providers/auth_provider.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  Map<DateTime, List<dynamic>> _events = {};
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _fetchHistory();
  }

  Future<void> _fetchHistory() async {
    final driver = ref.read(driverProvider);
    if (driver == null) return;

    setState(() => _isLoading = true);
    try {
      final response = await http.get(
        Uri.parse('http://localhost:8080/driver/drivers/${driver.id}/history'),
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        Map<DateTime, List<dynamic>> newEvents = {};

        for (var ride in data) {
          final dateStr = ride['created_at'] as String;
          final date = DateTime.parse(dateStr).toLocal();
          final day = DateTime(date.year, date.month, date.day);

          if (newEvents[day] == null) {
            newEvents[day] = [];
          }
          newEvents[day]!.add(ride);
        }

        setState(() {
          _events = newEvents;
        });
      }
    } catch (e) {
      debugPrint('Error fetching history: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  List<dynamic> _getEventsForDay(DateTime day) {
    return _events[DateTime(day.year, day.month, day.day)] ?? [];
  }

  @override
  Widget build(BuildContext context) {
    final selectedRides = _getEventsForDay(_selectedDay ?? _focusedDay);
    final totalSales = selectedRides.fold<double>(
      0,
      (sum, ride) =>
          sum + (ride['actual_fare'] ?? ride['estimated_fare'] ?? 0).toDouble(),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('売上履歴'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchHistory),
        ],
      ),
      body: Column(
        children: [
          TableCalendar(
            firstDay: DateTime.utc(2024, 1, 1),
            lastDay: DateTime.utc(2030, 12, 31),
            focusedDay: _focusedDay,
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            onDaySelected: (selectedDay, focusedDay) {
              setState(() {
                _selectedDay = selectedDay;
                _focusedDay = focusedDay;
              });
            },
            eventLoader: _getEventsForDay,
            calendarStyle: const CalendarStyle(
              todayDecoration: BoxDecoration(
                color: Colors.blueAccent,
                shape: BoxShape.circle,
              ),
              selectedDecoration: BoxDecoration(
                color: Colors.indigo,
                shape: BoxShape.circle,
              ),
              markerDecoration: BoxDecoration(
                color: Colors.orange,
                shape: BoxShape.circle,
              ),
            ),
            headerStyle: const HeaderStyle(
              formatButtonVisible: false,
              titleCentered: true,
            ),
          ),
          const Divider(),
          if (_isLoading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else
            Expanded(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          DateFormat(
                            'yyyy年MM月dd日',
                          ).format(_selectedDay ?? _focusedDay),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '売上合計: ¥${NumberFormat('#,###').format(totalSales)}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.indigo,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: selectedRides.isEmpty
                        ? const Center(child: Text('この日の記録はありません'))
                        : ListView.builder(
                            itemCount: selectedRides.length,
                            itemBuilder: (context, index) {
                              final ride = selectedRides[index];
                              final fare =
                                  (ride['actual_fare'] ??
                                          ride['estimated_fare'] ??
                                          0)
                                      .toDouble();
                              final rating = ride['rating_to_driver'] as int?;
                              final comment = ride['review_comment'] as String?;
                              final time = DateFormat('HH:mm').format(
                                DateTime.parse(ride['created_at']).toLocal(),
                              );

                              return Card(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                child: ListTile(
                                  title: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text('$time - ${ride['customer_id']} 様'),
                                      Text(
                                        '¥${NumberFormat('#,###').format(fare)}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (rating != null)
                                        Row(
                                          children: [
                                            const Text('評価: '),
                                            ...List.generate(
                                              5,
                                              (i) => Icon(
                                                i < rating
                                                    ? Icons.star
                                                    : Icons.star_border,
                                                size: 16,
                                                color: Colors.amber,
                                              ),
                                            ),
                                          ],
                                        ),
                                      if (comment != null && comment.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 4.0,
                                          ),
                                          child: Text(
                                            'コメント: $comment',
                                            style: const TextStyle(
                                              fontStyle: FontStyle.italic,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
