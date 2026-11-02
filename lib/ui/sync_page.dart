import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../core/dates.dart';
import '../data/app_state.dart';
import '../main.dart';
import 'theme.dart';
import 'widgets.dart';

class SyncPage extends StatelessWidget {
  const SyncPage({super.key});

  Future<void> _pickFolder(BuildContext context) async {
    final app = context.app;
    final dir = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Choose the folder used to exchange files with the device');
    if (dir != null) await app.setSyncFolder(dir);
  }

  Future<void> _importLogs(BuildContext context) async {
    final app = context.app;
    final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['txt'], dialogTitle: 'Choose Attendance_Logs.txt');
    final path = res?.files.single.path;
    if (path == null) return;
    final r = await app.importLogsFromPath(path, force: true);
    if (context.mounted && r != null) {
      toast(context, '${r.added} new punch${r.added == 1 ? '' : 'es'} added, ${r.duplicates} already known.');
    }
  }

  Future<void> _saveFormTo(BuildContext context) async {
    final app = context.app;
    final dir = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Where should Employee_Form.xls be written? (e.g. the USB stick)');
    if (dir == null) return;
    final ok = await app.exportFormTo(p.join(dir, kFormFileNames.first));
    if (context.mounted) toast(context, ok ? 'Employee_Form.xls written to $dir' : 'Could not write the file – see activity log.', error: !ok);
  }

  void _openFolder(String path) {
    if (Platform.isWindows) Process.run('explorer', [path]);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final formPath = p.join(app.syncFolder, kFormFileNames.first);
    final act = app.activity.reversed.take(60).toList();
    return ListView(padding: const EdgeInsets.only(bottom: 32), children: [
      PageHeader(
        title: 'Device sync',
        subtitle: 'The biometric device only talks USB. This page keeps its files and this app in step.',
        actions: [
          OutlinedButton.icon(onPressed: () => _importLogs(context), icon: const Icon(Icons.file_open_outlined, size: 16), label: const Text('Import logs file')),
          FilledButton.icon(onPressed: app.canWrite ? () => app.exportNow() : null, icon: const Icon(Icons.upload_file_outlined, size: 16), label: const Text('Write Employee_Form.xls now')),
        ],
      ),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          flex: 3,
          child: Column(children: [
            Panel(
              title: 'Exchange folder',
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SelectableText(app.syncFolder, style: const TextStyle(fontFamily: 'Consolas', fontSize: 12.5)),
                const SizedBox(height: 4),
                const Text(
                  'Employee_Form.xls is rewritten here after every change. Drop Attendance_Logs.txt into this folder (or plug in the USB stick) and new punches are imported automatically. Duplicates are skipped.',
                  style: TextStyle(color: C.muted, height: 1.4),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  OutlinedButton(onPressed: () => _pickFolder(context), child: const Text('Change folder')),
                  const SizedBox(width: 8),
                  OutlinedButton(onPressed: () => _openFolder(app.syncFolder), child: const Text('Open in Explorer')),
                  const SizedBox(width: 8),
                  OutlinedButton(onPressed: () => _saveFormTo(context), child: const Text('Save form to…')),
                ]),
                const SizedBox(height: 14),
                const Divider(height: 1),
                _switch('Rewrite Employee_Form.xls automatically', 'After every student, section, shift or rule change.', app.autoExport, (v) => app.updateSettings(autoExport: v)),
                _switch('Watch for USB sticks', 'Import Attendance_Logs.txt as soon as a stick containing it is inserted.', app.autoUsb, (v) => app.updateSettings(autoUsb: v)),
                _switch('Also write Employee_Form.xls to the stick', 'So the device can upload new students straight from it.', app.writeUsb, (v) => app.updateSettings(writeUsb: v)),
              ]),
            ),
            const SizedBox(height: 14),
            Panel(
              title: 'USB sticks detected',
              trailing: TextButton(onPressed: app.rescanUsb, child: const Text('Rescan')),
              child: app.drives.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('None. A stick shows up here when it contains Attendance_Logs.txt or Employee_Form.xls in its top folder.', style: TextStyle(color: C.muted)),
                    )
                  : Column(children: [
                      for (final d in app.drives)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(children: [
                            const Icon(Icons.usb_rounded, size: 18, color: C.ok),
                            const SizedBox(width: 10),
                            Text(d.root, style: const TextStyle(fontWeight: FontWeight.w700)),
                            const SizedBox(width: 14),
                            if (d.logsPath != null) const Tag('Attendance_Logs.txt', fg: C.ok, bg: C.okSoft),
                            if (d.logsPath != null) const SizedBox(width: 6),
                            if (d.formPath != null) const Tag('Employee_Form.xls', fg: C.accent, bg: C.accentSoft),
                            const Spacer(),
                            if (d.logsPath != null) TextButton(onPressed: () => app.importLogsFromPath(d.logsPath!, force: true), child: const Text('Import logs')),
                            TextButton(onPressed: app.canWrite ? () => app.exportFormTo(d.formPath ?? p.join(d.root, kFormFileNames.first)) : null, child: const Text('Write form')),
                          ]),
                        ),
                    ]),
            ),
          ]),
        ),
        const SizedBox(width: 14),
        Expanded(
          flex: 2,
          child: Column(children: [
            Panel(
              title: 'Status',
              child: Column(children: [
                _stat('Punches stored', '${app.logs.length}'),
                _stat('Days with data', '${app.logsByDate.length}'),
                _stat('Last import', app.lastImport == null ? 'this session: none' : fmtAgo(app.lastImport!)),
                _stat('Form last written', app.lastExport == null ? 'this session: none' : fmtAgo(app.lastExport!)),
                _stat('Form file', p.basename(formPath)),
                _stat('Cloud queue', app.cloudEnabled ? '${app.pendingCloudChanges} pending' : 'cloud off'),
              ]),
            ),
            const SizedBox(height: 14),
            Panel(
              title: 'Uploading to the device',
              child: const Text(
                '1. Copy Employee_Form.xls to the USB stick (automatic if the stick is plugged in).\n'
                '2. On the device: menu → USB → upload employee info.\n'
                '3. New students must still enrol their fingerprint or card on the device under the ID shown here.',
                style: TextStyle(color: C.muted, height: 1.6),
              ),
            ),
          ]),
        ),
      ]),
      const SizedBox(height: 14),
      Panel(
        title: 'Activity',
        padding: EdgeInsets.zero,
        child: act.isEmpty
            ? const EmptyNote('Nothing has happened yet.')
            : Column(children: [
                for (var i = 0; i < act.length; i++)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                    decoration: BoxDecoration(color: i.isOdd ? C.surfaceAlt : C.surface, border: const Border(bottom: BorderSide(color: C.border, width: 0.5))),
                    child: Row(children: [
                      SizedBox(width: 120, child: Text('${fmtDayMonth(act[i].time)} ${fmtTimeSec(act[i].time)}', style: const TextStyle(fontSize: 12, color: C.muted))),
                      SizedBox(width: 18, child: Icon(_icon(act[i].kind), size: 14, color: _color(act[i].kind))),
                      Expanded(child: Text(act[i].text)),
                    ]),
                  ),
              ]),
      ),
    ]);
  }

  IconData _icon(String k) => k == 'ok' ? Icons.check_circle_outline : (k == 'warn' ? Icons.warning_amber_rounded : (k == 'error' ? Icons.error_outline : Icons.info_outline));
  Color _color(String k) => k == 'ok' ? C.ok : (k == 'warn' ? C.warn : (k == 'error' ? C.bad : C.muted));

  Widget _stat(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [Expanded(child: Text(k, style: const TextStyle(color: C.muted))), Text(v, style: const TextStyle(fontWeight: FontWeight.w600))]),
      );

  Widget _switch(String title, String sub, bool value, ValueChanged<bool> onChanged) => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(sub, style: const TextStyle(fontSize: 12)),
        value: value,
        onChanged: onChanged,
      );
}
