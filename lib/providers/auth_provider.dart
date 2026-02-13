import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../models/driver.dart';

class DriverNotifier extends Notifier<Driver?> {
  @override
  Driver? build() => null;

  void setDriver(Driver? driver) {
    state = driver;
  }

  Future<void> updateFCMToken(String id, String token) async {
    try {
      final response = await http.patch(
        Uri.parse('http://localhost:8080/driver/fcm-token'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'id': id, 'fcm_token': token}),
      );
      if (response.statusCode != 200) {
        debugPrint('Failed to update FCM token');
      }
    } catch (e) {
      debugPrint('FCM token update error: $e');
    }
  }

  void logout() {
    state = null;
  }

  Future<bool> deleteAccount(String id) async {
    try {
      final response = await http.delete(
        Uri.parse('http://localhost:8080/driver/drivers/$id'),
      );
      if (response.statusCode == 200) {
        state = null;
        return true;
      }
      return false;
    } catch (e) {
      print('Delete account error: $e');
      return false;
    }
  }
}

final driverProvider = NotifierProvider<DriverNotifier, Driver?>(
  DriverNotifier.new,
);
