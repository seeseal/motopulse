import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/maintenance_model.dart';
import '../models/ride_model.dart';

class MaintenanceService {
  MaintenanceService._();

  static const _itemsKey = 'maintenance_items';

  // ── Items CRUD ─────────────────────────────────────────────────────────────

  static Future<List<MaintenanceItem>> loadItems() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_itemsKey) ?? [];
    return raw
        .map((s) => MaintenanceItem.fromJson(jsonDecode(s)))
        .toList();
  }

  static Future<void> saveItems(List<MaintenanceItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _itemsKey,
      items.map((i) => jsonEncode(i.toJson())).toList(),
    );
  }

  static Future<void> addItem(MaintenanceItem item) async {
    final items = await loadItems();
    items.add(item);
    await saveItems(items);
  }

  static Future<void> updateItem(MaintenanceItem updated) async {
    final items = await loadItems();
    final idx = items.indexWhere((i) => i.id == updated.id);
    if (idx >= 0) items[idx] = updated;
    await saveItems(items);
  }

  static Future<void> deleteItem(String id) async {
    final items = await loadItems();
    items.removeWhere((i) => i.id == id);
    await saveItems(items);
  }

  // ── Odometer (total distance from all saved rides) ─────────────────────────

  static Future<double> totalOdometerKm() async {
    final rides = await RideStorage.loadRides();
    return rides.fold<double>(0.0, (sum, r) => sum + r.distanceKm);
  }

  // ── Defaults ───────────────────────────────────────────────────────────────

  /// Pre-populates a fresh install with common service items.
  static Future<void> seedDefaults() async {
    final existing = await loadItems();
    if (existing.isNotEmpty) return;
    final now = DateTime.now();
    final defaults = [
      MaintenanceItem(
        id: '1', name: 'Engine Oil Change',
        intervalKm: 5000, lastServiceKm: 0,
        notes: 'Use recommended viscosity grade',
        lastServiceDate: now,
      ),
      MaintenanceItem(
        id: '2', name: 'Chain Lube & Tension',
        intervalKm: 500, lastServiceKm: 0,
        lastServiceDate: now,
      ),
      MaintenanceItem(
        id: '3', name: 'Air Filter',
        intervalKm: 10000, lastServiceKm: 0,
        lastServiceDate: now,
      ),
      MaintenanceItem(
        id: '4', name: 'Brake Fluid',
        intervalKm: 20000, lastServiceKm: 0,
        lastServiceDate: now,
      ),
      MaintenanceItem(
        id: '5', name: 'Tyre Pressure Check',
        intervalKm: 500, lastServiceKm: 0,
        lastServiceDate: now,
      ),
      MaintenanceItem(
        id: '6', name: 'Spark Plugs',
        intervalKm: 12000, lastServiceKm: 0,
        lastServiceDate: now,
      ),
    ];
    await saveItems(defaults);
  }
}
