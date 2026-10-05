import 'package:supabase_flutter/supabase_flutter.dart';

import '../models.dart';

/// All database access goes through here. Row level security on the server
/// decides what each role can actually read or write.
class Api {
  static SupabaseClient get db => Supabase.instance.client;
  static String? get uid => db.auth.currentUser?.id;

  /// PostgREST returns at most 1000 rows per request, so page through results.
  static Future<List<Map<String, dynamic>>> _all(
      PostgrestTransformBuilder<PostgrestList> Function() query) async {
    const page = 1000;
    final out = <Map<String, dynamic>>[];
    for (var from = 0;; from += page) {
      final rows = await query().range(from, from + page - 1);
      out.addAll(rows);
      if (rows.length < page) return out;
    }
  }

  // ---------------- auth / profile ----------------

  static Future<Profile?> myProfile() async {
    if (uid == null) return null;
    final row = await db.from('profiles').select().eq('id', uid!).maybeSingle();
    return row == null ? null : Profile.fromMap(row);
  }

  static Future<List<Profile>> searchProfiles(String q) async {
    var query = db.from('profiles').select();
    if (q.trim().isNotEmpty) {
      query = query.or('email.ilike.%${q.trim()}%,full_name.ilike.%${q.trim()}%');
    }
    final rows = await query.order('email').limit(50);
    return rows.map(Profile.fromMap).toList();
  }

  static Future<void> setRole(String profileId, UserRole role) =>
      db.from('profiles').update({'role': role.name}).eq('id', profileId);

  // ---------------- courses ----------------

  static Future<List<Course>> staffCourses(Profile me) async {
    var query = db.from('courses').select();
    if (!me.isAdmin) query = query.eq('lecturer_id', me.id);
    final rows = await query.order('code');
    return rows.map(Course.fromMap).toList();
  }

  static Future<Course?> courseById(String id) async {
    final row = await db.from('courses').select().eq('id', id).maybeSingle();
    return row == null ? null : Course.fromMap(row);
  }

  static Future<Course?> courseByCode(String code) async {
    final row = await db.from('courses').select().ilike('code', code.trim()).maybeSingle();
    return row == null ? null : Course.fromMap(row);
  }

  static Future<Course> createCourse({required String code, required String name, String? semester}) async {
    final row = await db
        .from('courses')
        .insert({
          'code': code.trim().toUpperCase(),
          'name': name.trim(),
          'semester': (semester ?? '').trim().isEmpty ? null : semester!.trim(),
          'lecturer_id': uid,
        })
        .select()
        .single();
    return Course.fromMap(row);
  }

  // ---------------- students ----------------

  static Future<Student?> myStudent() async {
    if (uid == null) return null;
    final row = await db.from('students').select().eq('user_id', uid!).maybeSingle();
    return row == null ? null : Student.fromMap(row);
  }

  static Future<List<Course>> myStudentCourses(String studentId) async {
    final rows = await db.from('course_students').select('courses(*)').eq('student_id', studentId);
    return rows.map((r) => Course.fromMap(r['courses'])).toList()..sort((a, b) => a.code.compareTo(b.code));
  }

  static Future<String> registerStudent({
    required String regNo,
    required String fullName,
    String? batch,
    String? courseId,
  }) async {
    final id = await db.rpc('register_student', params: {
      'p_reg_no': regNo,
      'p_full_name': fullName,
      'p_batch': batch ?? '',
      'p_course_id': courseId,
    });
    return id as String;
  }

  static Future<void> joinCourse(String courseId) =>
      db.rpc('join_course', params: {'p_course_id': courseId});

  static Future<Student?> studentById(String id) async {
    final row = await db.from('students').select().eq('id', id).maybeSingle();
    return row == null ? null : Student.fromMap(row);
  }

  static Future<Student?> studentByRegNo(String regNo) async {
    final row = await db.from('students').select().eq('reg_no', regNo.trim().toUpperCase()).maybeSingle();
    return row == null ? null : Student.fromMap(row);
  }

  /// Staff: create or update a student by registration number.
  static Future<Student> saveStudent({required String regNo, required String fullName, String? batch}) async {
    final row = await db
        .from('students')
        .upsert({
          'reg_no': regNo.trim().toUpperCase(),
          'full_name': fullName.trim(),
          'batch': (batch ?? '').trim().isEmpty ? null : batch!.trim(),
        }, onConflict: 'reg_no')
        .select()
        .single();
    return Student.fromMap(row);
  }

  static Future<void> addToCourse(String courseId, String studentId) => db
      .from('course_students')
      .upsert({'course_id': courseId, 'student_id': studentId}, ignoreDuplicates: true);

