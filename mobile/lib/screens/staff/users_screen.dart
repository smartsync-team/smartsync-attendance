import 'package:flutter/material.dart';

import '../../models.dart';
import '../../services/api.dart';
import '../../widgets/common.dart';

/// Admin only: give lecturers access (everyone signs up as a student).
class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  final _q = TextEditingController();
  Future<List<Profile>>? _future;

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  void _search() => setState(() => _future = Api.searchProfiles(_q.text));

  Future<void> _setRole(Profile p, UserRole role) async {
    final ok = await withProgress(context, 'Saving…', () async {
      await Api.setRole(p.id, role);
      return true;
    });
    if (ok == true && mounted) {
      toast(context, '${p.email} is now ${role.name}');
      _search();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Users')),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
            child: TextField(
              controller: _q,
              decoration: InputDecoration(
                hintText: 'Search by email or name',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward), onPressed: _search),
              ),
              onSubmitted: (_) => _search(),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Profile>>(
              future: _future,
              builder: (_, snap) {
                if (snap.hasError) return ErrorView(errorText(snap.error!), onRetry: _search);
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                final users = snap.data!;
                if (users.isEmpty) return const Center(child: Muted('No users found.'));
                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  itemCount: users.length,
                  separatorBuilder: (_, _) => const Divider(),
                  itemBuilder: (_, i) {
                    final u = users[i];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(u.fullName.isEmpty ? u.email : u.fullName),
                      subtitle: Text(u.email),
                      trailing: DropdownButton<UserRole>(
                        value: u.role,
                        underline: const SizedBox(),
                        items: [for (final r in UserRole.values) DropdownMenuItem(value: r, child: Text(r.name))],
                        onChanged: (r) {
                          if (r != null && r != u.role) _setRole(u, r);
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ]),
      );
}
