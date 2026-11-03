import 'package:flutter/material.dart';

import '../models.dart';
import '../repo.dart';
import 'common.dart';

class AdminShell extends StatefulWidget {
  const AdminShell({super.key});
  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _i = 0;
  static const _titles = ['Requests', 'Students', 'Notices', 'Account'];

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[const _RequestsTab(), const _StudentsTab(), const _NoticesAdminTab(), const _AccountTab()];
    return Scaffold(
      appBar: AppBar(title: Text('Admin · ${_titles[_i]}')),
      body: KeyedSubtree(key: ValueKey(_i), child: pages[_i]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _i,
        onDestinationSelected: (i) => setState(() => _i = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.how_to_reg_outlined), selectedIcon: Icon(Icons.how_to_reg), label: 'Requests'),
          NavigationDestination(icon: Icon(Icons.groups_outlined), selectedIcon: Icon(Icons.groups), label: 'Teachers'),
          NavigationDestination(icon: Icon(Icons.campaign_outlined), selectedIcon: Icon(Icons.campaign), label: 'Notices'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Account'),
        ],
      ),
    );
  }
}

// ================================================================= Requests
class _RequestsTab extends StatefulWidget {
  const _RequestsTab();
  @override
  State<_RequestsTab> createState() => _RequestsTabState();
}

class _RequestsTabState extends State<_RequestsTab> {
  String _status = 'pending';
  late Future<List<Link>> _f = Repo.links(_status);

  void _load() => setState(() => _f = Repo.links(_status));

  Future<void> _act(Link l, String status, {String? note}) async {
    try {
      await Repo.review(l.id, status, note: note);
      if (mounted) toast(context, status == 'approved' ? 'Approved ${l.displayName}' : 'Updated ${l.displayName}');
    } catch (e) {
      if (mounted) toast(context, errText(e), error: true);
    }
    _load();
  }

  Future<void> _unlink(Link l, bool approve) async {
    String note = '';
    if (!approve) {
      final n = await askText(context, title: 'Keep linked', label: 'Reason (shown to the teachers, optional)');
      if (n == null) return;
      note = n.trim();
    }
    try {
      await Repo.resolveUnlink(l.id, approve, note: note);
      if (mounted) toast(context, approve ? 'Unlinked ${l.displayName}' : 'Kept ${l.displayName} linked');
    } catch (e) {
      if (mounted) toast(context, errText(e), error: true);
    }
    _load();
  }

  Future<void> _deny(Link l) async {
    final note = await askText(context, title: 'Deny request', label: 'Reason (shown to the teachers, optional)');
    if (note == null) return;
    await _act(l, 'denied', note: note.trim());
  }

