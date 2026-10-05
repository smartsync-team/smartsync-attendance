enum UserRole { student, lecturer, admin }

DateTime? _date(dynamic v) => v == null ? null : DateTime.parse(v as String).toLocal();

class Profile {
  Profile({required this.id, required this.email, required this.fullName, required this.role});

  final String id;
  final String email;
  final String fullName;
  final UserRole role;

  bool get isStaff => role != UserRole.student;
  bool get isAdmin => role == UserRole.admin;

  factory Profile.fromMap(Map<String, dynamic> m) => Profile(
        id: m['id'],
        email: m['email'] ?? '',
        fullName: m['full_name'] ?? '',
        role: UserRole.values.byName(m['role'] ?? 'student'),
      );
}

class Course {
  Course({required this.id, required this.code, required this.name, this.semester, this.lecturerId});

  final String id;
  final String code;
  final String name;
  final String? semester;
  final String? lecturerId;

  String get label => '$code · $name';

  factory Course.fromMap(Map<String, dynamic> m) => Course(
        id: m['id'],
        code: m['code'],
        name: m['name'],
        semester: m['semester'],
        lecturerId: m['lecturer_id'],
      );
}

class Student {
  Student({
    required this.id,
    required this.regNo,
    required this.fullName,
    this.batch,
    this.userId,
    this.fingerprintEnrolledAt,
  });

  final String id;
  final String regNo;
  final String fullName;
  final String? batch;
  final String? userId;
  final DateTime? fingerprintEnrolledAt;

  bool get hasFingerprint => fingerprintEnrolledAt != null;

  factory Student.fromMap(Map<String, dynamic> m) => Student(
        id: m['id'],
        regNo: m['reg_no'],
        fullName: m['full_name'],
        batch: m['batch'],
        userId: m['user_id'],
        fingerprintEnrolledAt: _date(m['fingerprint_enrolled_at']),
      );
}

class SessionStat {
  SessionStat({
    required this.sessionId,
    required this.courseId,
    required this.type,
    required this.startedAt,
    required this.endedAt,
    required this.status,
    required this.attended,
    required this.late,
    required this.enrolled,
  });

  final String sessionId;
  final String courseId;
  final String type;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String status;
  final int attended;
  final int late;
  final int enrolled;

  double get ratio => enrolled == 0 ? 0 : attended / enrolled;

  factory SessionStat.fromMap(Map<String, dynamic> m) => SessionStat(
        sessionId: m['session_id'],
        courseId: m['course_id'],
        type: m['session_type'],
        startedAt: _date(m['started_at'])!,
        endedAt: _date(m['ended_at']),
        status: m['status'],
        attended: (m['attended'] as num).toInt(),
        late: (m['late'] as num).toInt(),
        enrolled: (m['enrolled'] as num).toInt(),
      );
}

class StudentSummary {
  StudentSummary({
    required this.courseId,
    required this.studentId,
    required this.regNo,
    required this.fullName,
    required this.hasFingerprint,
    required this.sessionsHeld,
    required this.attended,
    required this.percent,
  });

  final String courseId;
  final String studentId;
  final String regNo;
  final String fullName;
  final bool hasFingerprint;
  final int sessionsHeld;
  final int attended;
  final double? percent;

  factory StudentSummary.fromMap(Map<String, dynamic> m) => StudentSummary(
        courseId: m['course_id'],
        studentId: m['student_id'],
        regNo: m['reg_no'],
        fullName: m['full_name'],
        hasFingerprint: m['has_fingerprint'] ?? false,
        sessionsHeld: (m['sessions_held'] as num).toInt(),
        attended: (m['attended'] as num).toInt(),
        percent: (m['percent'] as num?)?.toDouble(),
      );
}

/// A student loaded onto the fingerprint device for a session.
class RosterEntry {
  RosterEntry({required this.studentId, required this.regNo, required this.fullName, this.slot});

  final String studentId;
  final String regNo;
  final String fullName;

  /// Sensor slot the template was loaded into, or null if the student has no fingerprint.
  final int? slot;

  Map<String, dynamic> toJson() =>
      {'studentId': studentId, 'regNo': regNo, 'fullName': fullName, 'slot': slot};

  factory RosterEntry.fromJson(Map<String, dynamic> m) => RosterEntry(
        studentId: m['studentId'],
        regNo: m['regNo'],
        fullName: m['fullName'],
        slot: m['slot'],
      );
}

class Mark {
  Mark({required this.studentId, required this.status, required this.at, required this.method});

  final String studentId;
  final String status; // present | late
  final DateTime at;
  final String method; // fingerprint | manual

  Map<String, dynamic> toJson() =>
      {'studentId': studentId, 'status': status, 'at': at.toIso8601String(), 'method': method};

  factory Mark.fromJson(Map<String, dynamic> m) => Mark(
        studentId: m['studentId'],
        status: m['status'],
        at: DateTime.parse(m['at']),
        method: m['method'],
      );
}

/// QR payloads used by the app.
class QrCodes {
  static const _course = 'ATT:COURSE:';
  static const _student = 'ATT:STUDENT:';

  static String course(String courseId) => '$_course$courseId';
  static String student(String studentId) => '$_student$studentId';

  static String? parseCourse(String raw) =>
      raw.startsWith(_course) ? raw.substring(_course.length) : null;
  static String? parseStudent(String raw) =>
      raw.startsWith(_student) ? raw.substring(_student.length) : null;
}
