import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/errors/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimens.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/inline_error_banner.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../../features/auth/presentation/controllers/auth_controller.dart';
import '../../../../features/tasks/presentation/controllers/tasks_providers.dart';
import '../../data/models/message_model.dart';

/// Bottom sheet for "Long-press a chat message → Add task".
///
/// Pre-fills:
///   - Title  : first 80 chars of the message body
///   - Description : full message body
///   - Brand  : current chat's brand (locked, shown as a chip)
///   - Assignees : auto-selected from any @mentions in the body. Empty if
///                 the message had no mentions — user picks via the search
///                 picker below.
///   - Department : creator's department (falls back to "Account Management")
///   - Priority : medium
///
/// On submit it creates ONE task per assignee via the tasks API, all linked
/// to the source message so the chat shows the task card automatically.
class CreateTaskFromMessageSheet extends ConsumerStatefulWidget {
  /// Null → standalone "Add Task" (opened from the Tasks page, not a chat).
  final MessageModel? sourceMessage;

  /// Null → standalone: the assignee pool is EVERY active employee, not a group.
  final int? groupId;
  /// The current chat's brand (null when opened from a private/DM chat).
  final int? initialBrandId;
  /// True when opened inside a 1-on-1 DM — defaults the brand picker to
  /// "Private" and lets the user optionally pick a brand instead.
  final bool isDirectChat;
  /// True when opened inside a CUSTOM (brainstorming) group — the brand
  /// picker is shown WITHOUT a "Private" option (a brand is mandatory).
  final bool requireBrand;
  /// Pre-select this user as an assignee (e.g. when opened by tapping their
  /// name in the chat). Added on top of any @mention-derived assignees.
  final int? initialAssigneeId;

  const CreateTaskFromMessageSheet({
    super.key,
    this.sourceMessage,
    this.groupId,
    this.initialBrandId,
    this.isDirectChat = false,
    this.requireBrand = false,
    this.initialAssigneeId,
  });

  static Future<bool?> show(
    BuildContext context, {
    MessageModel? sourceMessage,
    int? groupId,
    int? initialBrandId,
    bool isDirectChat = false,
    bool requireBrand = false,
    int? initialAssigneeId,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: AppRadius.sheetTop,
      ),
      builder: (_) => CreateTaskFromMessageSheet(
        sourceMessage: sourceMessage,
        groupId: groupId,
        // Standalone (no chat) → a brand/client is mandatory.
        initialBrandId: initialBrandId,
        isDirectChat: isDirectChat,
        requireBrand: requireBrand || (sourceMessage == null && !isDirectChat),
        initialAssigneeId: initialAssigneeId,
      ),
    );
  }

  @override
  ConsumerState<CreateTaskFromMessageSheet> createState() =>
      _CreateTaskFromMessageSheetState();
}