  Future<void> _edit(Link l) async {
    final r = await showDialog<_EditResult>(context: context, builder: (_) => _EditLinkDialog(link: l));
    if (r == null) return;
    try {
      await Repo.review(l.id, l.status, studentId: r.studentId, accountName: r.accountName, note: r.note);
      if (r.renameTo != null) {
        await Repo.renameStudent(r.studentId, r.renameTo!);
      }
      if (mounted) toast(context, 'Saved');
    } catch (e) {
      if (mounted) toast(context, errText(e), error: true);
    }
    _load();
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'pending', label: Text('Pending')),
              ButtonSegment(value: 'approved', label: Text('Approved')),
              ButtonSegment(value: 'denied', label: Text('Denied')),
              ButtonSegment(value: 'unlink', label: Text('Unlink')),
            ],
            showSelectedIcon: false,
            selected: {_status},
            onSelectionChanged: (s) {
              _status = s.first;
              _load();
            },
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              _load();
              try {
                await _f;
              } catch (_) {}
            },
            child: Busy<List<Link>>(
              future: _f,
              builder: (rows) => rows.isEmpty
                  ? ListView(children: [Empty(Icons.inbox_outlined, 'No $_status requests.')])
                  : ListView(children: [for (final l in rows) _card(l)]),
            ),
          ),
        ),
      ]);

  Widget _card(Link l) => Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(l.displayName.isEmpty ? '(no name)' : l.displayName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
              IconButton(tooltip: 'Edit', icon: const Icon(Icons.edit_outlined), onPressed: () => _edit(l)),
            ]),
            Text(l.email, style: TextStyle(color: Theme.of(context).colorScheme.outline)),
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.link, size: 18),
              const SizedBox(width: 6),
              Expanded(child: Text('Bound to: ${l.studentName.isEmpty ? '(unknown)' : l.studentName}  ·  ID ${l.studentId}')),
            ]),
            if (l.unlinkRequested)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Unlink requested${l.unlinkReason.isEmpty ? '' : ': ${l.unlinkReason}'}', style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w600)),
              ),
            if (l.adminNote.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text('Note: ${l.adminNote}')),
            Text('Requested ${fStamp.format(l.createdAt)}', style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 12)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              if (_status == 'unlink') ...[
                FilledButton.icon(onPressed: () => _unlink(l, true), icon: const Icon(Icons.link_off), label: const Text('Approve unlink')),
                OutlinedButton.icon(onPressed: () => _unlink(l, false), icon: const Icon(Icons.close), label: const Text('Keep linked')),
              ] else ...[
              if (l.status != 'approved') FilledButton.icon(onPressed: () => _act(l, 'approved'), icon: const Icon(Icons.check), label: const Text('Approve')),
              if (l.status != 'denied') OutlinedButton.icon(onPressed: () => _deny(l), icon: const Icon(Icons.close), label: Text(l.status == 'approved' ? 'Revoke' : 'Deny')),
              ],
            ]),
          ]),
        ),
      );
}

class _EditResult {
  final int studentId;
  final String accountName;
  final String note;
  final String? renameTo; // new name for the student record itself, if changed
  _EditResult(this.studentId, this.accountName, this.note, this.renameTo);
}

/// Admin can change: the account's display name, which student record it is bound to,
/// the student record's own name, and the note.
class _EditLinkDialog extends StatefulWidget {
  final Link link;
  const _EditLinkDialog({required this.link});
  @override
  State<_EditLinkDialog> createState() => _EditLinkDialogState();
}

class _EditLinkDialogState extends State<_EditLinkDialog> {
  late final _account = TextEditingController(text: widget.link.accountName);
  late final _student = TextEditingController(text: widget.link.studentName);
  late final _note = TextEditingController(text: widget.link.adminNote);
  late int _studentId = widget.link.studentId;
  late String _origName = widget.link.studentName;

  Future<void> _rebind() async {
    final s = await showDialog<StudentRow>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Bind to a different teacher'),
        content: SizedBox(width: 420, height: 420, child: StudentPicker(search: Repo.students, loadOnStart: true, onPick: (s) => Navigator.pop(c, s))),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel'))],
      ),
    );
    if (s == null) return;
    setState(() {
      _studentId = s.id;
      _student.text = s.name;
      _origName = s.name;
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Edit request'),
        content: SingleChildScrollView(
          child: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: _account, decoration: const InputDecoration(labelText: 'Name shown on the account')),
              const SizedBox(height: 12),
              TextField(controller: _student, decoration: InputDecoration(labelText: 'Teachers record name (ID $_studentId)', helperText: 'Renames the biometric record itself')),
              Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: _rebind, icon: const Icon(Icons.swap_horiz), label: const Text('Bind to a different teacher'))),
              TextField(controller: _note, decoration: const InputDecoration(labelText: 'Note to the teacher (optional)')),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final newName = _student.text.trim();
              Navigator.pop(context, _EditResult(_studentId, _account.text.trim(), _note.text.trim(), newName.isNotEmpty && newName != _origName ? newName : null));
            },
            child: const Text('Save'),
          ),
        ],
      );
}

