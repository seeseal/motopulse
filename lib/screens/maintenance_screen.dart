import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/maintenance_model.dart';
import '../services/maintenance_service.dart';

class MaintenanceScreen extends StatefulWidget {
  const MaintenanceScreen({super.key});

  @override
  State<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends State<MaintenanceScreen> {
  List<MaintenanceItem> _items = [];
  double _odometerKm = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await MaintenanceService.seedDefaults();
    final items = await MaintenanceService.loadItems();
    final odo   = await MaintenanceService.totalOdometerKm();
    if (mounted) setState(() { _items = items; _odometerKm = odo; _loading = false; });
  }

  void _markServiced(MaintenanceItem item) async {
    HapticFeedback.mediumImpact();
    final updated = item.copyWith(
      lastServiceKm: _odometerKm,
      lastServiceDate: DateTime.now(),
    );
    await MaintenanceService.updateItem(updated);
    _load();
  }

  void _deleteItem(String id) async {
    await MaintenanceService.deleteItem(id);
    _load();
  }

  void _showAddSheet({MaintenanceItem? existing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditItemSheet(
        existing: existing,
        currentOdo: _odometerKm,
        onSave: (item) async {
          if (existing == null) {
            await MaintenanceService.addItem(item);
          } else {
            await MaintenanceService.updateItem(item);
          }
          _load();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sorted = [..._items]..sort((a, b) =>
        b.duePct(_odometerKm).compareTo(a.duePct(_odometerKm)));

    return Scaffold(
      backgroundColor: const Color(0xFF080808),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.arrow_back_ios_new_rounded,
                        color: Colors.white54, size: 20),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Text('MAINTENANCE',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            letterSpacing: 4,
                            fontWeight: FontWeight.w300)),
                  ),
                  GestureDetector(
                    onTap: () => _showAddSheet(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8003D),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(children: [
                        Icon(Icons.add_rounded, color: Colors.white, size: 15),
                        SizedBox(width: 4),
                        Text('ADD',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.5)),
                      ]),
                    ),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                    color: const Color(0xFF111111),
                    borderRadius: BorderRadius.circular(12)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.speed_rounded, color: Colors.white38, size: 15),
                  const SizedBox(width: 8),
                  const Text('Total distance ridden',
                      style: TextStyle(color: Colors.white38, fontSize: 12)),
                  const SizedBox(width: 8),
                  Text('${_odometerKm.toStringAsFixed(1)} km',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                ]),
              ),
            ),

            const SizedBox(height: 6),

            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: Color(0xFFE8003D), strokeWidth: 1.5))
                  : sorted.isEmpty
                      ? _emptyState()
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                          itemCount: sorted.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, i) => _ItemCard(
                            item: sorted[i],
                            odometerKm: _odometerKm,
                            onServiced: () => _markServiced(sorted[i]),
                            onEdit: () => _showAddSheet(existing: sorted[i]),
                            onDelete: () => _deleteItem(sorted[i].id),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: const [
          Icon(Icons.build_circle_outlined, color: Colors.white12, size: 64),
          SizedBox(height: 16),
          Text('No maintenance items',
              style: TextStyle(color: Colors.white38, fontSize: 16)),
          SizedBox(height: 6),
          Text('Tap + ADD to track your service schedule',
              style: TextStyle(color: Colors.white24, fontSize: 12)),
        ]),
      );
}

// ── Item Card ─────────────────────────────────────────────────────────────────

