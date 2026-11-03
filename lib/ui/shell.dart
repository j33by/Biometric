import 'package:flutter/material.dart';

import '../core/dates.dart';
import '../data/app_state.dart';
import '../main.dart';
import 'admins_page.dart';
import 'attendance_page.dart';
import 'dashboard_page.dart';
import 'sections_page.dart';
import 'settings_page.dart';
import 'students_page.dart';
import 'sync_page.dart';
import 'theme.dart';

class _Nav {
  final String label;
  final IconData icon;
  final String? group;
  const _Nav(this.label, this.icon, [this.group]);
}

const _navs = <_Nav>[
  _Nav('Dashboard', Icons.dashboard_outlined, 'Overview'),
  _Nav('Teachers', Icons.groups_outlined, 'Records'),
  _Nav('Attendance', Icons.fact_check_outlined),
  _Nav('Subjects & shifts', Icons.schedule_outlined, 'Setup'),
  _Nav('Device sync', Icons.usb_rounded),
  _Nav('Administrators', Icons.admin_panel_settings_outlined, 'System'),
  _Nav('Settings', Icons.tune_outlined),
];

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _index = 0;

  void go(int i) => setState(() => _index = i);

  Widget _page() {
    switch (_index) {
      case 0:
        return DashboardPage(onNavigate: go);
      case 1:
        return const StudentsPage();
      case 2:
        return const AttendancePage();
      case 3:
        return const SectionsPage();
      case 4:
        return const SyncPage();
      case 5:
        return const AdminsPage();
      default:
        return const SettingsPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(children: [
        _Sidebar(index: _index, onSelect: go),
        Expanded(
          child: Column(children: [
            _TopBar(title: _navs[_index].label),
            Expanded(
              child: Container(
                color: C.bg,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(28, 22, 28, 0),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1280), child: _page()),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _Sidebar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onSelect;
  const _Sidebar({required this.index, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final school = app.rules.company.trim().isEmpty ? 'Attendance Console' : app.rules.company.trim().toUpperCase();
    return Container(
      width: 224,
      color: C.side,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 22, 16, 18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(school, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15, letterSpacing: 0.4)),
            const SizedBox(height: 2),
            const Text('Biometric attendance', style: TextStyle(color: C.sideText, fontSize: 12)),
          ]),
        ),
        for (var i = 0; i < _navs.length; i++) ...[
          if (_navs[i].group != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 16, 6),
              child: Text(_navs[i].group!.toUpperCase(), style: const TextStyle(color: Color(0xFF6F7F8F), fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1)),
            ),
          if (!(i == 5 && !(app.admin?.isSuper ?? false))) _item(i),
        ],
        const Spacer(),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFF2B3A49)))),
          child: Row(children: [
            const Icon(Icons.account_circle_outlined, color: C.sideText, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(app.admin?.name.isNotEmpty == true ? app.admin!.name : (app.admin?.email ?? ''),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 12.5)),
                Text(app.localMode ? 'Offline mode' : (app.admin?.role ?? ''), style: const TextStyle(color: C.sideText, fontSize: 11)),
              ]),
            ),
            IconButton(
              tooltip: 'Sign out',
              onPressed: app.signOut,
              icon: const Icon(Icons.logout, color: C.sideText, size: 18),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _item(int i) {
    final sel = i == index;
    return InkWell(
      onTap: () => onSelect(i),
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: sel ? C.sideHi : Colors.transparent,
          border: Border(left: BorderSide(color: sel ? const Color(0xFF6FA8DC) : Colors.transparent, width: 3)),
        ),
        child: Row(children: [
          Icon(_navs[i].icon, size: 18, color: sel ? Colors.white : C.sideText),
          const SizedBox(width: 12),
          Text(_navs[i].label, style: TextStyle(fontSize: 13.5, color: sel ? Colors.white : C.sideText, fontWeight: sel ? FontWeight.w600 : FontWeight.w400)),
        ]),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final String title;
  const _TopBar({required this.title});

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final usb = app.drives;
    String cloud;
    Color cloudColor;
    if (app.localMode || !app.cloudEnabled) {
      cloud = 'Local only';
      cloudColor = C.muted;
    } else if (app.syncPhase == SyncPhase.syncing) {
      cloud = 'Syncing…';
      cloudColor = C.accent;
    } else if (app.syncPhase == SyncPhase.error) {
      cloud = 'Cloud offline · ${app.pendingCloudChanges} queued';
      cloudColor = C.bad;
    } else {
      cloud = app.lastCloudSync == null ? 'Connected' : 'Synced ${fmtAgo(app.lastCloudSync!)}';
      cloudColor = C.ok;
    }
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 28),
      decoration: const BoxDecoration(color: C.surface, border: Border(bottom: BorderSide(color: C.border))),
      child: Row(children: [
        Text(fmtDateLong(DateTime.now()), style: const TextStyle(color: C.muted, fontSize: 12.5)),
        const Spacer(),
        if (usb.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(right: 18),
            child: Row(children: [
              const Icon(Icons.usb_rounded, size: 16, color: C.ok),
              const SizedBox(width: 5),
              Text('USB ${usb.map((d) => d.root.substring(0, 2)).join(', ')}', style: const TextStyle(fontSize: 12.5, color: C.ok, fontWeight: FontWeight.w600)),
            ]),
          ),
        Tooltip(
          message: app.syncError ?? 'Cloud sync status',
          child: InkWell(
            onTap: app.cloudEnabled ? app.syncNow : null,
            child: Row(children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: cloudColor, shape: BoxShape.circle)),
              const SizedBox(width: 7),
              Text(cloud, style: TextStyle(fontSize: 12.5, color: cloudColor, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      ]),
    );
  }
}
