import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../services/ble_service.dart';
import '../services/storage_service.dart';
import '../services/wahoo_service.dart';

class HomeScreen extends StatefulWidget {
  final BleService ble;
  final StorageService storage;
  const HomeScreen({super.key, required this.ble, required this.storage});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _wahoo = WahooService();
  WahooStatus? _wahooStatus;

  late TextEditingController _msgCtrl;
  bool _msgEditing = false;

  late bool _climbAEnabled;
  late bool _climbBEnabled;

  @override
  void initState() {
    super.initState();
    _msgCtrl = TextEditingController(text: widget.storage.callMessage);
    _climbAEnabled = widget.storage.climbAEnabled;
    _climbBEnabled = widget.storage.climbBEnabled;
    widget.ble.addListener(_onBle);
    _checkWahoo();
  }

  void _onBle() => setState(() {});

  Future<void> _checkWahoo() async {
    final s = await _wahoo.check();
    if (mounted) setState(() => _wahooStatus = s);
  }

  @override
  void dispose() {
    widget.ble.removeListener(_onBle);
    _msgCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveMessage() async {
    final txt = _msgCtrl.text.trim();
    if (txt.isEmpty) return;
    await widget.storage.saveCallMessage(txt);
    setState(() => _msgEditing = false);
  }

  void _openScanSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ScanSheet(ble: widget.ble),
    ).then((_) => setState(() {}));
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Header ─────────────────────────────────────────────────
              Text('Bell',
                  style: Theme.of(context)
                      .textTheme
                      .headlineLarge
                      ?.copyWith(fontWeight: FontWeight.bold)),
              Text('DI2 → Wahoo alert bridge',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withAlpha(120))),

              const SizedBox(height: 24),

              // ── 1. Connect DI2 (full width) ───────────────────────────
              _Di2Card(ble: widget.ble, storage: widget.storage,
                  onTap: _openScanSheet),

              const SizedBox(height: 12),

              // ── 2 & 3. Button toggles (side by side) ─────────────────
              Row(
                children: [
                  Expanded(
                    child: _ButtonToggleCard(
                      label: 'Climb A',
                      sublabel: 'Bar top · left',
                      enabled: _climbAEnabled,
                      onToggle: (v) async {
                        await widget.storage.saveClimbAEnabled(v);
                        setState(() => _climbAEnabled = v);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ButtonToggleCard(
                      label: 'Climb B',
                      sublabel: 'Bar top · right',
                      enabled: _climbBEnabled,
                      onToggle: (v) async {
                        await widget.storage.saveClimbBEnabled(v);
                        setState(() => _climbBEnabled = v);
                      },
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // ── 4. Message (full width) ───────────────────────────────
              _MessageCard(
                controller: _msgCtrl,
                isEditing: _msgEditing,
                onEdit: () => setState(() => _msgEditing = true),
                onSave: _saveMessage,
                onCancel: () {
                  _msgCtrl.text = widget.storage.callMessage;
                  setState(() => _msgEditing = false);
                },
              ),

              const SizedBox(height: 12),

              // ── 5. Wahoo confirmation (full width) ────────────────────
              _WahooCard(
                status: _wahooStatus,
                onOpenSettings: () async {
                  await _wahoo.openNotificationSettings();
                  await _checkWahoo();
                },
                onRefresh: _checkWahoo,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 1. DI2 connection card — full width
// ─────────────────────────────────────────────────────────────────────────────

class _Di2Card extends StatelessWidget {
  final BleService ble;
  final StorageService storage;
  final VoidCallback onTap;
  const _Di2Card(
      {required this.ble, required this.storage, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final paired = storage.pairedDevice;

    final (dotColor, statusLabel) = switch (ble.status) {
      BleStatus.connected    => (Colors.greenAccent, 'Connected'),
      BleStatus.connecting   => (Colors.orangeAccent, 'Connecting…'),
      BleStatus.scanning     => (Colors.orangeAccent, 'Scanning…'),
      BleStatus.disconnected => (Colors.redAccent, 'Reconnecting…'),
      BleStatus.off          => (Colors.grey, 'Bluetooth off'),
      _                      => (Colors.grey, 'Not connected'),
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            // Status dot
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: dotColor,
                boxShadow: [
                  BoxShadow(
                      color: dotColor.withAlpha(140),
                      blurRadius: 8,
                      spreadRadius: 1)
                ],
              ),
            ),
            const SizedBox(width: 14),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    paired?.name ?? 'No device paired',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  Text(statusLabel,
                      style: TextStyle(
                          fontSize: 12,
                          color: dotColor)),
                ],
              ),
            ),

            FilledButton.tonal(
              onPressed: onTap,
              style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10)),
              child: Text(paired == null ? 'Pair DI2' : 'Change'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 2 & 3. Button toggle card — half width, on/off switch look
// ─────────────────────────────────────────────────────────────────────────────

class _ButtonToggleCard extends StatelessWidget {
  final String label;
  final String sublabel;
  final bool enabled;
  final ValueChanged<bool> onToggle;

  const _ButtonToggleCard({
    required this.label,
    required this.sublabel,
    required this.enabled,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Active colour — use primary with a strong glow.
    const activeColor = Color(0xFFE53935);
    final bgActive   = activeColor.withAlpha(28);
    final bgInactive = cs.surfaceContainerHighest;

    return GestureDetector(
      onTap: () => onToggle(!enabled),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          color: enabled ? bgActive : bgInactive,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: enabled ? activeColor.withAlpha(160) : Colors.transparent,
            width: 1.5,
          ),
          boxShadow: enabled
              ? [
                  BoxShadow(
                      color: activeColor.withAlpha(60),
                      blurRadius: 16,
                      spreadRadius: 2)
                ]
              : [],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ON / OFF badge
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: enabled ? activeColor : cs.outline.withAlpha(60),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                enabled ? 'ON' : 'OFF',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  color: enabled ? Colors.white : cs.onSurfaceVariant,
                ),
              ),
            ),

            const SizedBox(height: 14),

            Text(
              label,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: enabled ? Colors.white : cs.onSurface,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              sublabel,
              style: TextStyle(
                fontSize: 11,
                color: enabled
                    ? Colors.white.withAlpha(160)
                    : cs.onSurfaceVariant,
              ),
            ),

            const SizedBox(height: 16),

            // Visual toggle switch
            Align(
              alignment: Alignment.centerRight,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 44,
                height: 26,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(13),
                  color: enabled
                      ? activeColor
                      : cs.outline.withAlpha(80),
                ),
                child: AnimatedAlign(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  alignment: enabled
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    width: 20,
                    height: 20,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 4. Message card — full width
// ─────────────────────────────────────────────────────────────────────────────

class _MessageCard extends StatelessWidget {
  final TextEditingController controller;
  final bool isEditing;
  final VoidCallback onEdit;
  final VoidCallback onSave;
  final VoidCallback onCancel;

  const _MessageCard({
    required this.controller,
    required this.isEditing,
    required this.onEdit,
    required this.onSave,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Message on Wahoo',
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 10),

            if (isEditing) ...[
              TextField(
                controller: controller,
                autofocus: true,
                maxLength: 30,
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  hintText: 'e.g. Ease Up, Lap, Go Hard',
                  helperText: 'Shown as the caller name on your Wahoo',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                ),
                onSubmitted: (_) => onSave(),
              ),
              const SizedBox(height: 10),
              Row(children: [
                FilledButton(
                    onPressed: onSave, child: const Text('Save')),
                const SizedBox(width: 10),
                TextButton(
                    onPressed: onCancel, child: const Text('Cancel')),
              ]),
            ] else
              GestureDetector(
                onTap: onEdit,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        controller.text.isEmpty ? '—' : controller.text,
                        style: const TextStyle(
                            fontSize: 26, fontWeight: FontWeight.bold),
                      ),
                    ),
                    Icon(Icons.edit_outlined,
                        size: 18, color: cs.onSurfaceVariant),
                  ],
                ),
              ),

            if (!isEditing) ...[
              const SizedBox(height: 4),
              Text('Tap to edit · appears on Wahoo as caller name',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant)),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 5. Wahoo companion status card — full width
// ─────────────────────────────────────────────────────────────────────────────

class _WahooCard extends StatelessWidget {
  final WahooStatus? status;
  final VoidCallback onOpenSettings;
  final VoidCallback onRefresh;

  const _WahooCard({
    required this.status,
    required this.onOpenSettings,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = status;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Wahoo Companion',
                      style: Theme.of(context)
                          .textTheme
                          .labelMedium
                          ?.copyWith(color: cs.onSurfaceVariant)),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 18),
                  onPressed: onRefresh,
                  tooltip: 'Re-check',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (s == null)
              const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
            else ...[
              _StatusRow(
                ok: s.appInstalled,
                label: 'Wahoo app installed',
                hint: s.appInstalled
                    ? null
                    : 'Install ELEMNT / BOLT / ROAM companion app',
              ),
              const SizedBox(height: 8),
              _StatusRow(
                ok: s.notificationListenerEnabled,
                label: 'Notification mirroring enabled',
                hint: s.notificationListenerEnabled
                    ? null
                    : 'Grant notification access to the Wahoo app',
              ),
              if (!s.notificationListenerEnabled) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.settings_outlined, size: 16),
                    label: const Text('Open Notification Settings'),
                    onPressed: onOpenSettings,
                  ),
                ),
              ],
              if (s.allGood) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.greenAccent.withAlpha(28),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: Colors.greenAccent.withAlpha(60)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.check_circle_outline,
                          color: Colors.greenAccent, size: 16),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Ready — hold a climb button to send alert',
                          style: TextStyle(
                              fontSize: 12, color: Colors.greenAccent),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  final bool ok;
  final String label;
  final String? hint;

  const _StatusRow({required this.ok, required this.label, this.hint});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(
            ok ? Icons.check_circle_outline : Icons.radio_button_unchecked,
            size: 16,
            color: ok ? Colors.greenAccent : Colors.grey,
          ),
          const SizedBox(width: 8),
          Text(label,
              style: TextStyle(
                  color: ok ? null : Colors.grey, fontSize: 14)),
        ]),
        if (hint != null)
          Padding(
            padding: const EdgeInsets.only(left: 24, top: 2),
            child: Text(hint!,
                style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant)),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Scan bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