class _ItemCard extends StatelessWidget {
  final MaintenanceItem item;
  final double odometerKm;
  final VoidCallback onServiced;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ItemCard({
    required this.item,
    required this.odometerKm,
    required this.onServiced,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final pct      = item.duePct(odometerKm);
    final overdue  = item.isOverdue(odometerKm);
    final kmLeft   = item.kmUntilDue(odometerKm);
    final barColor = overdue
        ? const Color(0xFFE8003D)
        : pct > 0.75
            ? const Color(0xFFFFD700)
            : const Color(0xFF00C853);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(16),
        border: overdue
            ? Border.all(color: const Color(0xFFE8003D).withOpacity(0.4))
            : null,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Title row
        Row(children: [
          Expanded(
            child: Text(item.name,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w500)),
          ),
          if (overdue)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFE8003D).withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text('OVERDUE',
                  style: TextStyle(
                      color: Color(0xFFE8003D),
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5)),
            ),
          const SizedBox(width: 8),
          // Context menu
          GestureDetector(
            onTap: () => _showMenu(context),
            child: const Icon(Icons.more_vert_rounded,
                color: Colors.white24, size: 18),
          ),
        ]),

        const SizedBox(height: 10),

        // Progress bar
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pct,
            backgroundColor: Colors.white10,
            valueColor: AlwaysStoppedAnimation<Color>(barColor),
            minHeight: 5,
          ),
        ),

        const SizedBox(height: 8),

        // Stats row
        Row(children: [
          Text(
            overdue
                ? '${(odometerKm - item.lastServiceKm - item.intervalKm).abs().toStringAsFixed(0)} km overdue'
                : '${kmLeft.toStringAsFixed(0)} km until due',
            style: TextStyle(
                color: overdue ? const Color(0xFFE8003D) : Colors.white38,
                fontSize: 11),
          ),
          const Spacer(),
          Text(
            'Every ${item.intervalKm} km',
            style: const TextStyle(color: Colors.white24, fontSize: 11),
          ),
        ]),

        if (item.notes.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(item.notes,
              style:
                  const TextStyle(color: Colors.white30, fontSize: 11)),
        ],

        const SizedBox(height: 12),

        // Mark serviced button
        GestureDetector(
          onTap: onServiced,
          child: Container(
            width: double.infinity,
            height: 38,
            decoration: BoxDecoration(
              color: overdue
                  ? const Color(0xFFE8003D).withOpacity(0.12)
                  : Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: overdue
                    ? const Color(0xFFE8003D).withOpacity(0.4)
                    : Colors.white12,
              ),
            ),
            child: Center(
              child: Text(
                'MARK AS SERVICED',
                style: TextStyle(
                  color: overdue ? const Color(0xFFE8003D) : Colors.white54,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  void _showMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141414),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                  color: Colors.white12,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.edit_rounded, color: Colors.white54),
            title: const Text('Edit', style: TextStyle(color: Colors.white)),
            onTap: () { Navigator.pop(context); onEdit(); },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline_rounded,
                color: Color(0xFFE8003D)),
            title: const Text('Delete',
                style: TextStyle(color: Color(0xFFE8003D))),
            onTap: () { Navigator.pop(context); onDelete(); },
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }
}

// ── Edit / Add Sheet ──────────────────────────────────────────────────────────

class _EditItemSheet extends StatefulWidget {
  final MaintenanceItem? existing;
  final double currentOdo;
  final Function(MaintenanceItem) onSave;

  const _EditItemSheet({
    this.existing,
    required this.currentOdo,
    required this.onSave,
  });

  @override
  State<_EditItemSheet> createState() => _EditItemSheetState();
}

class _EditItemSheetState extends State<_EditItemSheet> {
  late TextEditingController _nameCtrl;
  late TextEditingController _intervalCtrl;
  late TextEditingController _lastKmCtrl;
  late TextEditingController _notesCtrl;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl     = TextEditingController(text: e?.name ?? '');
    _intervalCtrl = TextEditingController(
        text: e != null ? '${e.intervalKm}' : '5000');
    _lastKmCtrl   = TextEditingController(
        text: e != null
            ? e.lastServiceKm.toStringAsFixed(0)
            : widget.currentOdo.toStringAsFixed(0));
    _notesCtrl    = TextEditingController(text: e?.notes ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _intervalCtrl.dispose();
    _lastKmCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final name     = _nameCtrl.text.trim();
    final interval = int.tryParse(_intervalCtrl.text) ?? 5000;
    final lastKm   = double.tryParse(_lastKmCtrl.text) ?? widget.currentOdo;

    if (name.isEmpty) return;

    final item = MaintenanceItem(
      id: widget.existing?.id ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      intervalKm: interval,
      lastServiceKm: lastKm,
      notes: _notesCtrl.text.trim(),
      lastServiceDate: DateTime.now(),
    );
    Navigator.pop(context);
    widget.onSave(item);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
        decoration: const BoxDecoration(
          color: Color(0xFF141414),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Center(
            child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(2))),
          ),
          const SizedBox(height: 18),
          Text(
            widget.existing == null ? 'ADD SERVICE ITEM' : 'EDIT ITEM',
            style: const TextStyle(
                color: Colors.white38,
                fontSize: 11,
                letterSpacing: 3),
          ),
          const SizedBox(height: 20),
          _field(_nameCtrl, 'Service name', 'e.g. Oil Change'),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _field(_intervalCtrl, 'Interval (km)',
                '5000', isNumber: true)),
            const SizedBox(width: 12),
            Expanded(child: _field(_lastKmCtrl, 'Last service at (km)',
                '0', isNumber: true)),
          ]),
          const SizedBox(height: 12),
          _field(_notesCtrl, 'Notes (optional)', ''),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: _save,
            child: Container(
              width: double.infinity,
              height: 52,
              decoration: BoxDecoration(
                color: const Color(0xFFE8003D),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Center(
                child: Text('SAVE',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 3)),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String label,
      String hint, {bool isNumber = false}) {
    return TextField(
      controller: ctrl,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: Colors.white38, fontSize: 12),
        hintStyle: const TextStyle(color: Colors.white12, fontSize: 12),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.white12),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE8003D)),
        ),
        filled: true,
        fillColor: const Color(0xFF1A1A1A),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }
}
