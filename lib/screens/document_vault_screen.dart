import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../models/document_model.dart';
import '../services/document_service.dart';
import '../widgets/glass_card.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Document Vault Screen
// ════════════════════════════════════════════════════════════════════════════

class DocumentVaultScreen extends StatefulWidget {
  const DocumentVaultScreen({super.key});

  @override
  State<DocumentVaultScreen> createState() => _DocumentVaultScreenState();
}

class _DocumentVaultScreenState extends State<DocumentVaultScreen> {
  List<DocumentModel> _docs = [];
  DocType? _filterType; // null = All
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final docs = await DocumentService.loadDocs();
    if (!mounted) return;
    setState(() {
      _docs = docs;
      _loading = false;
    });
  }

  List<DocumentModel> get _filtered => _filterType == null
      ? _docs
      : _docs.where((d) => d.type == _filterType).toList();

  // ── Counts for badge ──────────────────────────────────────────────────────

  int get _alertCount =>
      _docs.where((d) => d.isExpired || d.isExpiringSoon).length;

  // ── Sheet & detail routing ────────────────────────────────────────────────

  Future<void> _openSheet({DocumentModel? editing}) async {
    HapticFeedback.lightImpact();
    final result = await showModalBottomSheet<DocumentModel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DocSheet(existing: editing),
    );
    if (result != null) {
      await DocumentService.saveDoc(result);
      _load();
    }
  }

  void _openDetail(DocumentModel doc) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _DocDetailScreen(
          doc: doc,
          onEdit: () {
            Navigator.pop(context);
            _openSheet(editing: doc);
          },
          onDelete: () async {
            Navigator.pop(context);
            await _confirmDelete(doc);
          },
        ),
      ),
    );
  }

  Future<void> _confirmDelete(DocumentModel doc) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Document',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        content: Text(
          'Remove "${doc.title}" from your vault?',
          style: const TextStyle(color: Colors.white54, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.white38)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete',
                style: TextStyle(
                    color: Color(0xFFE8003D), fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await DocumentService.deleteDoc(doc.id);
      _load();
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              const SizedBox(height: 14),
              _buildFilterRow(),
              const SizedBox(height: 14),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: const Icon(Icons.arrow_back_ios_new_rounded,
                color: Colors.white54, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('DOCUMENT VAULT',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            letterSpacing: 4,
                            fontWeight: FontWeight.w300)),
                    if (_alertCount > 0) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8003D),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '$_alertCount',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  _docs.isEmpty
                      ? 'Stored locally on device'
                      : '${_docs.length} document${_docs.length == 1 ? '' : 's'}  ·  Private & offline',
                  style: const TextStyle(color: Colors.white24, fontSize: 11),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => _openSheet(),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFE8003D),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text('+ ADD',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      letterSpacing: 2,
                      fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterRow() {
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          _chip(null, 'All'),
          ...DocType.values.map((t) => _chip(t, t.shortLabel)),
        ],
      ),
    );
  }

  Widget _chip(DocType? type, String label) {
    final selected = _filterType == type;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _filterType = type);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFFE8003D).withOpacity(0.15)
              : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? const Color(0xFFE8003D)
                : Colors.white.withOpacity(0.1),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          type != null ? '${type.emoji}  $label' : label,
          style: TextStyle(
            color: selected ? const Color(0xFFE8003D) : Colors.white54,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(
            color: Color(0xFFE8003D), strokeWidth: 1.5),
      );
    }

    final items = _filtered;
    if (items.isEmpty) return _emptyState();

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
      itemCount: items.length,
      itemBuilder: (_, i) => _DocCard(
        doc: items[i],
        onTap: () => _openDetail(items[i]),
        onLongPress: () => _confirmDelete(items[i]),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.04),
              borderRadius: BorderRadius.circular(20),
              border:
                  Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: const Center(
                child: Text('📂', style: TextStyle(fontSize: 32))),
          ),
          const SizedBox(height: 18),
          const Text('No documents yet',
              style: TextStyle(
                  color: Colors.white38,
                  fontSize: 16,
                  fontWeight: FontWeight.w300)),
          const SizedBox(height: 8),
          Text(
            _filterType == null
                ? 'Tap + ADD to store insurance,\nregistration, and more'
                : 'No ${_filterType!.label} documents stored',
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white24, fontSize: 12, height: 1.7),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  Document Card
// ════════════════════════════════════════════════════════════════════════════

