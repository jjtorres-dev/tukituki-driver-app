import 'package:flutter_test/flutter_test.dart';

import 'package:driver/features/driver/domain/driver_cancellation_reason.dart';

void main() {
  test('expone exactamente los 6 motivos utilizables por Backend', () {
    expect(DriverCancellationReason.values.length, 6);
  });

  test('los valores wire coinciden exactamente con el enum Backend', () {
    final values = DriverCancellationReason.values.map((r) => r.value).toSet();

    expect(values, {
      'PASSENGER_REQUESTED_CANCEL',
      'CANNOT_REACH_PICKUP',
      'VEHICLE_PROBLEM',
      'SAFETY_CONCERN',
      'EMERGENCY',
      'OTHER',
    });
  });

  test('NUNCA incluye PASSENGER_NOT_FOUND (Backend lo rechaza en este endpoint)', () {
    final values = DriverCancellationReason.values.map((r) => r.value);

    expect(values, isNot(contains('PASSENGER_NOT_FOUND')));
  });

  test('cada label es texto legible, nunca el enum raw', () {
    for (final reason in DriverCancellationReason.values) {
      expect(reason.label, isNot(equals(reason.value)));
      expect(reason.label, isNot(contains('_')));
    }
  });
}
