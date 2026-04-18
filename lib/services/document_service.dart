import 'package:shared_preferences/shared_preferences.dart';
import '../models/document_model.dart';

/// Persists documents locally using SharedPreferences.
/// Each document is JSON-serialised; images are stored as file paths.
class DocumentService {
  static const _key = 'doc_vault_v1';

  // ── Load ──────────────────────────────────────────────────────────────────

  static Future<List<DocumentModel>> loadDocs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      return DocumentStorage.decodeList(raw)
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt)); // newest first
    } catch (_) {
      return [];
    }
  }

  // ── Save / Upsert ─────────────────────────────────────────────────────────

  static Future<void> saveDoc(DocumentModel doc) async {
    final docs = await loadDocs();
    final idx = docs.indexWhere((d) => d.id == doc.id);
    if (idx >= 0) {
      docs[idx] = doc;
    } else {
      docs.insert(0, doc); // new docs go to front
    }
    await _persist(docs);
  }

  // ── Delete ────────────────────────────────────────────────────────────────

  static Future<void> deleteDoc(String id) async {
    final docs = await loadDocs();
    docs.removeWhere((d) => d.id == id);
    await _persist(docs);
  }

  // ── Count helpers ─────────────────────────────────────────────────────────

  static Future<int> totalCount() async => (await loadDocs()).length;

  static Future<int> expiredCount() async =>
      (await loadDocs()).where((d) => d.isExpired).length;

  static Future<int> expiringSoonCount() async =>
      (await loadDocs()).where((d) => d.isExpiringSoon).length;

  // ── Internal ──────────────────────────────────────────────────────────────

  static Future<void> _persist(List<DocumentModel> docs) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, DocumentStorage.encodeList(docs));
  }
}
