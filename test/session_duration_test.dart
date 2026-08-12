import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/utils/session_duration.dart';

void main() {
  group('formatSessionDuration', () {
    // The boundary table: the :30 round-up and the "never show 60m" rollover.
    const cases = <int, String>{
      0: '0m',
      3629: '1h', //   60m29s — rounds down
      3630: '1h 1m', // 60m30s — rounds up
      3631: '1h 1m', // 60m31s
      3569: '59m', //  59m29s — rounds down
      3570: '1h', //   59m30s — rounds up to a clean hour, not "60m"
      1800: '30m',
      5400: '1h 30m',
      3540: '59m', //  exactly 59m
      3600: '1h', //   exactly 1h
    };

    cases.forEach((seconds, expected) {
      test('$seconds -> "$expected"', () {
        expect(formatSessionDuration(seconds), expected);
      });
    });
  });
}
