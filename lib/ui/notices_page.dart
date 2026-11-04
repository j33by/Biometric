import 'package:flutter/material.dart';

import '../core/dates.dart';
import '../core/ph_time.dart';
import '../data/api_client.dart';
import '../main.dart';
import 'theme.dart';
import 'widgets.dart';

/// Announcements shown to teachers in the phone app: to everyone or to one faculty.
/// Stored in the cloud (Supabase `notices`), reached through the Render API.
class NoticesPage extends StatefulWidget {
  const NoticesPage({super.key});
  @override
  State<NoticesPage> createState() => _NoticesPageState();
}

class _NoticesPageState extends State<NoticesPage> {
  List<NoticeItem>? _items;
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
      final l = await app.api.listNotices();
      if (mounted) setState(() => _items = l);
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
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
    await _load();
  }

  Future<void> _add() async {
    final r = await showDialog<_NoticeDraft>(context: context, builder: (_) => const _NoticeDialog());
    if (r == null || !mounted) return;
    await _run(() => context.app.api.addNotice(r.title, r.body, faculty: r.faculty, pinned: r.pinned), 'Notice posted');
  }

  Future<void> _delete(NoticeItem n) async {
    if (!await confirm(context, 'Delete "${n.title}"?', 'Teachers will no longer see it in the phone app.')) return;
    if (!mounted) return;
    await _run(() => context.app.api.deleteNotice(n.id), 'Deleted');
  }

  String _when(DateTime? t) {
    if (t == null) return '';
    final p = phFromInstant(t);
    return '${fmtDate(p)} ${fmtTime12(p)}';
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    if (!app.cloudEnabled) {
      return const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        PageHeader(title: 'Notices'),
        Panel(child: Text('Notices are stored in the cloud. Sign in to the server (not offline mode) to post them.', style: TextStyle(color: C.muted))),
      ]);
    }
    final list = _items ?? const <NoticeItem>[];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      PageHeader(
        title: 'Notices',
        subtitle: 'Announcements teachers see in the phone app',
        actions: [
          OutlinedButton.icon(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh, size: 16), label: const Text('Refresh')),
          FilledButton.icon(onPressed: _add, icon: const Icon(Icons.add, size: 16), label: const Text('New notice')),
        ],
      ),
      if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(_error!, style: const TextStyle(color: C.bad))),
      Expanded(
        child: Container(
          decoration: BoxDecoration(color: C.surface, border: Border.all(color: C.border), borderRadius: BorderRadius.circular(4)),
          child: Column(children: [
            const THead(['Notice', 'For', 'Posted', ''], [null, 190, 140, 60]),
            Expanded(
              child: _loading && _items == null
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  : list.isEmpty
                      ? const EmptyNote('No notices yet.')
                      : ListView.builder(
                          itemCount: list.length,
                          itemBuilder: (c, i) {
                            final n = list[i];
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(color: i.isOdd ? C.surfaceAlt : C.surface, border: const Border(bottom: BorderSide(color: C.border, width: 0.5))),
                              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                tcell(
                                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Row(children: [
                                      if (n.pinned) const Padding(padding: EdgeInsets.only(right: 6), child: Icon(Icons.push_pin, size: 14, color: C.warn)),
                                      Flexible(child: Text(n.title, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
                                    ]),
                                    if (n.body.isNotEmpty)
                                      Padding(padding: const EdgeInsets.only(top: 3), child: Text(n.body, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.muted, fontSize: 12.5))),
                                  ]),
                                  null,
                                ),
                                tcell(
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: n.faculty == null
                                        ? const Tag('Every teacher', fg: C.accent, bg: C.accentSoft)
                                        : Tag(app.facultyName(n.faculty!), fg: C.muted, bg: C.surfaceAlt),
                                  ),
                                  190,
                                ),
                                tcell(Text(_when(n.createdAt), style: const TextStyle(color: C.muted, fontSize: 12.5)), 140),
                                tcell(
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: IconButton(
                                      tooltip: 'Delete',
                                      visualDensity: VisualDensity.compact,
                                      icon: const Icon(Icons.delete_outline, size: 18, color: C.bad),
                                      onPressed: () => _delete(n),
                                    ),
                                  ),
                                  60,
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

class _NoticeDraft {
  final String title;
  final String body;
  final int? faculty;
  final bool pinned;
  _NoticeDraft(this.title, this.body, this.faculty, this.pinned);
}

class _NoticeDialog extends StatefulWidget {
  const _NoticeDialog();
  @override
  State<_NoticeDialog> createState() => _NoticeDialogState();
}

class _NoticeDialogState extends State<_NoticeDialog> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  int? _faculty; // null = every teacher
  bool _pinned = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    return AlertDialog(
      title: const Text('New notice', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 440,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: _title, autofocus: true, maxLength: 120, decoration: const InputDecoration(labelText: 'Title')),
            const SizedBox(height: 8),
            TextField(controller: _body, minLines: 3, maxLines: 6, maxLength: 2000, decoration: const InputDecoration(labelText: 'Message (optional)')),
            const SizedBox(height: 8),
            DropdownButtonFormField<int?>(
              initialValue: _faculty,
              decoration: const InputDecoration(labelText: 'Send to'),
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('Every teacher')),
                for (var n = 1; n <= 16; n++) DropdownMenuItem<int?>(value: n, child: Text('Only ${app.facultyName(n)}')),
              ],
              onChanged: (v) => setState(() => _faculty = v),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _pinned,
              onChanged: (v) => setState(() => _pinned = v ?? false),
              title: const Text('Pin to the top'),
            ),
            if (_error != null) Align(alignment: Alignment.centerLeft, child: Text(_error!, style: const TextStyle(color: C.bad))),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: C.muted))),
        FilledButton(
          onPressed: () {
            if (_title.text.trim().isEmpty) {
              setState(() => _error = 'Enter a title.');
              return;
            }
            Navigator.pop(context, _NoticeDraft(_title.text.trim(), _body.text.trim(), _faculty, _pinned));
          },
          child: const Text('Post'),
        ),
      ],
    );
  }
}