class _DocCard extends StatelessWidget {
  final DocumentModel doc;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _DocCard({
    required this.doc,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final (expiryColor, expiryLabel) = _expiryBadge();

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: doc.isExpired
                ? const Color(0xFFE8003D).withOpacity(0.35)
                : Colors.white.withOpacity(0.07),
          ),
        ),
        child: Row(
          children: [
            // Type icon box
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                  child: Text(doc.type.emoji,
                      style: const TextStyle(fontSize: 24))),
            ),
            const SizedBox(width: 14),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(doc.title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 3),
                  Text(doc.type.label,
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 11)),
                  if (doc.expiryDate != null) ...[
                    const SizedBox(height: 7),
                    Row(children: [
                      _badge(expiryLabel, expiryColor),
                      const SizedBox(width: 7),
                      Text(
                        _fmtDate(doc.expiryDate!),
                        style: const TextStyle(
                            color: Colors.white24, fontSize: 10),
                      ),
                    ]),
                  ],
                ],
              ),
            ),
            // Thumbnail or arrow
            if (doc.imagePath != null &&
                File(doc.imagePath!).existsSync())
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.file(
                  File(doc.imagePath!),
                  width: 50,
                  height: 50,
                  fit: BoxFit.cover,
                ),
              )
            else
              const Icon(Icons.chevron_right_rounded,
                  color: Colors.white24, size: 20),
          ],
        ),
      ),
    );
  }

  (Color, String) _expiryBadge() {
    if (doc.isExpired) return (const Color(0xFFE8003D), 'EXPIRED');
    if (doc.isExpiringSoon) {
      final d = doc.daysUntilExpiry!;
      return (const Color(0xFFFFD700), d == 0 ? 'TODAY' : '${d}d LEFT');
    }
    return (const Color(0xFF00C853), 'VALID');
  }

  Widget _badge(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: color.withOpacity(0.14),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(text,
            style: TextStyle(
                color: color,
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8)),
      );

  String _fmtDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')} ${_mon(dt.month)} ${dt.year}';

  String _mon(int m) => const [
        '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ][m];
}

// ════════════════════════════════════════════════════════════════════════════
//  Document Detail Screen
// ════════════════════════════════════════════════════════════════════════════

class _DocDetailScreen extends StatelessWidget {
  final DocumentModel doc;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _DocDetailScreen({
    required this.doc,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final hasPhoto =
        doc.imagePath != null && File(doc.imagePath!).existsSync();
    final (expiryColor, expiryLabel) = _expiryBadge();

    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              // ── Top bar ─────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Icon(Icons.arrow_back_ios_new_rounded,
                          color: Colors.white54, size: 20),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        '${doc.type.emoji}  ${doc.type.label}',
                        style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 12,
                            letterSpacing: 1.5),
                      ),
                    ),
                    // Edit
                    GestureDetector(
                      onTap: onEdit,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.07),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: const Text('Edit',
                            style: TextStyle(
                                color: Colors.white70, fontSize: 12)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Delete
                    GestureDetector(
                      onTap: onDelete,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFFE8003D).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: const Color(0xFFE8003D)
                                  .withOpacity(0.3)),
                        ),
                        child: const Icon(Icons.delete_outline_rounded,
                            color: Color(0xFFE8003D), size: 18),
                      ),
                    ),
                  ],
                ),
              ),

              // ── Content ──────────────────────────────────────────────────
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Photo
                      if (hasPhoto)
                        GestureDetector(
                          onTap: () => _showFullPhoto(context),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: Stack(
                              children: [
                                Image.file(
                                  File(doc.imagePath!),
                                  width: double.infinity,
                                  height: 240,
                                  fit: BoxFit.cover,
                                ),
                                Positioned(
                                  bottom: 10,
                                  right: 10,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius:
                                          BorderRadius.circular(8),
                                    ),
                                    child: const Row(children: [
                                      Icon(Icons.zoom_out_map_rounded,
                                          color: Colors.white70,
                                          size: 12),
                                      SizedBox(width: 4),
                                      Text('Tap to expand',
                                          style: TextStyle(
                                              color: Colors.white70,
                                              fontSize: 10)),
                                    ]),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        Container(
                          width: double.infinity,
                          height: 140,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.04),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: Colors.white.withOpacity(0.08)),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(doc.type.emoji,
                                  style: const TextStyle(fontSize: 40)),
                              const SizedBox(height: 8),
                              const Text('No photo attached',
                                  style: TextStyle(
                                      color: Colors.white24,
                                      fontSize: 12)),
                            ],
                          ),
                        ),

                      const SizedBox(height: 24),

                      // Title
                      Text(
                        doc.title,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w300,
                            letterSpacing: 0.5),
                      ),

                      const SizedBox(height: 20),

                      // Info grid
                      _infoRow(
                        icon: Icons.category_outlined,
                        label: 'Type',
                        value: doc.type.label,
                      ),

                      if (doc.expiryDate != null) ...[
                        const SizedBox(height: 12),
                        _infoRow(
                          icon: Icons.event_outlined,
                          label: 'Expiry',
                          value: _fmtDate(doc.expiryDate!),
                          badge: expiryLabel,
                          badgeColor: expiryColor,
                        ),
                      ],

                      if (doc.notes.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        const Text('NOTES',
                            style: TextStyle(
                                color: Colors.white24,
                                fontSize: 10,
                                letterSpacing: 3)),
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.04),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color: Colors.white.withOpacity(0.07)),
                          ),
                          child: Text(
                            doc.notes,
                            style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 13,
                                height: 1.6),
                          ),
                        ),
                      ],

                      const SizedBox(height: 20),
                      Text(
                        'Added ${_fmtDate(doc.createdAt)}',
                        style: const TextStyle(
                            color: Colors.white24, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow({
    required IconData icon,
    required String label,
    required String value,
    String? badge,
    Color? badgeColor,
  }) {
    return Row(
      children: [
        Icon(icon, color: Colors.white24, size: 16),
        const SizedBox(width: 10),
        Text(label,
            style: const TextStyle(color: Colors.white38, fontSize: 12)),
        const SizedBox(width: 8),
        Text(value,
            style: const TextStyle(color: Colors.white70, fontSize: 13)),
        if (badge != null && badgeColor != null) ...[
          const SizedBox(width: 8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: badgeColor.withOpacity(0.14),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(badge,
                style: TextStyle(
                    color: badgeColor,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8)),
          ),
        ],
      ],
    );
  }

  void _showFullPhoto(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _FullPhotoViewer(imagePath: doc.imagePath!),
      ),
    );
  }

  (Color, String) _expiryBadge() {
    if (doc.isExpired) return (const Color(0xFFE8003D), 'EXPIRED');
    if (doc.isExpiringSoon) {
      final d = doc.daysUntilExpiry!;
      return (const Color(0xFFFFD700), d == 0 ? 'TODAY' : '${d}d LEFT');
    }
    return (const Color(0xFF00C853), 'VALID');
  }

  String _fmtDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')} ${_mon(dt.month)} ${dt.year}';

  String _mon(int m) => const [
        '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ][m];
}

