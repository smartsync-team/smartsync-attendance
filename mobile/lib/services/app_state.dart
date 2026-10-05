import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models.dart';
import 'api.dart';

/// Who is signed in, and (for staff) which courses they teach.
class AppState extends ChangeNotifier {
  AppState() {
    _sub = Api.db.auth.onAuthStateChange.listen((s) {
      if (s.event == AuthChangeEvent.tokenRefreshed) return;
      refresh();
    });
  }

  late final StreamSubscription<AuthState> _sub;

  bool loading = true;
  String? error;
  Profile? profile;
  Student? student; // set for student accounts that completed registration
  List<Course> courses = const []; // staff: courses they manage

  bool get signedIn => Api.db.auth.currentSession != null;

  Future<void> refresh() async {
    loading = true;
    notifyListeners();
    try {
      if (!signedIn) {
        profile = null;
        student = null;
        courses = const [];
      } else {
        profile = await Api.myProfile();
        if (profile == null) throw 'No profile found. Has schema.sql been run on the database?';
        if (profile!.isStaff) {
          student = null;
          courses = await Api.staffCourses(profile!);
        } else {
          student = await Api.myStudent();
          courses = const [];
        }
      }
      error = null;
    } catch (e) {
      error = e.toString();
    }
    loading = false;
    notifyListeners();
  }

  Future<void> reloadCourses() async {
    if (profile?.isStaff != true) return;
    courses = await Api.staffCourses(profile!);
    notifyListeners();
  }

  Future<void> signOut() => Api.db.auth.signOut();

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
