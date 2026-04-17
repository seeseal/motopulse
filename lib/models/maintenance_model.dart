/// A single maintenance item (e.g. "Oil Change every 5 000 km").
class MaintenanceItem {
  final String id;
  final String name;
  final int intervalKm;       // how often this service is due (km)
  final double lastServiceKm; // odometer reading at last service
  final String notes;
  final DateTime? lastServiceDate;

  const MaintenanceItem({
    required this.id,
    required this.name,
    required this.intervalKm,
    required this.lastServiceKm,
    this.notes = '',
    this.lastServiceDate,
  });

  double duePct(double currentKm) {
    if (intervalKm <= 0) return 0;
    final travelled = currentKm - lastServiceKm;
    return (travelled / intervalKm).clamp(0.0, 1.0);
  }

  double kmUntilDue(double currentKm) {
    final remaining = intervalKm - (currentKm - lastServiceKm);
    return remaining.clamp(0.0, intervalKm.toDouble());
  }

  bool isOverdue(double currentKm) =>
      currentKm - lastServiceKm >= intervalKm;

  MaintenanceItem copyWith({
    String? name,
    int? intervalKm,
    double? lastServiceKm,
    String? notes,
    DateTime? lastServiceDate,
  }) =>
      MaintenanceItem(
        id: id,
        name: name ?? this.name,
        intervalKm: intervalKm ?? this.intervalKm,
        lastServiceKm: lastServiceKm ?? this.lastServiceKm,
        notes: notes ?? this.notes,
        lastServiceDate: lastServiceDate ?? this.lastServiceDate,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'intervalKm': intervalKm,
        'lastServiceKm': lastServiceKm,
        'notes': notes,
        'lastServiceDate': lastServiceDate?.toIso8601String(),
      };

  factory MaintenanceItem.fromJson(Map<String, dynamic> j) => MaintenanceItem(
        id: j['id'] as String,
        name: j['name'] as String,
        intervalKm: j['intervalKm'] as int,
        lastServiceKm: (j['lastServiceKm'] as num).toDouble(),
        notes: j['notes'] as String? ?? '',
        lastServiceDate: j['lastServiceDate'] != null
            ? DateTime.tryParse(j['lastServiceDate'] as String)
            : null,
      );
}
