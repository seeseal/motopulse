import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RiderPosition {
  final String riderId;
  final String riderName;
  final String emoji;
  final double lat;
  final double lng;
  final double speedKmh;
  final DateTime updatedAt;

  RiderPosition({
    required this.riderId,
    required this.riderName,
    required this.emoji,
    required this.lat,
    required this.lng,
    required this.speedKmh,
    required this.updatedAt,
  });

  factory RiderPosition.fromMap(String id, Map<String, dynamic> map) {
    return RiderPosition(
      riderId: id,
      riderName: map['name'] ?? 'Rider',
      emoji: map['emoji'] ?? '🏍️',
      lat: (map['lat'] ?? 0).toDouble(),
      lng: (map['lng'] ?? 0).toDouble(),
      speedKmh: (map['speed'] ?? 0).toDouble(),
      updatedAt: map['updatedAt'] != null
          ? (map['updatedAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'name': riderName,
        'emoji': emoji,
        'lat': lat,
        'lng': lng,
        'speed': speedKmh,
        'updatedAt': FieldValue.serverTimestamp(),
      };
}

class GroupRideService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const _collection = 'group_rides';

  // ── Persistent session state ──────────────────────────────────────────────
  // These survive screen disposal — the ride keeps going until explicitly ended
  static String? _activeCode;
  static StreamSubscription<Position>? _gpsSubscription;

  static String? get activeCode => _activeCode;
  static bool get isActive => _activeCode != null;

  static final List<Map<String, dynamic>> _avatarEmojis = [
    {'emoji': '🏍️'},
    {'emoji': '🔥'},
    {'emoji': '⚡'},
    {'emoji': '🐺'},
    {'emoji': '🦅'},
    {'emoji': '💀'},
  ];

  /// Generate a random 6-character room code
  static String generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random();
    return List.generate(6, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  /// Create a new group ride, returns the room code
  static Future<String> createGroupRide() async {
    final prefs = await SharedPreferences.getInstance();
    final code = generateCode();
    final riderId = prefs.getString('rider_id') ?? _generateRiderId(prefs);
    final name = prefs.getString('rider_name') ?? 'Rider';
    final avatarIndex = prefs.getInt('rider_avatar') ?? 0;
    final emoji = _avatarEmojis[avatarIndex]['emoji'] as String;

    await _db.collection(_collection).doc(code).set({
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': riderId,
      'active': true,
    });

    await _db
        .collection(_collection)
        .doc(code)
        .collection('riders')
        .doc(riderId)
        .set({'name': name, 'emoji': emoji, 'lat': 0, 'lng': 0, 'speed': 0});

    _activeCode = code;
    _startPersistentGPS();
    return code;
  }

  /// Join an existing group ride
  static Future<bool> joinGroupRide(String code) async {
    try {
      final doc =
          await _db.collection(_collection).doc(code.toUpperCase()).get();
      if (!doc.exists) return false;

      final prefs = await SharedPreferences.getInstance();
      final riderId = prefs.getString('rider_id') ?? _generateRiderId(prefs);
      final name = prefs.getString('rider_name') ?? 'Rider';
      final avatarIndex = prefs.getInt('rider_avatar') ?? 0;
      final emoji = _avatarEmojis[avatarIndex]['emoji'] as String;

      await _db
          .collection(_collection)
          .doc(code.toUpperCase())
          .collection('riders')
          .doc(riderId)
          .set({'name': name, 'emoji': emoji, 'lat': 0, 'lng': 0, 'speed': 0});

      _activeCode = code.toUpperCase();
      _startPersistentGPS();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Update this rider's position in the group
  static Future<void> updatePosition(
      String code, double lat, double lng, double speedKmh) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final riderId = prefs.getString('rider_id') ?? '';
      if (riderId.isEmpty) return;

      await _db
          .collection(_collection)
          .doc(code)
          .collection('riders')
          .doc(riderId)
          .update({
        'lat': lat,
        'lng': lng,
        'speed': speedKmh,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  /// Stream all rider positions in a group
  static Stream<List<RiderPosition>> streamRiders(String code) {
    return _db
        .collection(_collection)
        .doc(code)
        .collection('riders')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => RiderPosition.fromMap(doc.id, doc.data()))
          .toList();
    });
  }

  /// Trigger an SOS alert visible to all riders in the active group
  static Future<void> triggerSOS(double lat, double lng) async {
    if (_activeCode == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final riderId = prefs.getString('rider_id') ?? '';
      final name = prefs.getString('rider_name') ?? 'Rider';
      final avatarIndex = prefs.getInt('rider_avatar') ?? 0;
      final emoji = _avatarEmojis[avatarIndex]['emoji'] as String;

      await _db
          .collection(_collection)
          .doc(_activeCode)
          .collection('sos')
          .doc(riderId)
          .set({
        'name': name,
        'emoji': emoji,
        'lat': lat,
        'lng': lng,
        'active': true,
        'triggeredAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  /// Cancel own SOS alert
  static Future<void> cancelSOS() async {
    if (_activeCode == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final riderId = prefs.getString('rider_id') ?? '';
      await _db
          .collection(_collection)
          .doc(_activeCode)
          .collection('sos')
          .doc(riderId)
          .update({'active': false});
    } catch (_) {}
  }

  /// Stream active SOS alerts for a group ride
  static Stream<List<Map<String, dynamic>>> streamSOS(String code) {
    return _db
        .collection(_collection)
        .doc(code)
        .collection('sos')
        .where('active', isEqualTo: true)
        .snapshots()
        .map((s) => s.docs
            .map((d) => <String, dynamic>{...d.data(), 'id': d.id})
            .toList());
  }

  // ── Quick group alerts ─────────────────────────────────────────────────────

  static const List<Map<String, String>> quickAlerts = [
    {'emoji': '⛽', 'message': 'Need fuel'},
    {'emoji': '🐢', 'message': 'Slowing down'},
    {'emoji': '🅿️', 'message': 'Pull over ahead'},
    {'emoji': '✅', 'message': 'All good'},
    {'emoji': '⚠️', 'message': 'Hazard on road'},
    {'emoji': '🚔', 'message': 'Police ahead'},
  ];

  /// Broadcast a quick alert to all riders in the active group.
  static Future<void> broadcastAlert(String message, String emoji) async {
    if (_activeCode == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final riderId = prefs.getString('rider_id') ?? '';
      final name = prefs.getString('rider_name') ?? 'Rider';
      final avatarIndex = prefs.getInt('rider_avatar') ?? 0;
      final senderEmoji = _avatarEmojis[avatarIndex]['emoji'] as String;

      await _db
          .collection(_collection)
          .doc(_activeCode)
          .collection('alerts')
          .add({
        'riderId': riderId,
        'name': name,
        'emoji': senderEmoji,
        'alertEmoji': emoji,
        'message': message,
        'sentAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  /// Stream the latest quick alerts (newest first) for a group ride.
  static Stream<List<Map<String, dynamic>>> streamAlerts(String code) {
    return _db
        .collection(_collection)
        .doc(code)
        .collection('alerts')
        .orderBy('sentAt', descending: true)
        .limit(30)
        .snapshots()
        .map((s) => s.docs
            .map((d) => <String, dynamic>{...d.data(), 'id': d.id})
            .toList());
  }

  /// Leave a group ride — stops GPS and removes rider from room
  static Future<void> leaveGroupRide(String code) async {
    _activeCode = null;
    _gpsSubscription?.cancel();
    _gpsSubscription = null;

    try {
      final prefs = await SharedPreferences.getInstance();
      final riderId = prefs.getString('rider_id') ?? '';
      if (riderId.isEmpty) return;
      await _db
          .collection(_collection)
          .doc(code)
          .collection('riders')
          .doc(riderId)
          .delete();
    } catch (_) {}
  }

  /// Starts a background GPS stream that pushes position to Firestore.
  /// Survives screen navigation — only stops when leaveGroupRide() is called.
  static void _startPersistentGPS() {
    _gpsSubscription?.cancel();
    _gpsSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
      ),
    ).listen((pos) {
      if (_activeCode != null) {
        updatePosition(
          _activeCode!,
          pos.latitude,
          pos.longitude,
          (pos.speed * 3.6).clamp(0, 300),
        );
      }
    });
  }

  static String _generateRiderId(SharedPreferences prefs) {
    final id =
        'rider_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}';
    prefs.setString('rider_id', id);
    return id;
  }
}
