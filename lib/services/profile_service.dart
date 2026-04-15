import 'package:shared_preferences/shared_preferences.dart';

/// Centralised rider profile — single source of truth for name, blood type,
/// emergency contact, fuel settings, speed alert threshold, etc.
class RiderProfile {
  final String name;
  final int avatarIndex;
  final String bloodType;
  final String allergies;
  final String emergencyName;
  final String emergencyPhone;
  final String bikeName;
  final double fuelTankL;
  final double fuelEfficiencyKmL;
  final double speedLimitKmh;

  const RiderProfile({
    required this.name,
    required this.avatarIndex,
    required this.bloodType,
    required this.allergies,
    required this.emergencyName,
    required this.emergencyPhone,
    required this.bikeName,
    required this.fuelTankL,
    required this.fuelEfficiencyKmL,
    required this.speedLimitKmh,
  });

  /// Data encoded in the helmet QR code — first responders scan this.
  String get qrData =>
      'MOTOPULSE EMERGENCY\n'
      'Name: $name\n'
      'Blood: $bloodType\n'
      'Allergies: ${allergies.isEmpty ? "None" : allergies}\n'
      'Bike: ${bikeName.isEmpty ? "N/A" : bikeName}\n'
      'Emergency Contact: ${emergencyName.isEmpty ? "N/A" : "$emergencyName · $emergencyPhone"}';

  /// Estimated fuel range remaining given distance already travelled.
  double remainingRangeKm(double travelledKm) {
    if (fuelEfficiencyKmL <= 0) return 0;
    final used = travelledKm / fuelEfficiencyKmL;
    final remaining = (fuelTankL - used).clamp(0.0, fuelTankL);
    return remaining * fuelEfficiencyKmL;
  }

  /// Fuel percentage remaining given distance already travelled.
  double fuelPercent(double travelledKm) {
    if (fuelTankL <= 0 || fuelEfficiencyKmL <= 0) return 1.0;
    final used = travelledKm / fuelEfficiencyKmL;
    return ((fuelTankL - used) / fuelTankL).clamp(0.0, 1.0);
  }
}

class ProfileService {
  static Future<RiderProfile> load() async {
    final prefs = await SharedPreferences.getInstance();
    return RiderProfile(
      name: prefs.getString('rider_name') ?? 'Rider',
      avatarIndex: prefs.getInt('rider_avatar') ?? 0,
      bloodType: prefs.getString('blood_type') ?? '',
      allergies: prefs.getString('allergies') ?? '',
      emergencyName: prefs.getString('emergency_name') ?? '',
      emergencyPhone: prefs.getString('emergency_phone') ?? '',
      bikeName: prefs.getString('bike_name') ?? '',
      fuelTankL: prefs.getDouble('fuel_tank_l') ?? 15.0,
      fuelEfficiencyKmL: prefs.getDouble('fuel_efficiency_km_l') ?? 30.0,
      speedLimitKmh: prefs.getDouble('speed_limit_kmh') ?? 100.0,
    );
  }

  static Future<void> save({
    String? name,
    int? avatarIndex,
    String? bloodType,
    String? allergies,
    String? emergencyName,
    String? emergencyPhone,
    String? bikeName,
    double? fuelTankL,
    double? fuelEfficiencyKmL,
    double? speedLimitKmh,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (name != null) await prefs.setString('rider_name', name);
    if (avatarIndex != null) await prefs.setInt('rider_avatar', avatarIndex);
    if (bloodType != null) await prefs.setString('blood_type', bloodType);
    if (allergies != null) await prefs.setString('allergies', allergies);
    if (emergencyName != null) await prefs.setString('emergency_name', emergencyName);
    if (emergencyPhone != null) await prefs.setString('emergency_phone', emergencyPhone);
    if (bikeName != null) await prefs.setString('bike_name', bikeName);
    if (fuelTankL != null) await prefs.setDouble('fuel_tank_l', fuelTankL);
    if (fuelEfficiencyKmL != null) {
      await prefs.setDouble('fuel_efficiency_km_l', fuelEfficiencyKmL);
    }
    if (speedLimitKmh != null) {
      await prefs.setDouble('speed_limit_kmh', speedLimitKmh);
    }
  }
}