class _ScanSheet extends StatefulWidget {
  final BleService ble;
  const _ScanSheet({required this.ble});

  @override
  State<_ScanSheet> createState() => _ScanSheetState();
}

class _ScanSheetState extends State<_ScanSheet> {
  final Map<String, ScanResult> _results = {};
  StreamSubscription<ScanResult>? _sub;
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    _results.clear();
    setState(() => _scanning = true);
    _sub?.cancel();
    _sub = widget.ble.scan(timeoutSec: 12).listen(
      (r) {
        if (mounted) setState(() => _results[r.device.remoteId.str] = r);
      },
      onDone: () {
        if (mounted) setState(() => _scanning = false);
      },
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    widget.ble.stopScan();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sorted = _results.values.toList()
      ..sort((a, b) => b.rssi.compareTo(a.rssi));

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      maxChildSize: 0.9,
      minChildSize: 0.3,
      builder: (_, scrollCtrl) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 4),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade600,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Select your DI2',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      Text('Wake EW-WU111 by clicking junction-A first',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant)),
                    ],
                  ),
                ),
                if (_scanning)
                  const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                else
                  IconButton(
                      icon: const Icon(Icons.refresh), onPressed: _start),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: sorted.isEmpty
                ? Center(
                    child: Text(
                      _scanning
                          ? 'Scanning for devices…'
                          : 'No devices found.\nTap refresh to scan again.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant),
                    ),
                  )
                : ListView.builder(
                    controller: scrollCtrl,
                    itemCount: sorted.length,
                    itemBuilder: (_, i) {
                      final r = sorted[i];
                      final name = r.device.platformName.isNotEmpty
                          ? r.device.platformName
                          : 'Unknown device';
                      final isShimano =
                          name.toLowerCase().contains('shimano') ||
                              name.toLowerCase().contains('ew-wu') ||
                              name.toLowerCase().contains('di2') ||
                              name.toLowerCase().contains('d-fly');
                      return ListTile(
                        leading: Icon(Icons.bluetooth,
                            color: isShimano
                                ? Colors.greenAccent
                                : Colors.grey),
                        title: Row(
                          children: [
                            Text(name),
                            if (isShimano) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color:
                                      Colors.greenAccent.withAlpha(40),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text('SHIMANO',
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.greenAccent)),
                              ),
                            ],
                          ],
                        ),
                        subtitle: Text(r.device.remoteId.str,
                            style: const TextStyle(fontSize: 11)),
                        trailing: Text('${r.rssi} dBm',
                            style: const TextStyle(fontSize: 12)),
                        onTap: () async {
                          await widget.ble.stopScan();
                          _sub?.cancel();
                          await widget.ble.pairAndConnect(r.device);
                          if (context.mounted) Navigator.pop(context);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
