import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/inline_error_banner.dart';
import '../data/shoot_models.dart';
import 'shoots_providers.dart';

/// "Add to Cuva" — schedule (or edit) a shoot from the chat or the calendar.
/// Pick client · date · time · location · team. Managers / AM / creative-photo.
class AddShootSheet extends ConsumerStatefulWidget {
  /// When non-null the sheet opens in EDIT mode (prefilled + PUT + cancel).
  final Shoot? existing;
  const AddShootSheet({super.key, this.existing});

  static Future<bool?> show(BuildContext context, {Shoot? existing}) =>
      showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) => AddShootSheet(existing: existing),
      );

  @override
  ConsumerState<AddShootSheet> createState() => _AddShootSheetState();
}

class _AddShootSheetState extends ConsumerState<AddShootSheet> {
  final _title = TextEditingController();
  final _location = TextEditingController();
  final _location2 = TextEditingController();
  final _notes = TextEditingController();

  int? _brandId;
  final Set<String> _types = {'lifestyle'};
  DateTime? _date;
  int? _hour;
  int? _minute;
  int? _endHour;
  int? _endMinute;
  final Set<int> _team = {};
  int? _leadId;
  String _brandQuery = '';
  String _crewQuery = '';
  bool _saving = false;
  String? _error;

  // New attachments picked in this session (existing ones show read-only).
  final List<File> _files = [];
  final List<String> _links = [];

