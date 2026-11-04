import 'dart:async';

import 'package:flutter/material.dart';

import '../core/dates.dart';
import '../core/models.dart';
import '../core/ph_time.dart';
import '../data/api_client.dart';
import '../main.dart';
import 'theme.dart';
import 'widgets.dart';

/// Teacher phone-app logins: approve, deny, revoke, rebind, rename and unlink.
/// Same decisions as the Requests tab of the phone app, made from the PC.
/// The data lives in the cloud (Supabase), reached through the Render API.
class AccountsPage extends StatefulWidget {
  const AccountsPage({super.key});
  @override
  State<AccountsPage> createState() => _AccountsPageState();
}

enum _Tab { pending, approved, denied, unlink }

class _AccountsPageState extends State<AccountsPage> {
  List<TeacherAccount>? _all;
  String? _error;
  bool _loading = false;
  bool _busy = false; // an action is in flight: block double clicks
  _Tab _tab = _Tab.pending;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final app = context.app;
    if (!app.cloudEnabled) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final l = await app.api.listAccounts();
      if (mounted) setState(() => _all = l);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Runs one server action, shows the result and reloads the list either way
  /// (a failed action usually means the list is out of date).
  Future<void> _run(Future<void> Function() job, String done) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await job();
      if (mounted) toast(context, done);
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _load();
  }

  List<TeacherAccount> _rows(_Tab t) {
    final all = _all ?? const <TeacherAccount>[];
    switch (t) {
      case _Tab.pending:
        return all.where((a) => a.status == 'pending').toList();
      case _Tab.approved:
        return all.where((a) => a.status == 'approved').toList();
      case _Tab.denied:
        return all.where((a) => a.status == 'denied').toList();
      case _Tab.unlink:
        return all.where((a) => a.status == 'approved' && a.unlinkRequested).toList();
    }
  }

  String _label(_Tab t) {
    switch (t) {
      case _Tab.pending:
        return 'Pending';
      case _Tab.approved:
        return 'Approved';
      case _Tab.denied:
        return 'Denied';
      case _Tab.unlink:
        return 'Unlink requests';
    }
  }

  Future<void> _approve(TeacherAccount a) =>
      _run(() => context.app.api.updateAccount(a.id, status: 'approved'), 'Approved ${a.displayName}');

  Future<void> _deny(TeacherAccount a) async {
    final revoke = a.status == 'approved';
    final note = await _askNote(
      context,
      title: revoke ? 'Revoke access' : 'Deny request',
      body: revoke
          ? '${a.displayName} will lose access to the schedule, logs and attendance of ${a.teacherName}.'
          : null,
      action: revoke ? 'Revoke' : 'Deny',
    );
    if (note == null || !mounted) return;
    await _run(() => context.app.api.updateAccount(a.id, status: 'denied', note: note), revoke ? 'Revoked ${a.displayName}' : 'Denied ${a.displayName}');
  }

  Future<void> _unlink(TeacherAccount a, bool approve) async {
    if (approve) {
      final ok = await confirm(
        context,
        'Unlink ${a.displayName}?',
        'The link to ${a.teacherName} is removed. They can search and bind again.',
        action: 'Unlink',
      );
      if (!ok || !mounted) return;
      await _run(() => context.app.api.resolveUnlink(a.id, true), 'Unlinked ${a.displayName}');
    } else {
      final note = await _askNote(context, title: 'Keep linked', action: 'Keep linked', danger: false);
      if (note == null || !mounted) return;
      await _run(() => context.app.api.resolveUnlink(a.id, false, note: note), 'Kept ${a.displayName} linked');
    }
  }

  Future<void> _edit(TeacherAccount a) async {
    final r = await showDialog<_EditResult>(context: context, builder: (_) => _EditDialog(account: a));
    if (r == null || !mounted) return;
    final app = context.app;
    final renamed = r.teacherName != null;
    await _run(
      () => app.api.updateAccount(
        a.id,
        accountName: r.accountName,
        note: r.note,
        teacherId: r.teacherId != a.teacherId ? r.teacherId : null,
        teacherName: r.teacherName,
      ),
      'Saved',
    );
    // A renamed record reaches this PC (and Employee Form.xls) through the normal cloud sync.
    if (renamed && mounted) unawaited(app.syncNow());
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    if (!app.cloudEnabled) {
      return const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        PageHeader(title: 'Teacher accounts'),
        Panel(
          child: Text(
            'Teacher phone accounts are stored in the cloud. Sign in to the server (not offline mode) to manage them.',
            style: TextStyle(color: C.muted),
          ),
        ),
      ]);
    }
    final list = _rows(_tab);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      PageHeader(
        title: 'Teacher accounts',
        subtitle: 'Phone-app logins linked to teacher records. Teachers ask from the phone app; you decide here.',
        actions: [
          OutlinedButton.icon(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh, size: 16), label: const Text('Refresh')),
        ],
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Align(
          alignment: Alignment.centerLeft,
          child: SegmentedButton<_Tab>(
            showSelectedIcon: false,
            segments: [
              for (final t in _Tab.values) ButtonSegment(value: t, label: Text('${_label(t)} (${_rows(t).length})')),
            ],
            selected: {_tab},
            onSelectionChanged: (s) => setState(() => _tab = s.first),
          ),
        ),
      ),
      if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(_error!, style: const TextStyle(color: C.bad))),
      Expanded(
        child: Container(
          decoration: BoxDecoration(color: C.surface, border: Border.all(color: C.border), borderRadius: BorderRadius.circular(4)),
          child: Column(children: [
            const THead(['Account', 'Bound to teacher', 'Requested', 'Notes', ''], [260, null, 130, 220, 250]),
            Expanded(
              child: _loading && _all == null
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  : list.isEmpty
                      ? EmptyNote(_emptyText())
                      : ListView.builder(
                          itemCount: list.length,
                          itemBuilder: (c, i) => _row(list[i], i),
                        ),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 20),
    ]);
  }

  String _emptyText() {
    switch (_tab) {
      case _Tab.pending:
        return 'No requests waiting for approval.';
      case _Tab.approved:
        return 'No approved accounts yet.';
      case _Tab.denied:
        return 'No denied requests.';
      case _Tab.unlink:
        return 'Nobody has asked to unlink.';
    }
  }

  String _when(DateTime? t) {
    if (t == null) return '';
    final p = phFromInstant(t);
    return '${fmtDate(p)} ${fmtTime12(p)}';
  }

  Widget _row(TeacherAccount a, int i) {
    final subject = a.faculty == null ? '' : context.app.facultyName(a.faculty!);
    final detail = [
      if (subject.isNotEmpty) subject,
      if (a.position.isNotEmpty) a.position,
      if (a.teacherNo.isNotEmpty) 'Teacher ID ${a.teacherNo}',
    ].join(' · ');
    final notes = <Widget>[
      if (a.unlinkRequested)
        Text('Unlink requested${a.unlinkReason.isEmpty ? '' : ': ${a.unlinkReason}'}',
            style: const TextStyle(color: C.bad, fontWeight: FontWeight.w600, fontSize: 12)),
      if (a.adminNote.isNotEmpty) Text('Note: ${a.adminNote}', style: const TextStyle(color: C.muted, fontSize: 12)),
      if (a.pickedName.isNotEmpty && a.pickedName != a.teacherName)
        Text('Picked: ${a.pickedName}', style: const TextStyle(color: C.faint, fontSize: 12)),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: i.isOdd ? C.surfaceAlt : C.surface, border: const Border(bottom: BorderSide(color: C.border, width: 0.5))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        tcell(
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(a.displayName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(a.email, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.muted, fontSize: 12)),
          ]),
          260,
        ),
        tcell(
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(a.teacherName.isEmpty ? '(unknown)' : a.teacherName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
              const SizedBox(width: 8),
              Text('ID ${a.teacherId}', style: const TextStyle(color: C.muted, fontSize: 12)),
            ]),
            if (a.teacherMissing)
              const Padding(
                padding: EdgeInsets.only(top: 3),
                child: Tag('Record missing in the cloud', fg: C.bad, bg: C.badSoft),
              )
            else if (detail.isNotEmpty)
              Text(detail, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.muted, fontSize: 12)),
          ]),
          null,
        ),
        tcell(Text(_when(a.createdAt), style: const TextStyle(color: C.muted, fontSize: 12.5)), 130),
        tcell(
          notes.isEmpty ? const SizedBox.shrink() : Column(crossAxisAlignment: CrossAxisAlignment.start, children: notes),
          220,
        ),
        tcell(
          Wrap(alignment: WrapAlignment.end, spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: _actions(a)),
          250,
        ),
      ]),
    );
  }

  List<Widget> _actions(TeacherAccount a) {
    final off = _busy;
    final edit = IconButton(
      tooltip: 'Edit name, note or bound teacher',
      visualDensity: VisualDensity.compact,
      icon: const Icon(Icons.edit_outlined, size: 18),
      onPressed: off ? null : () => _edit(a),
    );
    if (_tab == _Tab.unlink) {
      return [
        FilledButton(onPressed: off ? null : () => _unlink(a, true), child: const Text('Approve unlink')),
        OutlinedButton(onPressed: off ? null : () => _unlink(a, false), child: const Text('Keep linked')),
      ];
    }
    return [
      if (a.status != 'approved') FilledButton(onPressed: off ? null : () => _approve(a), child: const Text('Approve')),
      if (a.status != 'denied')
        OutlinedButton(
          onPressed: off ? null : () => _deny(a),
          style: OutlinedButton.styleFrom(foregroundColor: C.bad),
          child: Text(a.status == 'approved' ? 'Revoke' : 'Deny'),
        ),
      edit,
    ];
  }
}