// ════════════════════════════════════════════════════════════════════════════
//  Full Photo Viewer
// ════════════════════════════════════════════════════════════════════════════

class _FullPhotoViewer extends StatelessWidget {
  final String imagePath;
  const _FullPhotoViewer({required this.imagePath});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Center(
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 5.0,
            child: Image.file(File(imagePath)),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  Add / Edit Sheet
// ════════════════════════════════════════════════════════════════════════════

class _DocSheet extends StatefulWidget {
  final DocumentModel? existing;
  const _DocSheet({this.existing});

  @override
  State<_DocSheet> createState() => _DocSheetState();
}

class _DocSheetState extends State<_DocSheet> {
  late DocType _type;
  late TextEditingController _titleCtrl;
  late TextEditingController _notesCtrl;
  String? _imagePath;
  DateTime? _expiryDate;
  bool _hasExpiry = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _type = e?.type ?? DocType.insurance;
    _titleCtrl = TextEditingController(text: e?.title ?? '');
    _notesCtrl = TextEditingController(text: e?.notes ?? '');
    _imagePath = e?.imagePath;
    _expiryDate = e?.expiryDate;
    _hasExpiry = e?.expiryDate != null;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  bool get _isEditing => widget.existing != null;

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        imageQuality: 88,
        maxWidth: 1600,
      );
      if (picked != null && mounted) {
        setState(() => _imagePath = picked.path);
      }
    } catch (_) {}
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiryDate ?? now.add(const Duration(days: 365)),
      firstDate: now.subtract(const Duration(days: 365 * 5)),
      lastDate: now.add(const Duration(days: 365 * 20)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFFE8003D),
            onPrimary: Colors.white,
            surface: Color(0xFF1A1A1A),
            onSurface: Colors.white,
          ),
          dialogBackgroundColor: const Color(0xFF1A1A1A),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => _expiryDate = picked);
    }
  }

  void _save() {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please enter a document title'),
          backgroundColor: const Color(0xFF1A1A1A),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }
    HapticFeedback.mediumImpact();
    final doc = DocumentModel(
      id: widget.existing?.id ?? DocumentModel.newId(),
      type: _type,
      title: title,
      imagePath: _imagePath,
      expiryDate: _hasExpiry ? _expiryDate : null,
      notes: _notesCtrl.text.trim(),
      createdAt: widget.existing?.createdAt ?? DateTime.now(),
    );
    Navigator.pop(context, doc);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 24, 20, 24 + bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Handle ──────────────────────────────────────────────────
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // ── Title ───────────────────────────────────────────────────
            Text(
              _isEditing ? 'Edit Document' : 'Add Document',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 22),

            // ── Type picker ─────────────────────────────────────────────
            _label('DOCUMENT TYPE'),
            const SizedBox(height: 10),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: DocType.values.map((t) {
                  final sel = _type == t;
                  return GestureDetector(
                    onTap: () => setState(() => _type = t),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 130),
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: sel
                            ? const Color(0xFFE8003D).withOpacity(0.15)
                            : Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: sel
                              ? const Color(0xFFE8003D)
                              : Colors.white12,
                          width: sel ? 1.5 : 1,
                        ),
                      ),
                      child: Text(
                        '${t.emoji}  ${t.shortLabel}',
                        style: TextStyle(
                          color: sel
                              ? const Color(0xFFE8003D)
                              : Colors.white54,
                          fontSize: 12,
                          fontWeight: sel
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),

            const SizedBox(height: 20),

            // ── Title field ─────────────────────────────────────────────
            _label('TITLE'),
            const SizedBox(height: 8),
            _textField(
              _titleCtrl,
              hint: 'e.g. Comprehensive Insurance 2025',
              capitalization: TextCapitalization.words,
            ),

            const SizedBox(height: 20),

            // ── Photo ────────────────────────────────────────────────────
            _label('PHOTO'),
            const SizedBox(height: 10),
            if (_imagePath != null && File(_imagePath!).existsSync()) ...[
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.file(
                      File(_imagePath!),
                      width: double.infinity,
                      height: 160,
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: GestureDetector(
                      onTap: () => setState(() => _imagePath = null),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.close_rounded,
                            color: Colors.white, size: 16),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => _showPhotoPicker(),
                child: const Text('Change photo',
                    style: TextStyle(
                        color: Color(0xFFE8003D), fontSize: 12)),
              ),
            ] else
              Row(children: [
                Expanded(
                  child: _photoBtn(
                    icon: Icons.camera_alt_outlined,
                    label: 'Camera',
                    onTap: () => _pickImage(ImageSource.camera),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _photoBtn(
                    icon: Icons.photo_library_outlined,
                    label: 'Gallery',
                    onTap: () => _pickImage(ImageSource.gallery),
                  ),
                ),
              ]),

            const SizedBox(height: 20),

            // ── Expiry date ──────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _label('EXPIRY DATE'),
                Switch(
                  value: _hasExpiry,
                  onChanged: (v) => setState(() {
                    _hasExpiry = v;
                    if (v && _expiryDate == null) {
                      _expiryDate =
                          DateTime.now().add(const Duration(days: 365));
                    }
                  }),
                  activeColor: const Color(0xFFE8003D),
                  inactiveTrackColor: Colors.white10,
                  inactiveThumbColor: Colors.white38,
                ),
              ],
            ),
            if (_hasExpiry) ...[
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _pickDate,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: const Color(0xFFE8003D).withOpacity(0.4)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.calendar_today_outlined,
                        color: Color(0xFFE8003D), size: 16),
                    const SizedBox(width: 10),
                    Text(
                      _expiryDate != null
                          ? '${_expiryDate!.day.toString().padLeft(2, '0')} ${_mon(_expiryDate!.month)} ${_expiryDate!.year}'
                          : 'Tap to select date',
                      style: TextStyle(
                        color: _expiryDate != null
                            ? Colors.white
                            : Colors.white38,
                        fontSize: 14,
                      ),
                    ),
                  ]),
                ),
              ),
            ],

            const SizedBox(height: 20),

            // ── Notes ────────────────────────────────────────────────────
            _label('NOTES (OPTIONAL)'),
            const SizedBox(height: 8),
            _textField(
              _notesCtrl,
              hint: 'Policy number, insurer, or anything useful...',
              maxLines: 3,
            ),

            const SizedBox(height: 28),

            // ── Save button ──────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE8003D),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text(
                        _isEditing ? 'Save Changes' : 'Save Document',
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPhotoPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined,
                  color: Color(0xFFE8003D)),
              title: const Text('Camera',
                  style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined,
                  color: Color(0xFFE8003D)),
              title: const Text('Gallery',
                  style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Text(text,
      style: const TextStyle(
          color: Colors.white24, fontSize: 10, letterSpacing: 3));

  Widget _textField(
    TextEditingController ctrl, {
    String hint = '',
    TextCapitalization capitalization = TextCapitalization.none,
    int maxLines = 1,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: TextField(
        controller: ctrl,
        textCapitalization: capitalization,
        maxLines: maxLines,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.white24, fontSize: 14),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 13),
        ),
      ),
    );
  }

  Widget _photoBtn({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Column(
          children: [
            Icon(icon, color: const Color(0xFFE8003D), size: 22),
            const SizedBox(height: 6),
            Text(label,
                style: const TextStyle(
                    color: Colors.white54, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  String _mon(int m) => const [
        '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ][m];
}
