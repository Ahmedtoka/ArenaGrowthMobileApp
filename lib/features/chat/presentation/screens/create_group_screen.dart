import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/providers/app_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/text_direction_util.dart';
import '../../../../core/widgets/attendance_guard.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../controllers/groups_controller.dart';

/// Create a CUSTOM group (brainstorming room): name + optional photo +
/// hand-picked members. Managers only (the entry button is gated).
class CreateGroupScreen extends ConsumerStatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  ConsumerState<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _PickUser {
  final int id;
  final String name;
  final String? avatarUrl;
  final String? subtitle;
  _PickUser(this.id, this.name, this.avatarUrl, this.subtitle);
}

final _usersProvider = FutureProvider.autoDispose<List<_PickUser>>((ref) async {
  final dio = ref.read(dioClientProvider);
  final res = await dio.get('/team/users');
  final list = (res.data is Map ? (res.data['users'] ?? res.data['data']) : res.data) as List;
  return [
    for (final u in list)
      _PickUser(
        u['id'] as int,
        u['name'] as String? ?? '?',
        u['avatar_url'] as String?,
        (u['job_title'] ?? u['department']) as String?,
      ),
  ];
});

class _CreateGroupScreenState extends ConsumerState<CreateGroupScreen> {
  final _name = TextEditingController();
  final _search = TextEditingController();
  final Set<int> _selected = {};
  File? _photo;
  bool _saving = false;

  Future<void> _pickPhoto() async {
    final picked = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked != null && mounted) setState(() => _photo = File(picked.path));
  }

  Future<void> _save() async {
    // Work-gate: creating a group only while checked-in + active.
    if (!await ref.ensureCheckedIn(context)) return;
    final name = _name.text.trim();
    if (name.isEmpty || _selected.isEmpty || _saving) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Add a group name and pick at least one member'),),);
      return;
    }
    setState(() => _saving = true);
    try {
      final dio = ref.read(dioClientProvider);
      final form = FormData.fromMap({
        'name': name,
        'member_ids[]': _selected.map((e) => e.toString()).toList(),
        if (_photo != null)
          'photo': await MultipartFile.fromFile(_photo!.path),
      });
      await dio.post('/team/groups/custom', data: form);
      ref.invalidate(groupsControllerProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Group "$name" created 🎉')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final users = ref.watch(_usersProvider);
    final q = _search.text.trim().toLowerCase();

    return Scaffold(
      appBar: AppBar(title: const Text('Create group')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: Row(
              children: [
                GestureDetector(
                  onTap: _pickPhoto,
                  child: _photo != null
                      ? CircleAvatar(
                          radius: 28, backgroundImage: FileImage(_photo!),)
                      : const CircleAvatar(
                          radius: 28,
                          backgroundColor: Color(0xFFE7F8F5),
                          child: Icon(Icons.add_a_photo_outlined,
                              color: AppColors.teal,),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _name,
                    decoration: const InputDecoration(
                      labelText: 'Group name',
                      hintText: 'e.g. Creative brainstorm',
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search people…',
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                suffixText: '${_selected.length} selected',
              ),
            ),
          ),
          Expanded(
            child: users.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Failed to load: $e')),
              data: (list) {
                final filtered = q.isEmpty
                    ? list
                    : list
                        .where((u) => u.name.toLowerCase().contains(q))
                        .toList();
                return ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (_, i) {
                    final u = filtered[i];
                    final on = _selected.contains(u.id);
                    return ListTile(
                      dense: true,
                      onTap: () => setState(() =>
                          on ? _selected.remove(u.id) : _selected.add(u.id),),
                      leading: UserAvatar(
                          name: u.name, avatarUrl: u.avatarUrl, size: 36,),
                      title: Text(u.name,
                          textDirection: detectBidiDirection(u.name),
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600,),),
                      subtitle: u.subtitle != null
                          ? Text(u.subtitle!,
                              textDirection: detectBidiDirection(u.subtitle),
                              style: const TextStyle(fontSize: 11.5),)
                          : null,
                      trailing: Icon(
                        on ? Icons.check_circle : Icons.circle_outlined,
                        color: on ? AppColors.teal : AppColors.ink3,
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  style:
                      FilledButton.styleFrom(backgroundColor: AppColors.teal),
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              valueColor:
                                  AlwaysStoppedAnimation(Colors.white),),)
                      : const Icon(Icons.group_add, color: Colors.white),
                  label: Text(_saving ? 'Creating…' : 'Create group',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700,),),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