/// Asks for an optional reason (shown to the teacher). Returns null if cancelled.
Future<String?> _askNote(BuildContext context, {required String title, String? body, required String action, bool danger = true}) {
  final c = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      content: SizedBox(
        width: 400,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (body != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(body)),
          TextField(
            controller: c,
            autofocus: true,
            maxLength: 300,
            decoration: const InputDecoration(labelText: 'Reason (shown to the teacher, optional)'),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: C.muted))),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: danger ? C.bad : C.accent),
          onPressed: () => Navigator.pop(ctx, c.text.trim()),
          child: Text(action),
        ),
      ],
    ),
  );
}

class _EditResult {
  final String accountName;
  final String note;
  final int teacherId;
  final String? teacherName; // set only if the teacher record itself is renamed
  _EditResult(this.accountName, this.note, this.teacherId, this.teacherName);
}

/// Change the account's display name, the note to the teacher, which teacher record it is
/// bound to, and the teacher record's own name.
class _EditDialog extends StatefulWidget {
  final TeacherAccount account;
  const _EditDialog({required this.account});
  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  late final _account = TextEditingController(text: widget.account.accountName);
  late final _teacher = TextEditingController(text: widget.account.teacherName);
  late final _note = TextEditingController(text: widget.account.adminNote);
  late int _teacherId = widget.account.teacherId;
  late String _origName = widget.account.teacherName; // name of the record now shown in the field

