import 'package:attendance_app/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('QR payloads round-trip', () {
    expect(QrCodes.parseCourse(QrCodes.course('abc')), 'abc');
    expect(QrCodes.parseStudent(QrCodes.student('xyz')), 'xyz');
    expect(QrCodes.parseCourse(QrCodes.student('xyz')), isNull);
  });

  test('Mark serialises', () {
    final m = Mark(studentId: 's1', status: 'late', at: DateTime(2026, 10, 5, 10, 20), method: 'fingerprint');
    final back = Mark.fromJson(m.toJson());
    expect(back.status, 'late');
    expect(back.at, m.at);
  });
}
