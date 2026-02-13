import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ride_request.dart';

class RideNotifier extends Notifier<RideRequest?> {
  @override
  RideRequest? build() => null;

  void setRequest(RideRequest? request) {
    state = request;
  }

  void updateStatus(String status) {
    if (state != null) {
      state = state!.copyWith(status: status);
    }
  }

  void clear() {
    state = null;
  }
}

final rideProvider = NotifierProvider<RideNotifier, RideRequest?>(
  RideNotifier.new,
);
