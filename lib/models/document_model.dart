import 'dart:convert';

// ── Document type ─────────────────────────────────────────────────────────────

enum DocType {
  insurance,
  registration,
  license,
  puc,
  fitness,
  other,
}

extension DocTypeExt on DocType {
  String get label {
    switch (this) {
      case DocType.insurance:    return 'Insurance';
      case DocType.registration: return 'Registration';
      case DocType.license:      return 'Driving License';
      case DocType.puc:          return 'PUC Certificate';
      case DocType.fitness:      return 'Fitness / MOT';
      case DocType.other:        return 'Other';
    }
  }

  String get emoji {
    switch (this) {
      case DocType.insurance:    return '🛡️';
      case DocType.registration: return '📋';
      case DocType.license:      return '🪪';
      case DocType.puc:          return '🌿';
      case DocType.fitness:      return '🔧';
      case DocType.other:        return '📄';
    }
  }

  String get shortLabel {
    switch (this) {
      case DocType.insurance:    return 'Insurance';
      case DocType.registration: return 'Reg';
      case DocType.license:      return 'License';
      case DocType.puc:          return 'PUC';
      case DocType.fitness:      return 'Fitness';
      case DocType.other:        return 'Other';
    }
  }
}

// ── Document model ────────────────────────────────────────────────────────────

class DocumentModel {
  final String id;
  final DocType type;
  final String title;
  final String? imagePath;
  final DateTime? expiryDate;
  final String notes;
  final DateTime createdAt;

  const DocumentModel({
    required this.id,
    required this.type,
    required this.title,
    this.imagePath,
    this.expiryDate,
    this.notes = '',
    required this.createdAt,
  });

  // ── Copy ──────────────────────────────────────────────────────────────────

  DocumentModel copyWith({
    DocType? type,
    String? title,
    String? imagePath,
    bool clearImage = false,
    DateTime? expiryDate,
    bool clearExpiry = false,
    String? notes,
  }) {
    return DocumentModel(
      id: id,
      type: type ?? this.type,
      title: title ?? this.title,
      imagePath: clearImage ? null : (imagePath ?? this.imagePath),
      expiryDate: clearExpiry ? null : (expiryDate ?? this.expiryDate),
      notes: notes ?? this.notes,
      createdAt: createdAt,
    );
  }

  // ── Expiry helpers ────────────────────────────────────────────────────────

  bool get isExpired =>
      expiryDate != null && expiryDate!.isBefore(DateTime.now());

  bool get isExpiringSoon {
    if (expiryDate == null || isExpired) return false;
    return expiryDate!.difference(DateTime.now()).inDays <= 30;
  }

  int? get daysUntilExpiry {
    if (expiryDate == null) return null;
    return expiryDate!.difference(DateTime.now()).inDays;
  }

  // ── Serialisation ─────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'title': title,
        'imagePath': imagePath,
        'expiryDate': expiryDate?.toIso8601String(),
        'notes': notes,
        'createdAt': createdAt.toIso8601String(),
      };

  factory DocumentModel.fromJson(Map<String, dynamic> json) {
    return DocumentModel(
      id: json['id'] as String,
      type: DocType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => DocType.other,
      ),
      title: json['title'] as String,
      imagePath: json['imagePath'] as String?,
      expiryDate: json['expiryDate'] != null
          ? DateTime.tryParse(json['expiryDate'] as String)
          : null,
      notes: (json['notes'] as String?) ?? '',
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  /// Generates a simple unique ID from timestamp + random suffix.
  static String newId() =>
      '${DateTime.now().millisecondsSinceEpoch}_${DateTime.now().microsecond}';
}

// ── Local storage helpers (kept in model layer for convenience) ───────────────

class DocumentStorage {
  static List<DocumentModel> decodeList(String raw) {
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => DocumentModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static String encodeList(List<DocumentModel> docs) =>
      jsonEncode(docs.map((d) => d.toJson()).toList());
}
