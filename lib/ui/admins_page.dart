import 'package:flutter/material.dart';

import '../core/models.dart';
import '../data/api_client.dart';
import '../main.dart';
import 'theme.dart';
import 'widgets.dart';

/// Dashboard administrators live in the cloud (Supabase via the Render API).
class AdminsPage extends StatefulWidget {
  const AdminsPage({super.key});
  @override
  State<AdminsPage> createState() => _AdminsPageState();
}

class _AdminsPageState extends State<AdminsPage> {
  List<AdminUser>? _admins;
  String? _error;
  bool _loading = false;

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
      final l = await app.api.listAdmins();
      if (mounted) setState(() => _admins = l);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _run(Future<void> Function() job, String done) async {
    try {
      await job();
      if (mounted) toast(context, done);
      await _load();
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    if (!app.cloudEnabled) {
      return const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        PageHeader(title: 'Administrators'),
        Panel(child: Text('Administrator accounts are stored in the cloud. Sign in to the server (not offline mode) to manage them.', style: TextStyle(color: C.muted))),
      ]);
    }
    final list = _admins ?? const <AdminUser>[];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      PageHeader(
        title: 'Administrators',
        subtitle: 'People who can sign in to this dashboard',
        actions: [
          OutlinedButton.icon(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh, size: 16), label: const Text('Refresh')),
          FilledButton.icon(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => _AdminDialog(onSave: (email, name, pw, role) => _run(() => app.api.createAdmin(email, name, pw, role), 'Account created')),
            ),
            icon: const Icon(Icons.person_add_alt, size: 16),
            label: const Text('Add administrator'),
          ),
        ],
      ),
      if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(_error!, style: const TextStyle(color: C.bad))),
      Expanded(
        child: Container(
          decoration: BoxDecoration(color: C.surface, border: Border.all(color: C.border), borderRadius: BorderRadius.circular(4)),
          child: Column(children: [
            const THead(['Name', 'Email', 'Role', 'Status', ''], [null, 260, 120, 90, 150]),
            Expanded(
              child: _loading && list.isEmpty
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  : ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (c, i) {
                        final a = list[i];
                        final me = a.id == app.admin?.id;
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(color: i.isOdd ? C.surfaceAlt : C.surface, border: const Border(bottom: BorderSide(color: C.border, width: 0.5))),
                          child: Row(children: [
                            tcell(Text('${a.name.isEmpty ? '(no name)' : a.name}${me ? '  (you)' : ''}', style: const TextStyle(fontWeight: FontWeight.w600)), null),
                            tcell(Text(a.email, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.muted)), 260),
                            tcell(Align(alignment: Alignment.centerLeft, child: Tag(a.role, fg: a.role == 'superadmin' ? C.accent : C.muted, bg: a.role == 'superadmin' ? C.accentSoft : C.surfaceAlt)), 120),
                            tcell(Align(alignment: Alignment.centerLeft, child: a.disabled ? const Tag('Disabled', fg: C.bad, bg: C.badSoft) : const Tag('Active', fg: C.ok, bg: C.okSoft)), 90),
                            tcell(
                              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                                IconButton(
                                  tooltip: 'Edit',
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.edit_outlined, size: 18),
                                  onPressed: () => showDialog(
                                    context: context,
                                    builder: (_) => _AdminDialog(
                                      existing: a,
                                      onSave: (email, name, pw, role) => _run(
                                          () => app.api.updateAdmin(a.id, name: name, role: me ? null : role, password: pw.isEmpty ? null : pw),
                                          'Saved'),
                                    ),
                                  ),
                                ),
                                if (!me)
                                  IconButton(
                                    tooltip: a.disabled ? 'Enable' : 'Disable',
                                    visualDensity: VisualDensity.compact,
                                    icon: Icon(a.disabled ? Icons.lock_open_outlined : Icons.block, size: 18),
                                    onPressed: () => _run(() => app.api.updateAdmin(a.id, disabled: !a.disabled), a.disabled ? 'Enabled' : 'Disabled'),
                                  ),
                                if (!me)
                                  IconButton(
                                    tooltip: 'Delete',
                                    visualDensity: VisualDensity.compact,
                                    icon: const Icon(Icons.delete_outline, size: 18, color: C.bad),
                                    onPressed: () async {
                                      if (await confirm(context, 'Delete ${a.email}?', 'They will no longer be able to sign in.')) {
                                        await _run(() => app.api.deleteAdmin(a.id), 'Deleted');
                                      }
                                    },
                                  ),
                              ]),
                              150,
                            ),
                          ]),
                        );
                      },
                    ),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 20),
    ]);
  }
}

class _AdminDialog extends StatefulWidget {
  final AdminUser? existing;
  final Future<void> Function(String email, String name, String password, String role) onSave;
  const _AdminDialog({this.existing, required this.onSave});
  @override
  State<_AdminDialog> createState() => _AdminDialogState();
}

class _AdminDialogState extends State<_AdminDialog> {
  late final _email = TextEditingController(text: widget.existing?.email ?? '');
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  final _pw = TextEditingController();
  late String _role = widget.existing?.role ?? 'admin';
  String? _error;

  @override
  Widget build(BuildContext context) {
    final isNew = widget.existing == null;
    return AlertDialog(
      title: Text(isNew ? 'Add administrator' : 'Edit administrator', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      content: SizedBox(
        width: 400,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: _email, enabled: isNew, decoration: const InputDecoration(labelText: 'Email')),
          const SizedBox(height: 12),
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name')),
          const SizedBox(height: 12),
          TextField(controller: _pw, obscureText: true, decoration: InputDecoration(labelText: isNew ? 'Password (min. 8 characters)' : 'New password (leave empty to keep)')),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _role,
            decoration: const InputDecoration(labelText: 'Role'),
            items: const [
              DropdownMenuItem(value: 'superadmin', child: Text('Superadmin – everything, manages accounts')),
              DropdownMenuItem(value: 'admin', child: Text('Admin – edit students, import data')),
              DropdownMenuItem(value: 'viewer', child: Text('Viewer – read only')),
            ],
            onChanged: (v) => setState(() => _role = v ?? 'admin'),
          ),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: const TextStyle(color: C.bad))),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: C.muted))),
        FilledButton(
          onPressed: () {
            if (isNew && (!_email.text.contains('@') || _pw.text.length < 8)) {
              setState(() => _error = 'Enter a valid email and a password of at least 8 characters.');
              return;
            }
            Navigator.pop(context);
            widget.onSave(_email.text.trim(), _name.text.trim(), _pw.text, _role);
          },
          child: Text(isNew ? 'Create' : 'Save'),
        ),
      ],
    );
  }
}