// ================================================================= Students
class _StudentsTab extends StatefulWidget {
  const _StudentsTab();
  @override
  State<_StudentsTab> createState() => _StudentsTabState();
}

class _StudentsTabState extends State<_StudentsTab> {
  Key _k = UniqueKey();

  Future<void> _rename(StudentRow s) async {
    final name = await askText(context, title: 'Rename teacher (ID ${s.id})', label: 'Name', initial: s.name);
    if (name == null || name.trim().isEmpty || name.trim() == s.name) return;
    try {
      await Repo.renameStudent(s.id, name);
      if (mounted) toast(context, 'Renamed. The desktop app will pick this up on its next sync.');
    } catch (e) {
      if (mounted) toast(context, errText(e), error: true);
    }
    setState(() => _k = UniqueKey());
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(12),
        child: StudentPicker(key: _k, search: Repo.students, loadOnStart: true, onPick: _rename),
      );
}

// ================================================================= Notices
class _NoticesAdminTab extends StatefulWidget {
  const _NoticesAdminTab();
  @override
  State<_NoticesAdminTab> createState() => _NoticesAdminTabState();
}

class _NoticesAdminTabState extends State<_NoticesAdminTab> {
  late Future<List<Notice>> _f = Repo.notices();
  void _load() => setState(() => _f = Repo.notices());

  Future<void> _add() async {
    final title = TextEditingController();
    final body = TextEditingController();
    bool pinned = false;
    int? section;
    final secs = await Repo.sections();
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setS) => AlertDialog(
          title: const Text('New notice'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: title, decoration: const InputDecoration(labelText: 'Title')),
              const SizedBox(height: 10),
              TextField(controller: body, minLines: 3, maxLines: 6, decoration: const InputDecoration(labelText: 'Details')),
              const SizedBox(height: 10),
              DropdownButtonFormField<int?>(
                initialValue: section,
                decoration: const InputDecoration(labelText: 'Audience'),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('Everyone')),
                  for (var i = 1; i <= 16; i++) DropdownMenuItem<int?>(value: i, child: Text((secs[i] ?? '').isEmpty ? 'Section $i' : secs[i]!)),
                ],
                onChanged: (v) => setS(() => section = v),
              ),
              SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Pin to top'), value: pinned, onChanged: (v) => setS(() => pinned = v)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Post')),
          ],
        ),
      ),
    );
    if (ok != true || title.text.trim().isEmpty) return;
    try {
      await Repo.addNotice(title.text.trim(), body.text.trim(), section: section, pinned: pinned);
    } catch (e) {
      if (mounted) toast(context, errText(e), error: true);
    }
    _load();
  }

  Future<void> _delete(Notice n) async {
    try {
      await Repo.deleteNotice(n.id);
    } catch (e) {
      if (mounted) toast(context, errText(e), error: true);
    }
    _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        floatingActionButton: FloatingActionButton.extended(onPressed: _add, icon: const Icon(Icons.add), label: const Text('Notice')),
        body: RefreshIndicator(
          onRefresh: () async {
            _load();
            try {
              await _f;
            } catch (_) {}
          },
          child: Busy<List<Notice>>(
            future: _f,
            builder: (ns) => ns.isEmpty
                ? ListView(children: const [Empty(Icons.campaign_outlined, 'No notices yet. Tap + to post one.')])
                : ListView(padding: const EdgeInsets.only(bottom: 80), children: [
                    for (final n in ns) NoticeTile(n, trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _delete(n))),
                  ]),
          ),
        ),
      );
}

class _AccountTab extends StatelessWidget {
  const _AccountTab();
  @override
  Widget build(BuildContext context) => ListView(children: [
        ListTile(leading: const Icon(Icons.admin_panel_settings_outlined), title: const Text('Signed in as administrator'), subtitle: Text(sb.auth.currentUser?.email ?? '')),
        ListTile(leading: const Icon(Icons.logout), title: const Text('Sign out'), onTap: () => signOut()),
      ]);
}