  Future<void> _rebind() async {
    final t = await showDialog<Teacher>(context: context, builder: (_) => const _TeacherPicker());
    if (t == null) return;
    setState(() {
      _teacherId = t.id;
      _teacher.text = t.name;
      _origName = t.name;
    });
  }

  @override
  Widget build(BuildContext context) {
    final rebound = _teacherId != widget.account.teacherId;
    return AlertDialog(
      title: const Text('Edit account', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.account.email, style: const TextStyle(color: C.muted)),
            const SizedBox(height: 12),
            TextField(controller: _account, decoration: const InputDecoration(labelText: 'Name shown on the account')),
            const SizedBox(height: 12),
            TextField(
              controller: _teacher,
              decoration: InputDecoration(labelText: 'Teacher record name (ID $_teacherId)', helperText: 'Renames the biometric record itself'),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(onPressed: _rebind, icon: const Icon(Icons.swap_horiz, size: 18), label: const Text('Bind to a different teacher')),
            ),
            if (rebound)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('The account will be bound to the new record when you save.', style: TextStyle(color: C.warn, fontSize: 12)),
              ),
            TextField(controller: _note, maxLength: 300, decoration: const InputDecoration(labelText: 'Note to the teacher (optional)')),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: C.muted))),
        FilledButton(
          onPressed: () {
            final name = _teacher.text.trim();
            Navigator.pop(
              context,
              _EditResult(_account.text.trim(), _note.text.trim(), _teacherId, name.isNotEmpty && name != _origName ? name : null),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// Pick a teacher from the records this PC holds. The server checks that the record is
/// in the cloud too, so a teacher that has not synced yet is refused with a clear message.
class _TeacherPicker extends StatefulWidget {
  const _TeacherPicker();
  @override
  State<_TeacherPicker> createState() => _TeacherPickerState();
}

class _TeacherPickerState extends State<_TeacherPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final q = _q.trim().toLowerCase();
    final list = app.teachers.where((t) => q.isEmpty || t.name.toLowerCase().contains(q) || '${t.id}' == q).toList();
    return AlertDialog(
      title: const Text('Bind to a different teacher', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      content: SizedBox(
        width: 440,
        height: 420,
        child: Column(children: [
          TextField(
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Search by name or device ID', prefixIcon: Icon(Icons.search, size: 18)),
            onChanged: (v) => setState(() => _q = v),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: list.isEmpty
                ? const EmptyNote('No matching teacher.')
                : ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (c, i) {
                      final t = list[i];
                      return ListTile(
                        dense: true,
                        title: Text(t.name, overflow: TextOverflow.ellipsis),
                        subtitle: Text('ID ${t.id} · ${app.facultyName(t.faculty)}'),
                        onTap: () => Navigator.pop(context, t),
                      );
                    },
                  ),
          ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: C.muted)))],
    );
  }
}