  static Future<List<StudentSummary>> courseSummary(String courseId) async {
    final rows = await _all(() => db
        .from('student_course_summary')
        .select()
        .eq('course_id', courseId)
        .order('reg_no'));
    return rows.map(StudentSummary.fromMap).toList();
  }

  // ---------------- fingerprints ----------------

  static Future<void> saveFingerprint({
    required String studentId,
    required String templateB64,
    String? deviceId,
  }) =>
      db.from('fingerprints').upsert({
        'student_id': studentId,
        'template': templateB64,
        'device_id': deviceId,
        'enrolled_by': uid,
        'enrolled_at': DateTime.now().toUtc().toIso8601String(),
      });

  /// Course roster together with fingerprint templates (staff only).
  static Future<List<({RosterEntry student, String? template})>> rosterWithTemplates(String courseId) async {
    final rows = await _all(() => db
        .from('course_students')
        .select('student_id, students(reg_no, full_name, fingerprints(template))')
        .eq('course_id', courseId));
    final out = rows.map((r) {
      final s = r['students'] as Map<String, dynamic>;
      // One-to-one embeds come back as an object; be tolerant of a list too.
      final fp = s['fingerprints'];
      final tpl = fp is Map ? fp['template'] as String? : (fp is List && fp.isNotEmpty ? fp.first['template'] as String? : null);
      return (
        student: RosterEntry(studentId: r['student_id'], regNo: s['reg_no'], fullName: s['full_name']),
        template: tpl,
      );
    }).toList();
    out.sort((a, b) => a.student.regNo.compareTo(b.student.regNo));
    return out;
  }

  // ---------------- sessions / attendance ----------------

  static Future<void> createSession({
    required String id,
    required String courseId,
    required String type,
    required int lateAfterMin,
    required DateTime startedAt,
    String? deviceId,
  }) =>
      db.from('sessions').insert({
        'id': id,
        'course_id': courseId,
        'session_type': type,
        'late_after_min': lateAfterMin,
        'started_at': startedAt.toUtc().toIso8601String(),
        'device_id': deviceId,
        'created_by': uid,
      });

  static Future<void> upsertAttendance(List<Map<String, dynamic>> rows) => db
      .from('attendance')
      .upsert(rows, onConflict: 'session_id,student_id', ignoreDuplicates: true);

  static Future<void> closeSession(String sessionId, DateTime endedAt) => db.rpc('close_session',
      params: {'p_session_id': sessionId, 'p_ended_at': endedAt.toUtc().toIso8601String()});

  static Future<List<SessionStat>> sessionStats(String courseId) async {
    final rows = await _all(() => db
        .from('session_stats')
        .select()
        .eq('course_id', courseId)
        .order('started_at', ascending: false));
    return rows.map(SessionStat.fromMap).toList();
  }

  /// Student view: their own recent check-ins across all courses.
  static Future<List<Map<String, dynamic>>> myRecentAttendance(String studentId) => db
      .from('attendance')
      .select('status, checked_at, sessions(started_at, session_type, courses(code, name))')
      .eq('student_id', studentId)
      .order('id', ascending: false)
      .limit(30);

  static Future<List<StudentSummary>> myCourseSummaries(String studentId) async {
    final rows = await db.from('student_course_summary').select().eq('student_id', studentId);
    return rows.map(StudentSummary.fromMap).toList();
  }

  /// Everything needed to build an export for one course and date range.
  static Future<
      ({
        List<Map<String, dynamic>> sessions,
        List<Map<String, dynamic>> students,
        List<Map<String, dynamic>> attendance
      })> reportData(String courseId, DateTime? from, DateTime? to) async {
    final sessions = await _all(() {
      var q = db.from('sessions').select('id, started_at, session_type').eq('course_id', courseId).eq('status', 'closed');
      if (from != null) q = q.gte('started_at', from.toUtc().toIso8601String());
      if (to != null) q = q.lt('started_at', to.toUtc().toIso8601String());
      return q.order('started_at');
    });
    final students = await _all(() => db
        .from('course_students')
        .select('student_id, students(reg_no, full_name, batch)')
        .eq('course_id', courseId));

    final ids = sessions.map((s) => s['id'] as String).toList();
    final attendance = <Map<String, dynamic>>[];
    // Keep the URL short: query sessions in chunks.
    for (var i = 0; i < ids.length; i += 40) {
      final chunk = ids.sublist(i, i + 40 > ids.length ? ids.length : i + 40);
      attendance.addAll(await _all(() => db
          .from('attendance')
          .select('session_id, student_id, status, checked_at')
          .inFilter('session_id', chunk)
          .order('id')));
    }
    return (sessions: sessions, students: students, attendance: attendance);
  }
}