class _CreateTaskFromMessageSheetState
    extends ConsumerState<CreateTaskFromMessageSheet> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _searchCtrl;
  late final TextEditingController _linkCtrl;
  DateTime? _dueAt;        // date portion (year/month/day only)
  int? _dueHour;           // 0-23 — picked from dropdown menu
  String _priority = 'medium';
  bool _saving = false;
  String? _error;          // shown as a visible banner inside the sheet

  // UI polish (matches desktop): collapsible time grid + deliverables, and a
  // real upload progress bar wired to Dio's onSendProgress during save.
  bool _showTime = false;
  bool _showDeliv = false;
  bool _uploading = false;
  double _uploadPct = 0;

  List<Map<String, dynamic>> _allMembers = const [];
  bool _loadingMembers = true;
  final Set<int> _selectedAssigneeIds = {};
  String _searchQuery = '';

  // Brand picker (private chat only). "Private" and brands are mutually
  // exclusive: pick Private (→ this DM) OR one/more brands (→ each brand group).
  List<Map<String, dynamic>> _brands = const [];
  final Set<int> _selectedBrandIds = {};
  bool _private = false;

  // Attachments + links picked in the sheet (Sprint I.2).
  final List<File> _attachedFiles = [];
  final List<String> _attachedLinks = [];

  // Specific deliverables (quantified task): [{type, qty, done:0}]
  final List<Map<String, dynamic>> _deliverables = [];
  String _delivType = '';
  int _delivQty = 1;
  // Per-row quantity in the checklist UI (keyed by deliverable type key).
  final Map<String, int> _rowQty = {};
  // Role-aware deliverable types pulled from /tasks/form-config for the FIRST
  // selected assignee — each = {key, label}. Changes with the chosen person.
  List<Map<String, dynamic>> _delivTypes = const [];
  String _roleLabel = '';
  bool _loadingForm = false;
  static final List<Map<String, dynamic>> _fallbackDelivTypes = [
    {'key': 'post', 'label': 'Post'},
    {'key': 'story', 'label': 'Story'},
    {'key': 'reel', 'label': 'Reel'},
    {'key': 'design', 'label': 'Design'},
    {'key': 'other', 'label': 'Other'},
  ];

  // Deadline sockets for the first assignee on the picked date — fetched from
  // /tasks/available-slots. Each = {hour, available, reason}. Booked / past
  // hours come back available:false and render disabled.
  List<Map<String, dynamic>> _slots = const [];
  bool _loadingSlots = false;

  int? get _firstAssigneeId =>
      _selectedAssigneeIds.isEmpty ? null : _selectedAssigneeIds.first;

  /// Reload the role-aware form config + deadline sockets whenever the chosen
  /// assignees change (the FIRST assignee drives both).
  void _onAssigneesChanged() {
    _loadFormConfig();
    _loadSlots();
  }

  /// Canonical role key → readable English (e.g. 'account_mgmt' → 'Account
  /// Mgmt', 'web' → 'Web'). Used for the deliverables section label.
  String _prettyRole(String key) {
    if (key.isEmpty || key == 'general') return '';
    return key
        .replaceAll('_', ' ')
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  Future<void> _loadFormConfig() async {
    final aid = _firstAssigneeId;
    if (aid == null) {
      if (mounted) setState(() { _delivTypes = const []; _roleLabel = ''; });
      return;
    }
    if (mounted) setState(() => _loadingForm = true);
    try {
      final repo = ref.read(tasksRepositoryProvider);
      final cfg = await repo.taskFormConfig(assigneeId: aid);
      final types = (cfg['deliverable_types'] as List<dynamic>? ?? const [])
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList();
      if (!mounted) return;
      setState(() {
        _delivTypes = types.isNotEmpty ? types : _fallbackDelivTypes;
        // English role label from the canonical key (e.g. 'account_mgmt' →
        // 'Account Mgmt'), NOT the Arabic role_label.
        _roleLabel = _prettyRole((cfg['role'] as String?) ?? '');
        if (_delivTypes.isNotEmpty &&
            !_delivTypes.any((d) => d['key'] == _delivType)) {
          _delivType = _delivTypes.first['key'] as String;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        if (_delivTypes.isEmpty) {
          _delivTypes = _fallbackDelivTypes;
          _delivType = _delivTypes.first['key'] as String;
        }
      });
    } finally {
      if (mounted) setState(() => _loadingForm = false);
    }
  }

  Future<void> _loadSlots() async {
    final aid = _firstAssigneeId;
    if (aid == null || _dueAt == null) {
      if (mounted) setState(() => _slots = const []);
      return;
    }
    if (mounted) setState(() => _loadingSlots = true);
    try {
      final repo = ref.read(tasksRepositoryProvider);
      final d = _dueAt!;
      final date = '${d.year.toString().padLeft(4, '0')}-'
          '${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';
      final slots = await repo.taskAvailableSlots(assigneeId: aid, date: date);
      if (!mounted) return;
      setState(() {
        _slots = slots;
        if (_dueHour != null && !_isHourAvailable(_dueHour!)) _dueHour = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _slots = const []); // fall back to free hours
    } finally {
      if (mounted) setState(() => _loadingSlots = false);
    }
  }

  bool _isHourAvailable(int h) {
    if (_slots.isEmpty) return true; // no data yet → allow
    for (final s in _slots) {
      if ((s['hour'] as num?)?.toInt() == h) return s['available'] == true;
    }
    return false; // outside the socket range → not selectable
  }

  /// Hours to render when the server slots haven't loaded (10 AM–9 PM, all open).
  List<Map<String, dynamic>> _fallbackSlots() =>
      [for (var h = 10; h <= 21; h++) {'hour': h, 'available': true}];

  void _addDeliverable() {
    if (_delivType.isEmpty) return; // no role loaded yet
    final existing = _deliverables.indexWhere((d) => d['type'] == _delivType);
    setState(() {
      if (existing >= 0) {
        _deliverables[existing]['qty'] =
            (_deliverables[existing]['qty'] as int) + _delivQty;
      } else {
        _deliverables.add({'type': _delivType, 'qty': _delivQty, 'done': 0});
      }
      _delivQty = 1;
    });
  }

  /// Checklist "Add": add (or update to) the row's chosen quantity.
  void _addDeliverableType(String type) {
    final qty = _rowQty[type] ?? 1;
    setState(() {
      final i = _deliverables.indexWhere((d) => d['type'] == type);
      if (i >= 0) {
        _deliverables[i]['qty'] = qty;
      } else {
        _deliverables.add({'type': type, 'qty': qty, 'done': 0});
      }
    });
  }

  void _removeDeliverableType(String type) {
    setState(() => _deliverables.removeWhere((d) => d['type'] == type));
  }

  String _delivLabel(String t) {
    for (final d in _delivTypes) {
      if (d['key'] == t) return (d['label'] as String?) ?? t;
    }
    return t
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  @override
  void initState() {
    super.initState();
    final body = (widget.sourceMessage?.body ?? '').trim();
    // Sprint P.4 — strip every @mention before using the body as the
    // task title (the assignee picker captures who was mentioned, so we
    // don't want the title to repeat their handles).
    final cleanTitleSrc = _stripMentions(body).trim();
    final title = cleanTitleSrc.length > 200
        ? cleanTitleSrc.substring(0, 200)
        : cleanTitleSrc;
    _titleCtrl = TextEditingController(text: title);
    // Description starts empty — the message body already became the title,
    // so we don't repeat it here (matches the desktop task creator).
    _descCtrl = TextEditingController();
    _searchCtrl = TextEditingController();
    _linkCtrl = TextEditingController();

    // Pre-select the tapped person (from "Add task" on a name) so the form
    // opens with them already chosen as assignee.
    if (widget.initialAssigneeId != null) {
      _selectedAssigneeIds.add(widget.initialAssigneeId!);
    }
    // A real brand chat targets that brand (no picker). A private chat starts
    // with NOTHING selected — the user must explicitly pick Private or brands.
    if (!widget.isDirectChat && widget.initialBrandId != null) {
      _selectedBrandIds.add(widget.initialBrandId!);
    }
    _loadMembers();
    _loadBrands();
    // Pull role-aware deliverables for any pre-selected assignee right away.
    if (_selectedAssigneeIds.isNotEmpty) _loadFormConfig();
  }

  /// Standalone Add Task = no source message AND no host group. It must show
  /// ONLY the user's own brands (a manager can't assign onto a brand that isn't
  /// theirs). Custom brainstorming rooms (requireBrand + a groupId) still load
  /// every client.
  bool get _isStandalone => widget.sourceMessage == null && widget.groupId == null;

  Future<void> _loadBrands() async {
    try {
      final repo = ref.read(tasksRepositoryProvider);
      // Load ALL brands only for custom rooms; standalone + DM load MY brands.
      final loadAll = widget.requireBrand && !_isStandalone;
      final brands = await repo.listMyBrands(all: loadAll);
      // Hide the sentinel brands from the picker.
      final filtered = brands
          .where((b) =>
              (b['slug'] as String?) != 'direct-messages' &&
              (b['slug'] as String?) != 'custom-groups',)
          .toList();
      if (mounted) setState(() => _brands = filtered);
    } catch (_) {
      // Non-fatal — the picker just stays empty (Private only).
    }
  }

  static Color? _parseBrandColor(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    var h = hex.replaceAll('#', '').trim();
    if (h.length == 6) h = 'FF$h';
    if (h.length != 8) return null;
    final v = int.tryParse(h, radix: 16);
    return v == null ? null : Color(v);
  }

  /// A single brand/Private pill matching the My-To-Do slider: coloured avatar
  /// + name + a check when active; unselected pills dim out.
  Widget _brandSliderPill({
    required String label,
    required Color color,
    IconData? icon,
    String? initial,
    String? logoUrl,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: selected ? 1 : 0.4,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.15) : Colors.white,
            borderRadius: AppRadius.rLg,
            border: Border.all(
              color: selected ? color : Colors.grey.shade300,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Brand LOGO when available, else colored initial / icon.
              (logoUrl != null && logoUrl.isNotEmpty)
                  ? ClipOval(
                      child: Image.network(logoUrl,
                          width: 18, height: 18, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => CircleAvatar(
                                radius: 9,
                                backgroundColor: color,
                                child: Text(initial ?? '?',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,),),
                              ),),
                    )
                  : CircleAvatar(
                      radius: 9,
                      backgroundColor: color,
                      child: icon != null
                          ? Icon(icon, size: 11, color: Colors.white)
                          : Text(
                              initial ?? '?',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,),
                            ),
                    ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: selected ? color : AppColors.ink2,
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 5),
                Icon(Icons.check_circle, size: 14, color: color),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Removes every `@Name` token from a string while keeping the
  /// surrounding text + collapsing the double spaces left behind.
  String _stripMentions(String src) {
    if (src.isEmpty || _allMembers.isEmpty) {
      // Fallback: strip anything that looks like "@Word Word" greedy-once.
      return src
          .replaceAll(RegExp(r'@[A-Za-z؀-ۿ]+(\s+[A-Za-z؀-ۿ]+)?'), '')
          .replaceAll(RegExp(r'\s{2,}'), ' ')
          .trim();
    }
    var out = src;
    for (final m in _allMembers) {
      final name = (m['name'] as String? ?? '').trim();
      if (name.isEmpty) continue;
      // Case-insensitive replace of `@<name>` — exact match on the longest
      // names first to avoid stripping "@Ahmed" when "@Ahmed Gamal" was meant.
      out = out.replaceAll(
        RegExp('@${RegExp.escape(name)}', caseSensitive: false),
        '',
      );
    }
    return out.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  }

  Future<void> _loadMembers() async {
    try {
      final repo = ref.read(tasksRepositoryProvider);
      // Standalone (no group) → every active employee is assignable.
      final list = widget.groupId != null
          ? await repo.listGroupUsers(widget.groupId!)
          : await repo.listUsers();
      if (!mounted) return;
      setState(() {
        _allMembers = list;
        _loadingMembers = false;
        _preselectMentions();
        // Now that we know who's in the group, re-clean the title using
        // EXACT member names (more accurate than the regex fallback).
        final cleaned = _stripMentions(widget.sourceMessage?.body ?? '').trim();
        _titleCtrl.text =
            cleaned.length > 80 ? cleaned.substring(0, 80) : cleaned;
      });
      // Mentions may have just added assignees → refresh role deliverables.
      if (_selectedAssigneeIds.isNotEmpty) _loadFormConfig();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMembers = false);
    }
  }

  /// Sprint P.4 — robust mention preselection. Instead of greedy-matching a
  /// regex across the body, we iterate over EVERY group member and check if
  /// `@<their_name>` appears in the message (case-insensitive). This picks
  /// up all the right people and never confuses "@Ahmed Gamal" with another
  /// "Ahmed" — the longest name still wins thanks to exact substring match.
  void _preselectMentions() {
    final body = widget.sourceMessage?.body ?? '';
    if (body.isEmpty || _allMembers.isEmpty) return;

    final lowerBody = body.toLowerCase();

    // "@All" / "@everyone" → assign the whole team.
    if (RegExp(r'@(all|everyone|الكل)\b', caseSensitive: false)
        .hasMatch(lowerBody)) {
      for (final mem in _allMembers) {
        _selectedAssigneeIds.add((mem['id'] as num).toInt());
      }
      return;
    }
    // Sort by name length DESC so we match longer names first ("Ahmed
    // Gamal") before shorter ones ("Ahmed") — prevents false positives.
    final byNameLen = List<Map<String, dynamic>>.from(_allMembers)
      ..sort((a, b) {
        final lenA = (a['name'] as String? ?? '').length;
        final lenB = (b['name'] as String? ?? '').length;
        return lenB.compareTo(lenA);
      });
    final consumed = StringBuffer(lowerBody);
    for (final mem in byNameLen) {
      final name = (mem['name'] as String? ?? '').trim();
      if (name.isEmpty) continue;
      final token = '@${name.toLowerCase()}';
      if (consumed.toString().contains(token)) {
        _selectedAssigneeIds.add((mem['id'] as num).toInt());
        // Blank out the matched token so a sub-match of a shorter name
        // (e.g. "@Ahmed" inside "@Ahmed Gamal") doesn't double-pick.
        final replaced = consumed.toString().replaceAll(token, ' ' * token.length);
        consumed
          ..clear()
          ..write(replaced);
      }
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _searchCtrl.dispose();
    _linkCtrl.dispose();
    super.dispose();
  }

  // ─── Attachments + links pickers ───────────────────────────────────

  Future<void> _pickImages() async {
    final picker = ImagePicker();
    final picked = await picker.pickMultiImage();
    if (picked.isEmpty) return;
    setState(() {
      for (final x in picked) {
        _attachedFiles.add(File(x.path));
      }
    });
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result == null) return;
    setState(() {
      for (final f in result.files) {
        if (f.path != null) _attachedFiles.add(File(f.path!));
      }
    });
  }

  void _addLink() {
    final raw = _linkCtrl.text.trim();
    if (raw.isEmpty) return;
    if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(raw)) {
      _toast('Link must start with http:// or https://');
      return;
    }
    setState(() {
      _attachedLinks.add(raw);
      _linkCtrl.clear();
    });
  }

  String _dueLabel(DateTime? d) {
    if (d == null) return 'No due date';
    return '${d.day}/${d.month}/${d.year}';
  }

  /// Display "12 AM", "1 PM", "11 PM" etc. for the hour dropdown.
  String _hourLabel(int h) {
    final suffix = h < 12 ? 'AM' : 'PM';
    final h12 = h == 0 ? 12 : (h <= 12 ? h : h - 12);
    return '$h12:00 $suffix';
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueAt ?? now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _dueAt = picked);
      _loadSlots(); // refresh which hours are still open for this assignee
    }
  }

  /// Combine the picked date + hour into a single DateTime to send to the
  /// API. Defaults to 23:59 if a date is set but no hour was chosen.
  DateTime? _combinedDueAt() {
    if (_dueAt == null) return null;
    final h = _dueHour ?? 23;
    final m = _dueHour == null ? 59 : 0;
    return DateTime(_dueAt!.year, _dueAt!.month, _dueAt!.day, h, m);
  }

  Future<void> _save() async {
    setState(() => _error = null);
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Please enter a task title.');
      return;
    }
    if (_selectedAssigneeIds.isEmpty) {
      setState(() => _error = 'Please choose at least one assignee.');
      return;
    }
    // Deadline is mandatory — both a date AND an hour must be picked.
    if (_dueAt == null) {
      setState(() => _error = 'Please pick a deadline date.');
      return;
    }
    if (_dueHour == null) {
      setState(() => _error = 'Please pick a deadline time.');
      return;
    }
    // Where the task(s) go: [null] = Private (this chat), or one entry per brand.
    final List<int?> brandTargets =
        _private ? <int?>[null] : _selectedBrandIds.map<int?>((e) => e).toList();
    if (brandTargets.isEmpty) {
      setState(() => _error = widget.requireBrand
          ? 'Pick a client (brand) for this task.'
          : 'Please pick “Private” or at least one brand.',);
      return;
    }
    setState(() {
      _saving = true;
      _uploading = _attachedFiles.isNotEmpty;
      _uploadPct = 0;
    });
    try {
      final repo = ref.read(tasksRepositoryProvider);
      final me = ref.read(authControllerProvider).valueOrNull;
      final dept = me?.department?.trim().isNotEmpty == true
          ? me!.department!
          : 'Account Management';
      // Fan out: one set of tasks per chosen brand (or a single Private set).
      for (final brandId in brandTargets) {
        await repo.createTasksFromMessage(
          brandId: brandId,
          sourceMessageId: widget.sourceMessage?.id,
          assigneeIds: _selectedAssigneeIds.toList(),
          title: title,
          description:
              _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
          department: dept,
          dueAt: _combinedDueAt(),
          priority: _priority,
          attachments: _attachedFiles,
          links: _attachedLinks,
          deliverables: _deliverables,
          onProgress: (pct) {
            if (mounted) setState(() => _uploadPct = pct);
          },
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
      _toast('✓ Task created');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _friendlyError(e));
    } finally {
      if (mounted) setState(() { _saving = false; _uploading = false; });
    }
  }

  /// Turn a raw exception into a short, user-facing sentence. For validation
  /// (422) errors we surface the ACTUAL field message from the server so the
  /// user knows exactly what to fix instead of a generic "review and try".
  String _friendlyError(Object e) {
    if (e is ApiException) {
      // Prefer the first per-field validation message.
      final ve = e.validationErrors;
      if (ve != null && ve.isNotEmpty) {
        final first = ve.values.firstWhere(
            (l) => l.isNotEmpty, orElse: () => const <String>[],);
        if (first.isNotEmpty) return first.first;
      }
      if (e.message.trim().isNotEmpty &&
          e.message != 'An unexpected error occurred') {
        return e.message;
      }
      if (e.isValidationError) {
        return 'Some details are missing or invalid. Please review and try again.';
      }
    }
    final s = e.toString();
    if (s.contains('SocketException') || s.contains('Connection')) {
      return 'No connection. Check your internet and try again.';
    }
    return 'Couldn’t create the task. Please try again.';
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  List<Map<String, dynamic>> get _filteredMembers {
    if (_searchQuery.trim().isEmpty) return _allMembers;
    final q = _searchQuery.toLowerCase().trim();
    return _allMembers.where((m) {
      final name = (m['name'] as String? ?? '').toLowerCase();
      final email = (m['email'] as String? ?? '').toLowerCase();
      return name.contains(q) || email.contains(q);
    }).toList();
  }

  // ─────────────────────── UI helpers (desktop parity) ────────────────
  Widget _fieldLabel(String text, {bool required = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          Text(text,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,),),
          if (required)
            const Text(' *',
                style: TextStyle(
                    fontSize: 13,
                    color: AppColors.arenaRed,
                    fontWeight: FontWeight.w700,),),
        ],),
      );

  InputDecoration _filledDec(String hint) => InputDecoration(
        hintText: hint,
        isDense: true,
        filled: true,
        fillColor: const Color(0xFFF9FAFB),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        enabledBorder: OutlineInputBorder(
            borderRadius: AppRadius.rSm,
            borderSide: BorderSide(color: Colors.grey.shade300),),
        focusedBorder: OutlineInputBorder(
            borderRadius: AppRadius.rSm,
            borderSide: const BorderSide(color: AppColors.arenaBlue, width: 1.5),),
        border: OutlineInputBorder(borderRadius: AppRadius.rSm),
      );

  /// Section header with a top divider + icon, matching the desktop layout.
  Widget _sectionHeader(IconData icon, String title, {Widget? trailing}) =>
      Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 12),
        child: Column(children: [
          Container(height: 1, color: AppColors.border),
          const SizedBox(height: 14),
          Row(children: [
            Icon(icon, size: 16, color: AppColors.ink3),
            AppSpacing.hSm,
            Text(title,
                style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,),),
            if (trailing != null) ...[const Spacer(), trailing],
          ],),
        ],),
      );

  Widget _initialDot(String label, Color c) => Container(
        width: 20,
        height: 20,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: c, shape: BoxShape.circle),
        child: Text(label.isNotEmpty ? label.characters.first.toUpperCase() : '?',
            style: const TextStyle(
                color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700,),),
      );

  /// Brand/Private pill matching desktop: solid blue + white check when
  /// selected, white with logo/initial when not.
  Widget _brandPill({
    required String label,
    String? logoUrl,
    Color? color,
    IconData? icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final c = color ?? AppColors.arenaBlue;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.only(left: 5, right: 12, top: 5, bottom: 5),
        decoration: BoxDecoration(
          color: selected ? AppColors.arenaBlue : Colors.white,
          borderRadius: AppRadius.rLg,
          border: Border.all(
              color: selected ? AppColors.arenaBlue : Colors.grey.shade300,
              width: selected ? 1.5 : 1,),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (selected)
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.28), shape: BoxShape.circle,),
              child: const Icon(Icons.check, size: 13, color: Colors.white),
            )
          else if (logoUrl != null && logoUrl.isNotEmpty)
            ClipOval(
                child: Image.network(logoUrl,
                    width: 20,
                    height: 20,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _initialDot(label, c),),)
          else if (icon != null)
            Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                child: Icon(icon, size: 12, color: Colors.white),)
          else
            _initialDot(label, c),
          const SizedBox(width: 7),
          Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : AppColors.ink2,),),
        ],),
      ),
    );
  }

  /// Compact dashed drop-zone button (image / file pickers).
  Widget _dropZone(
          {required IconData icon,
          required String label,
          required VoidCallback onTap,}) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          height: 64,
          decoration: BoxDecoration(
            color: const Color(0xFFF9FAFB),
            borderRadius: AppRadius.rSm,
            border: Border.all(
                color: Colors.grey.shade300,
                style: BorderStyle.solid,
                width: 1,),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: AppColors.ink3),
              const SizedBox(height: 2),
              Text(label,
                  style: const TextStyle(fontSize: 11.5, color: AppColors.ink2),),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + viewInsets),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // grab handle
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
            AppSpacing.vLg,
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppColors.arenaBlue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(Icons.add_task,
                      color: AppColors.arenaBlue, size: 19,),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Create task from message',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ],
            ),
            AppSpacing.vLg,

            // ═══ Section 1 — main fields, in a card (matches desktop) ═══
            AppCard(
              margin: EdgeInsets.zero,
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Title ──
                  _fieldLabel('Title', required: true),
                  TextField(
                    controller: _titleCtrl,
                    maxLines: 2,
                    minLines: 1,
                    decoration: _filledDec('Task title'),
                  ),
                  const SizedBox(height: 14),

                  // ── Details ──
                  _fieldLabel('Details'),
                  TextField(
                    controller: _descCtrl,
                    maxLines: 4,
                    minLines: 3,
                    decoration: _filledDec('Add more context (optional)'),
                  ),
                  AppSpacing.vLg,

                  // ── Assign to ──
                  _fieldLabel('Assign to', required: true),
                  TextField(
                    controller: _searchCtrl,
                    decoration: _filledDec('Search a teammate…').copyWith(
                      prefixIcon: const Icon(Icons.search, size: 18),
                      suffixIcon: _searchQuery.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close, size: 16),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() => _searchQuery = '');
                              },
                            ),
                    ),
                    onChanged: (v) => setState(() => _searchQuery = v),
                  ),
                  if (_selectedAssigneeIds.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final m in _allMembers.where((m) =>
                              _selectedAssigneeIds
                                  .contains((m['id'] as num).toInt()),))
                            Builder(builder: (_) {
                              final id = (m['id'] as num).toInt();
                              final name = (m['name'] as String?) ?? '?';
                              return Container(
                                padding: const EdgeInsets.only(
                                    left: 3, right: 6, top: 3, bottom: 3,),
                                decoration: BoxDecoration(
                                  color: AppColors.arenaBlue.withValues(alpha: 0.10),
                                  borderRadius: AppRadius.rLg,
                                  border: Border.all(
                                      color:
                                          AppColors.arenaBlue.withValues(alpha: 0.3),),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    UserAvatar(
                                        name: name,
                                        size: 20,
                                        backgroundColor: AppColors.arenaBlue,),
                                    const SizedBox(width: 5),
                                    Text(name,
                                        style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.arenaBlue,),),
                                    const SizedBox(width: 3),
                                    GestureDetector(
                                      onTap: () {
                                        setState(() =>
                                            _selectedAssigneeIds.remove(id),);
                                        _onAssigneesChanged();
                                      },
                                      child: const Icon(Icons.close,
                                          size: 14, color: AppColors.arenaBlue,),
                                    ),
                                  ],
                                ),
                              );
                            },),
                        ],
                      ),
                    ),
                  // Results appear ONLY after typing 3+ letters (desktop
                  // parity) — keeps the form short instead of a long list.
                  if (_loadingMembers)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Center(
                        child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),),
                      ),
                    )
                  else if (_searchQuery.trim().length >= 3)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: SizedBox(
                        height: 240,
                        child: _MemberPickerList(
                          members: _filteredMembers,
                          selectedIds: _selectedAssigneeIds,
                          onToggle: (id) {
                            setState(() {
                              if (_selectedAssigneeIds.contains(id)) {
                                _selectedAssigneeIds.remove(id);
                              } else {
                                _selectedAssigneeIds.add(id);
                                // Picked → clear the search so the box empties
                                // and the results collapse (same as pressing ✕);
                                // the chosen person shows in the chips above.
                                _searchCtrl.clear();
                                _searchQuery = '';
                              }
                            });
                            _onAssigneesChanged();
                          },
                        ),
                      ),
                    )
                  else if (_searchQuery.trim().isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 8, left: 2),
                      child: Text('Type at least 3 letters…',
                          style:
                              TextStyle(fontSize: 11.5, color: AppColors.ink3),),
                    ),

                  // ── Brand (DM, custom rooms, or standalone Add Task) ──
                  if (widget.isDirectChat || widget.requireBrand) ...[
                    AppSpacing.vLg,
                    _fieldLabel(
                        widget.requireBrand
                            ? 'Client / Brand'
                            : 'Client / Brand · optional',
                        required: widget.requireBrand,),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (!widget.requireBrand)
                          _brandPill(
                            label: 'Private',
                            icon: Icons.lock,
                            color: AppColors.ink3,
                            selected: _private,
                            onTap: () => setState(() {
                              _private = true;
                              _selectedBrandIds.clear();
                            }),
                          ),
                        for (final b in _brands)
                          Builder(builder: (_) {
                            final id = (b['id'] as num).toInt();
                            final name = (b['name'] as String?) ?? 'Brand';
                            final color = _parseBrandColor(
                                    b['primary_color'] as String?,) ??
                                AppColors.arenaBlue;
                            return _brandPill(
                              label: name,
                              logoUrl: b['logo_url'] as String?,
                              color: color,
                              selected: _selectedBrandIds.contains(id),
                              onTap: () => setState(() {
                                _private = false;
                                if (_selectedBrandIds.contains(id)) {
                                  _selectedBrandIds.remove(id);
                                } else {
                                  _selectedBrandIds.add(id);
                                }
                              }),
                            );
                          },),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        _private
                            ? 'Posts in this private chat'
                            : _selectedBrandIds.isEmpty
                                ? (widget.requireBrand
                                    ? 'Pick a client (brand) for this task'
                                    : 'Pick “Private” or one/more brands')
                                : 'Posts to ${_selectedBrandIds.length} brand group(s)',
                        style:
                            const TextStyle(fontSize: 11, color: AppColors.ink3),
                      ),
                    ),
                  ],

                  // ── Deadline (after an assignee is chosen) ──
                  if (_selectedAssigneeIds.isNotEmpty) ...[
                    AppSpacing.vLg,
                    _fieldLabel('Deadline', required: true),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _pickDate,
                            icon: const Icon(Icons.event, size: 18),
                            label: Text(_dueLabel(_dueAt),
                                overflow: TextOverflow.ellipsis,),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 13,),
                              alignment: Alignment.centerLeft,
                              side: BorderSide(color: Colors.grey.shade300),
                            ),
                          ),
                        ),
                        if (_dueAt != null) ...[
                          AppSpacing.hSm,
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () =>
                                  setState(() => _showTime = !_showTime),
                              icon: Icon(Icons.schedule,
                                  size: 18,
                                  color: _dueHour != null
                                      ? AppColors.arenaBlue
                                      : null,),
                              label: Text(
                                _dueHour != null
                                    ? _hourLabel(_dueHour!)
                                    : 'Pick time',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: _dueHour != null
                                        ? AppColors.arenaBlue
                                        : null,
                                    fontWeight: _dueHour != null
                                        ? FontWeight.w700
                                        : FontWeight.w500,),
                              ),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 13,),
                                alignment: Alignment.centerLeft,
                                side: BorderSide(
                                    color: _dueHour != null
                                        ? AppColors.arenaBlue
                                        : Colors.grey.shade300,),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (_dueAt != null && _showTime) ...[
                      AppSpacing.vSm,
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF9FAFB),
                          borderRadius: AppRadius.rSm,
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_loadingSlots)
                              const Padding(
                                padding: EdgeInsets.only(bottom: 8),
                                child: SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,),),
                              ),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                for (final s in (_slots.isNotEmpty
                                    ? _slots
                                    : _fallbackSlots()))
                                  Builder(builder: (_) {
                                    final h = (s['hour'] as num).toInt();
                                    final avail = s['available'] == true;
                                    final sel = _dueHour == h;
                                    return GestureDetector(
                                      onTap: avail
                                          ? () => setState(() {
                                                _dueHour = sel ? null : h;
                                                _showTime = false;
                                              })
                                          : null,
                                      child: Container(
                                        width: 52,
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 9,),
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: sel
                                              ? AppColors.arenaBlue
                                              : (avail
                                                  ? Colors.white
                                                  : const Color(0xFFF3F4F6)),
                                          borderRadius:
                                              BorderRadius.circular(9),
                                          border: Border.all(
                                            color: sel
                                                ? AppColors.arenaBlue
                                                : (avail
                                                    ? Colors.grey.shade300
                                                    : Colors.grey.shade200),
                                          ),
                                        ),
                                        child: Text(
                                          _hourLabel(h).replaceAll(':00', ''),
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: sel
                                                ? FontWeight.w700
                                                : FontWeight.w500,
                                            color: !avail
                                                ? AppColors.ink3
                                                    .withValues(alpha: 0.5)
                                                : (sel
                                                    ? Colors.white
                                                    : AppColors.ink2),
                                            decoration: avail
                                                ? null
                                                : TextDecoration.lineThrough,
                                          ),
                                        ),
                                      ),
                                    );
                                  },),
                              ],
                            ),
                            const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Text(
                                  '10 AM–9 PM · booked / past hours are disabled',
                                  style: TextStyle(
                                      fontSize: 10.5, color: AppColors.ink3,),),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],

                  // ── Priority ──
                  AppSpacing.vLg,
                  _fieldLabel('Priority'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final t in const [
                        ('low', 'Low', Color(0xFFD1FAE5), Color(0xFF065F46)),
                        ('medium', 'Medium', Color(0xFFFEF3C7),
                            Color(0xFF92400E)),
                        ('high', 'High', Color(0xFFFFEDD5), Color(0xFF9A3412)),
                        ('urgent', 'Urgent', Color(0xFFFEE2E2),
                            Color(0xFFB91C1C)),
                      ])
                        Builder(builder: (_) {
                          final value = t.$1;
                          final label = t.$2;
                          final bg = t.$3;
                          final fg = t.$4;
                          final selected = _priority == value;
                          return GestureDetector(
                            onTap: () => setState(() => _priority = value),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 9,),
                              decoration: BoxDecoration(
                                color: selected ? bg : Colors.white,
                                borderRadius: AppRadius.rMd,
                                border: Border.all(
                                    color: selected
                                        ? fg
                                        : AppColors.border,
                                    width: 2,),
                              ),
                              child: Text(label,
                                  style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color:
                                          selected ? fg : AppColors.ink3,),),
                            ),
                          );
                        },),
                    ],
                  ),
                ],
              ),
            ),

            // ═══ Section 2 — Attachments ═══
            _sectionHeader(Icons.attach_file, 'Attachments'),
            // Real upload progress (shown during save when files are attached).
            if (_uploading)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Uploading…',
                            style: TextStyle(
                                fontSize: 12,
                                color: AppColors.ink2,
                                fontWeight: FontWeight.w600,),),
                        Text('${(_uploadPct * 100).round()}%',
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.ink2,),),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: AppRadius.rXs,
                      child: LinearProgressIndicator(
                        value: _uploadPct == 0 ? null : _uploadPct,
                        minHeight: 7,
                        backgroundColor: AppColors.border,
                        valueColor: const AlwaysStoppedAnimation(
                            AppColors.arenaBlue,),
                      ),
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                Expanded(
                    child: _dropZone(
                        icon: Icons.image_outlined,
                        label: 'Image',
                        onTap: _pickImages,),),
                const SizedBox(width: 10),
                Expanded(
                    child: _dropZone(
                        icon: Icons.attach_file,
                        label: 'File',
                        onTap: _pickFiles,),),
              ],
            ),
            // Image thumbnails grid (64px) with ✕ overlay.
            Builder(builder: (_) {
              final imgs = _attachedFiles
                  .where((f) => RegExp(r'\.(jpe?g|png|webp|gif|heic)$',
                          caseSensitive: false,)
                      .hasMatch(f.path),)
                  .toList();
              if (imgs.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  children: [
                    for (final f in imgs)
                      SizedBox(
                        width: 64,
                        height: 64,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            ClipRRect(
                              borderRadius: AppRadius.rSm,
                              child: Image.file(f,
                                  width: 64, height: 64, fit: BoxFit.cover,),
                            ),
                            Positioned(
                              top: -7,
                              right: -7,
                              child: GestureDetector(
                                onTap: () =>
                                    setState(() => _attachedFiles.remove(f)),
                                child: Container(
                                  width: 20,
                                  height: 20,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: AppColors.arenaRed,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: Colors.white, width: 2,),
                                  ),
                                  child: const Icon(Icons.close,
                                      size: 11, color: Colors.white,),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              );
            },),
            // Non-image files list.
            Builder(builder: (_) {
              final others = _attachedFiles
                  .where((f) => !RegExp(r'\.(jpe?g|png|webp|gif|heic)$',
                          caseSensitive: false,)
                      .hasMatch(f.path),)
                  .toList();
              if (others.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Column(
                  children: [
                    for (final f in others)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Container(
                          height: 40,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF9FAFB),
                            borderRadius: AppRadius.rSm,
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(children: [
                            const Icon(Icons.insert_drive_file_outlined,
                                size: 16, color: AppColors.ink3,),
                            AppSpacing.hSm,
                            Expanded(
                              child: Text(
                                  f.path.split(Platform.pathSeparator).last,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 12.5, color: AppColors.ink,),),
                            ),
                            GestureDetector(
                              onTap: () =>
                                  setState(() => _attachedFiles.remove(f)),
                              child: const Icon(Icons.close,
                                  size: 16, color: AppColors.ink3,),
                            ),
                          ],),
                        ),
                      ),
                  ],
                ),
              );
            },),
            // Link adder.
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _linkCtrl,
                      keyboardType: TextInputType.url,
                      onSubmitted: (_) => _addLink(),
                      decoration: _filledDec('https://…'),
                    ),
                  ),
                  AppSpacing.hSm,
                  SizedBox(
                    height: 44,
                    child: FilledButton(
                      onPressed: _addLink,
                      style: FilledButton.styleFrom(
                          backgroundColor: AppColors.arenaBlue,
                          padding:
                              const EdgeInsets.symmetric(horizontal: 16),),
                      child: const Text('Add'),
                    ),
                  ),
                ],
              ),
            ),
            if (_attachedLinks.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  children: [
                    for (var i = 0; i < _attachedLinks.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Container(
                          height: 40,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF9FAFB),
                            borderRadius: AppRadius.rSm,
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(children: [
                            const Icon(Icons.link,
                                size: 16, color: AppColors.arenaBlue,),
                            AppSpacing.hSm,
                            Expanded(
                              child: Text(_attachedLinks[i],
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 12.5,
                                      color: AppColors.arenaBlue,),),
                            ),
                            GestureDetector(
                              onTap: () =>
                                  setState(() => _attachedLinks.removeAt(i)),
                              child: const Icon(Icons.close,
                                  size: 16, color: AppColors.ink3,),
                            ),
                          ],),
                        ),
                      ),
                  ],
                ),
              ),

            // ═══ Section 3 — Deliverables (collapsible) ═══
            if (_selectedAssigneeIds.isNotEmpty) ...[
              _sectionHeader(
                Icons.checklist,
                'Deliverables',
                trailing: GestureDetector(
                  onTap: () => setState(() => _showDeliv = !_showDeliv),
                  behavior: HitTestBehavior.opaque,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // English role label sits right next to the arrow and
                      // changes with the assignee's department.
                      if (_roleLabel.isNotEmpty)
                        Text(_roleLabel,
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.arenaBlue,),),
                      if (_loadingForm) ...[
                        const SizedBox(width: 6),
                        const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 2),),
                      ],
                      AppSpacing.hXs,
                      Icon(
                          _showDeliv ? Icons.expand_less : Icons.expand_more,
                          color: AppColors.ink3,),
                    ],
                  ),
                ),
              ),
              if (_showDeliv) ...[
                // Checklist: every deliverable type on its own row with a tiny
                // qty stepper + Add. Bounded height so the page stays short.
                Container(
                  decoration: BoxDecoration(
                    borderRadius: AppRadius.rSm,
                    border: Border.all(color: AppColors.border),
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 300),
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          for (var idx = 0;
                              idx <
                                  (_delivTypes.isNotEmpty
                                      ? _delivTypes
                                      : _fallbackDelivTypes)
                                      .length;
                              idx++)
                            Builder(builder: (_) {
                              final list = _delivTypes.isNotEmpty
                                  ? _delivTypes
                                  : _fallbackDelivTypes;
                              final d = list[idx];
                              final key = d['key'] as String;
                              final label =
                                  (d['label'] as String?) ?? _delivLabel(key);
                              final added = _deliverables
                                  .any((x) => x['type'] == key);
                              final qty = _rowQty[key] ?? 1;
                              return Container(
                                decoration: BoxDecoration(
                                  border: idx == 0
                                      ? null
                                      : const Border(
                                          top: BorderSide(
                                              color: Color(0xFFF1F1F4),),),
                                ),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 7,),
                                child: Row(
                                  children: [
                                    Icon(
                                        added
                                            ? Icons.check_circle
                                            : Icons.radio_button_unchecked,
                                        size: 18,
                                        color: added
                                            ? AppColors.arenaBlue
                                            : Colors.grey.shade400,),
                                    AppSpacing.hSm,
                                    Expanded(
                                      child: Text(label,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: added
                                                  ? FontWeight.w700
                                                  : FontWeight.w500,
                                              color: added
                                                  ? AppColors.arenaBlue
                                                  : AppColors.ink,),),
                                    ),
                                    // tiny qty stepper
                                    Container(
                                      decoration: BoxDecoration(
                                        borderRadius: AppRadius.rSm,
                                        border: Border.all(
                                            color: Colors.grey.shade300,),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          InkWell(
                                            onTap: qty > 1
                                                ? () => setState(() =>
                                                    _rowQty[key] = qty - 1,)
                                                : null,
                                            child: const Padding(
                                                padding: EdgeInsets.all(5),
                                                child: Icon(Icons.remove,
                                                    size: 14,),),
                                          ),
                                          SizedBox(
                                              width: 20,
                                              child: Text('$qty',
                                                  textAlign: TextAlign.center,
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 13,),),),
                                          InkWell(
                                            onTap: () => setState(
                                                () => _rowQty[key] = qty + 1,),
                                            child: const Padding(
                                                padding: EdgeInsets.all(5),
                                                child:
                                                    Icon(Icons.add, size: 14),),
                                          ),
                                        ],
                                      ),
                                    ),
                                    AppSpacing.hSm,
                                    GestureDetector(
                                      onTap: () => added
                                          ? _removeDeliverableType(key)
                                          : _addDeliverableType(key),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 7,),
                                        decoration: BoxDecoration(
                                          color: added
                                              ? AppColors.arenaBlue
                                                  .withValues(alpha: 0.12)
                                              : AppColors.arenaBlue,
                                          borderRadius:
                                              AppRadius.rSm,
                                        ),
                                        child: Text(added ? 'Added' : 'Add',
                                            style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                color: added
                                                    ? AppColors.arenaBlue
                                                    : Colors.white,),),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_deliverables.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (var i = 0; i < _deliverables.length; i++)
                          Container(
                            padding: const EdgeInsets.only(
                                left: 12, right: 6, top: 6, bottom: 6,),
                            decoration: BoxDecoration(
                                color: AppColors.arenaBlueLight,
                                borderRadius: AppRadius.rLg,),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Text(
                                  '${_deliverables[i]['qty']}× ${_delivLabel(_deliverables[i]['type'] as String)}',
                                  style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.arenaBlue,),),
                              AppSpacing.hXs,
                              GestureDetector(
                                onTap: () =>
                                    setState(() => _deliverables.removeAt(i)),
                                child: const Icon(Icons.close,
                                    size: 14, color: AppColors.arenaBlue,),
                              ),
                            ],),
                          ),
                      ],
                    ),
                  ),
              ],
            ],

            // (Old attachments / links / assignees / deadline / priority
            //  blocks were moved up into the Section-1 card and the new
            //  Attachments / Deliverables sections above — desktop parity.)

            if (_error != null) ...[
              const SizedBox(height: 14),
              InlineErrorBanner(message: _error!),
            ],
            AppSpacing.vLg,
            // Prominent progress so a slow upload never feels frozen.
            if (_saving) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.arenaBlue.withValues(alpha: 0.06),
                  borderRadius: AppRadius.rMd,
                  border:
                      Border.all(color: AppColors.arenaBlue.withValues(alpha: 0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const SizedBox(
                            width: 16,
                            height: 16,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _uploading
                                ? 'Uploading attachments… ${(_uploadPct * 100).round()}%'
                                : 'Creating task…',
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.arenaBlue,),
                          ),
                        ),
                      ],
                    ),
                    AppSpacing.vSm,
                    ClipRRect(
                      borderRadius: AppRadius.rXs,
                      child: LinearProgressIndicator(
                        value: _uploading
                            ? (_uploadPct == 0 ? null : _uploadPct)
                            : null,
                        minHeight: 8,
                        backgroundColor: AppColors.border,
                        valueColor: const AlwaysStoppedAnimation(
                            AppColors.arenaBlue,),
                      ),
                    ),
                    if (_uploading && _attachedFiles.length > 1)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                            '${_attachedFiles.length} files · large images are compressed first',
                            style: const TextStyle(
                                fontSize: 11, color: AppColors.ink3,),),
                      ),
                  ],
                ),
              ),
              AppSpacing.vMd,
            ],
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
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                  : const Icon(Icons.check, color: Colors.white),
              label: Text(
                _saving
                    ? (_uploading ? 'Uploading…' : 'Creating…')
                    : 'Create task',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600,),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MemberPickerList extends StatelessWidget {
  final List<Map<String, dynamic>> members;
  final Set<int> selectedIds;
  final void Function(int id) onToggle;

  const _MemberPickerList({
    required this.members,
    required this.selectedIds,
    required this.onToggle,
  });

  Color _initialsColor(String name) {
    final hash = name.codeUnits.fold<int>(0, (a, c) => a + c);
    final hues = [
      AppColors.arenaBlue,
      const Color(0xFFEC4899),
      const Color(0xFF10B981),
      const Color(0xFF8B5CF6),
      const Color(0xFFF59E0B),
      const Color(0xFF06B6D4),
      AppColors.arenaRed,
    ];
    return hues[hash.abs() % hues.length];
  }

  String _initials(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    if (members.isEmpty) {
      return const Center(
        child: Text(
          'No teammates match your search.',
          style: TextStyle(fontSize: 12, color: AppColors.ink3),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        borderRadius: AppRadius.rSm,
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: ListView.separated(
        padding: EdgeInsets.zero,
        itemCount: members.length,
        separatorBuilder: (_, __) =>
            const Divider(height: 1, color: AppColors.border),
        itemBuilder: (ctx, i) {
          final m = members[i];
          final id = (m['id'] as num).toInt();
          final name = m['name'] as String? ?? '?';
          final position = m['job_title'] as String?;
          final avatarUrl = m['avatar_url'] as String?;
          final selected = selectedIds.contains(id);
          return InkWell(
            onTap: () => onToggle(id),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  UserAvatar(
                    name: name,
                    avatarUrl: avatarUrl,
                    size: 32,
                    backgroundColor: _initialsColor(name),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.ink,
                          ),
                        ),
                        if (position != null && position.isNotEmpty)
                          Text(
                            position,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 11.5, color: AppColors.ink3,),
                          ),
                      ],
                    ),
                  ),
                  Checkbox(
                    value: selected,
                    onChanged: (_) => onToggle(id),
                    activeColor: AppColors.arenaBlue,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