  bool get _editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final s = widget.existing;
    if (s != null) {
      _brandId = s.brandId;
      _types
        ..clear()
        ..addAll(s.type.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty));
      if (_types.isEmpty) _types.add('lifestyle');
      _date = DateTime.tryParse(s.date);
      if (s.startTime != null && s.startTime!.contains(':')) {
        final parts = s.startTime!.split(':');
        _hour = int.tryParse(parts[0]);
        _minute = int.tryParse(parts[1]);
      }
      if (s.endTime != null && s.endTime!.contains(':')) {
        final parts = s.endTime!.split(':');
        _endHour = int.tryParse(parts[0]);
        _endMinute = int.tryParse(parts[1]);
      }
      _title.text = s.title;
      _location.text = s.location ?? '';
      _location2.text = s.location2 ?? '';
      _notes.text = s.notes ?? '';
      _team.addAll(s.team.map((m) => m.id));
      _leadId = s.leadId;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    _location2.dispose();
    _notes.dispose();
    super.dispose();
  }

  static Color _parseColor(String? hex, [Color fallback = AppColors.arenaBlue]) {
    if (hex == null || hex.isEmpty) return fallback;
    var h = hex.replaceAll('#', '').trim();
    if (h.length == 6) h = 'FF$h';
    final v = int.tryParse(h, radix: 16);
    return v == null ? fallback : Color(v);
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _hour ?? 13, minute: _minute ?? 0),
    );
    if (t != null) setState(() {
      _hour = t.hour;
      _minute = t.minute;
    });
  }

  Future<void> _pickEndTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _endHour ?? (_hour ?? 15), minute: _endMinute ?? 0),
    );
    if (t != null) setState(() {
      _endHour = t.hour;
      _endMinute = t.minute;
    });
  }

  Future<void> _save() async {
    setState(() => _error = null);
    if (_brandId == null) {
      setState(() => _error = 'Pick a client.');
      return;
    }
    if (_date == null) {
      setState(() => _error = 'Pick a date.');
      return;
    }
    setState(() => _saving = true);
    try {
      final dateStr =
          '${_date!.year.toString().padLeft(4, '0')}-${_date!.month.toString().padLeft(2, '0')}-${_date!.day.toString().padLeft(2, '0')}';
      final timeStr = _hour != null
          ? '${_hour!.toString().padLeft(2, '0')}:${(_minute ?? 0).toString().padLeft(2, '0')}'
          : null;
      final endStr = _endHour != null
          ? '${_endHour!.toString().padLeft(2, '0')}:${(_endMinute ?? 0).toString().padLeft(2, '0')}'
          : null;
      final payload = {
        'brand_id': _brandId,
        'title': _title.text.trim().isEmpty ? null : _title.text.trim(),
        'type': _types.isEmpty ? 'lifestyle' : _types.join(','),
        'scheduled_date': dateStr,
        if (timeStr != null) 'start_time': timeStr,
        if (endStr != null) 'end_time': endStr,
        if (_location.text.trim().isNotEmpty) 'location': _location.text.trim(),
        if (_notes.text.trim().isNotEmpty) 'notes': _notes.text.trim(),
        'collaborators': _team.toList(),
        if (_leadId != null && _team.contains(_leadId)) 'lead_photographer_id': _leadId,
      };
      if (_editing) {
        await updateShoot(ref, widget.existing!.id, payload,
            files: _files, links: _links);
      } else {
        await createShoot(ref, payload, files: _files, links: _links);
      }
      if (!mounted) return;
      ref.invalidate(shootsProvider);
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_editing ? '✓ Shoot updated' : '✓ Added to Cuva')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Couldn’t save. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Attachments ────────────────────────────────────────────────────
  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickMultiImage();
    if (picked.isNotEmpty) {
      setState(() => _files.addAll(picked.map((x) => File(x.path))));
    }
  }

  Future<void> _pickFile() async {
    final res = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (res != null) {
      setState(() => _files.addAll(
          res.files.where((f) => f.path != null).map((f) => File(f.path!))));
    }
  }

  Future<void> _addLink() async {
    final ctrl = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add link'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(hintText: 'https://…'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Add')),
        ],
      ),
    );
    if (url != null && url.isNotEmpty) setState(() => _links.add(url));
  }

  Widget _attachmentsSection() {
    final existing = widget.existing?.attachments ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Attachments (optional)'),
        const SizedBox(height: 6),
        Row(children: [
          _attachBtn(Icons.image_outlined, 'Photo', _pickImage),
          const SizedBox(width: 8),
          _attachBtn(Icons.attach_file, 'File', _pickFile),
          const SizedBox(width: 8),
          _attachBtn(Icons.link, 'Link', _addLink),
        ]),
        if (existing.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final a in existing)
              _chip(
                  a.isLink
                      ? Icons.link
                      : (a.isImage ? Icons.image : Icons.insert_drive_file),
                  a.name ?? a.kind,
                  null),
          ]),
        ],
        if (_files.isNotEmpty || _links.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (var i = 0; i < _files.length; i++)
              _chip(
                  Icons.insert_drive_file,
                  _files[i].path.split(Platform.pathSeparator).last,
                  () => setState(() => _files.removeAt(i))),
            for (var i = 0; i < _links.length; i++)
              _chip(Icons.link, _links[i],
                  () => setState(() => _links.removeAt(i))),
          ]),
        ],
      ],
    );
  }

  Widget _attachBtn(IconData icon, String label, VoidCallback onTap) =>
      OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
      );

  Widget _chip(IconData icon, String label, VoidCallback? onRemove) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.appBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: AppColors.ink3),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: Text(label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12)),
          ),
          if (onRemove != null) ...[
            const SizedBox(width: 4),
            GestureDetector(
                onTap: onRemove,
                child: const Icon(Icons.close, size: 14, color: AppColors.ink3)),
          ],
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    final optsAsync = ref.watch(shootFormOptionsProvider);

    return Directionality(
      textDirection: TextDirection.ltr,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + viewInsets),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Icon(Icons.camera_alt, color: AppColors.arenaBlue),
                const SizedBox(width: 8),
                Text(_editing ? 'Edit shoot' : 'Add to Cuva',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.ink)),
                const Spacer(),
                if (_editing)
                  TextButton.icon(
                    onPressed: _saving ? null : _cancelShoot,
                    icon: const Icon(Icons.event_busy, size: 18, color: AppColors.arenaRed),
                    label: const Text('Cancel shoot',
                        style: TextStyle(color: AppColors.arenaRed, fontWeight: FontWeight.w600)),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            optsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (_, __) => const InlineErrorBanner(
                  message: 'Couldn’t load clients & team. Pull to retry.'),
              data: (opts) => _form(opts),
            ),
          ],
        ),
      ),
    );
  }

  Widget _form(ShootFormOptions opts) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _label('Client *'),
        const SizedBox(height: 6),
        _searchField('Search client…', (v) => setState(() => _brandQuery = v)),
        const SizedBox(height: 6),
        Container(
          constraints: const BoxConstraints(maxHeight: 150),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(10),
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(4),
            children: opts.brands
                .where((b) => _brandQuery.isEmpty || b.name.toLowerCase().contains(_brandQuery.toLowerCase()))
                .map((b) {
              final c = _parseColor(b.color);
              final sel = _brandId == b.id;
              return InkWell(
                onTap: () => setState(() => _brandId = b.id),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
                  child: Row(children: [
                    CircleAvatar(radius: 6, backgroundColor: c),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(b.name,
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: sel ? c : AppColors.ink))),
                    if (sel) Icon(Icons.check_circle, size: 17, color: c),
                  ]),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 14),
        // Type — one or more
        _label('Type (one or more)'),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: opts.types.map((t) {
            final on = _types.contains(t);
            return GestureDetector(
              onTap: () => setState(() => on ? _types.remove(t) : _types.add(t)),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: on ? AppColors.arenaBlue : Colors.white,
                  border: Border.all(color: on ? AppColors.arenaBlue : Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  t.isEmpty ? t : t[0].toUpperCase() + t.substring(1),
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: on ? Colors.white : AppColors.ink),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 14),
        // Date + Start + End
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.event, size: 16),
                label: Text(_date == null ? 'Date *' : '${_date!.day}/${_date!.month}',
                    overflow: TextOverflow.ellipsis),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: _pickTime,
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                child: Text(_hour == null ? 'Start' : _ampm(_hour!, _minute ?? 0),
                    overflow: TextOverflow.ellipsis),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: _pickEndTime,
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                child: Text(_endHour == null ? 'End' : _ampm(_endHour!, _endMinute ?? 0),
                    overflow: TextOverflow.ellipsis),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _location,
          decoration: const InputDecoration(
            labelText: 'Location', border: OutlineInputBorder(), prefixIcon: Icon(Icons.place_outlined)),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _title,
          decoration: const InputDecoration(
            labelText: 'Title (optional)', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _notes,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Notes (optional)', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 14),
        _attachmentsSection(),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _label('Crew on set')),
          const Text('tap ★ for lead', style: TextStyle(fontSize: 11, color: AppColors.ink3)),
        ]),
        const SizedBox(height: 6),
        // selected chips
        if (_team.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: opts.team.where((m) => _team.contains(m.id)).map((m) {
                final lead = _leadId == m.id;
                return Container(
                  padding: const EdgeInsets.only(left: 6, right: 2, top: 2, bottom: 2),
                  decoration: BoxDecoration(color: AppColors.arenaBlueLight, borderRadius: BorderRadius.circular(16)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    GestureDetector(
                      onTap: () => setState(() => _leadId = m.id),
                      child: Icon(Icons.star, size: 15, color: lead ? const Color(0xFFF59E0B) : const Color(0xFF9AA8FF)),
                    ),
                    const SizedBox(width: 3),
                    Text(m.name.split(' ').first,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.arenaBlue)),
                    IconButton(
                      icon: const Icon(Icons.close, size: 14, color: AppColors.arenaBlue),
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                      padding: EdgeInsets.zero,
                      onPressed: () => setState(() {
                        _team.remove(m.id);
                        if (_leadId == m.id) _leadId = _team.isEmpty ? null : _team.first;
                      }),
                    ),
                  ]),
                );
              }).toList(),
            ),
          ),
        _searchField('Search crew…', (v) => setState(() => _crewQuery = v)),
        const SizedBox(height: 6),
        Container(
          constraints: const BoxConstraints(maxHeight: 190),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(10),
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(4),
            children: opts.team
                .where((m) => _crewQuery.isEmpty ||
                    ('${m.name} ${m.jobTitle ?? ''}').toLowerCase().contains(_crewQuery.toLowerCase()))
                .map((m) {
              final sel = _team.contains(m.id);
              return InkWell(
                onTap: () => setState(() {
                  if (sel) {
                    _team.remove(m.id);
                    if (_leadId == m.id) _leadId = _team.isEmpty ? null : _team.first;
                  } else {
                    _team.add(m.id);
                    _leadId ??= m.id;
                  }
                }),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Row(children: [
                    Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: sel ? AppColors.arenaBlue : Colors.transparent,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: sel ? AppColors.arenaBlue : Colors.grey.shade400),
                      ),
                      child: sel ? const Icon(Icons.check, size: 13, color: Colors.white) : null,
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(m.name, style: const TextStyle(fontSize: 13, color: AppColors.ink, fontWeight: FontWeight.w500))),
                    if (m.jobTitle != null)
                      Text(m.jobTitle!, style: const TextStyle(fontSize: 10.5, color: AppColors.ink3)),
                  ]),
                ),
              );
            }).toList(),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 14),
          InlineErrorBanner(message: _error!),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.arenaBlue,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)))
              : Icon(_editing ? Icons.check : Icons.add, color: Colors.white),
          label: Text(_editing ? 'Save changes' : 'Add to Cuva',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }

  Future<void> _cancelShoot() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel this shoot?'),
        content: const Text('The team will no longer see it on the calendar.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep it')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.arenaRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel shoot'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _saving = true);
    try {
      await cancelShoot(ref, widget.existing!.id);
      if (!mounted) return;
      ref.invalidate(shootsProvider);
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Shoot cancelled')),
      );
    } catch (_) {
      if (mounted) setState(() {
        _saving = false;
        _error = 'Couldn’t cancel. Try again.';
      });
    }
  }

  Widget _label(String t) => Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(t,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ink2)),
      );

  Widget _searchField(String hint, ValueChanged<String> onChanged) => SizedBox(
        height: 40,
        child: TextField(
          onChanged: onChanged,
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: const Icon(Icons.search, size: 18),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      );

  /// 14, 30 → "2:30 PM"
  static String _ampm(int h, int m) {
    final ap = h >= 12 ? 'PM' : 'AM';
    var hh = h % 12;
    if (hh == 0) hh = 12;
    return '$hh:${m.toString().padLeft(2, '0')} $ap';
  }
}
