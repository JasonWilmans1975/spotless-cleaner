import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Where the Spotless Solutions server lives — same rules as the customer app:
///
/// - Android emulator: use 'http://10.0.2.2:3000' (the emulator's alias for
///   your Mac's localhost).
/// - iOS Simulator: 'http://localhost:3000' works directly.
/// - A physical phone: use your Mac's LAN IP, e.g. 'http://192.168.1.23:3000',
///   with the phone on the same Wi-Fi network as your Mac.
const String kApiBaseUrl = 'http://localhost:3000';

/// Thrown for any API error — network failure, non-2xx response, or a body
/// that isn't the JSON shape we expect. `message` is safe to show to the user.
class ApiException implements Exception {
  final String message;
  ApiException(this.message);

  @override
  String toString() => message;
}

/// The logged-in cleaner's own profile.
class Cleaner {
  final int id;
  final String name;
  final String? email;
  final String? phone;
  final String? address;
  final String? postcode;
  final String? avatar;
  final String status; // 'pending' | 'approved'
  final bool active;

  bool get isPendingApproval => status == 'pending';

  Cleaner({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.address,
    required this.postcode,
    required this.avatar,
    required this.status,
    required this.active,
  });

  factory Cleaner.fromJson(Map<String, dynamic> json) {
    return Cleaner(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      email: json['email'] as String?,
      phone: json['phone'] as String?,
      address: json['address'] as String?,
      postcode: json['postcode'] as String?,
      avatar: json['avatar'] as String?,
      status: json['status'] as String? ?? 'pending',
      active: json['active'] as bool? ?? false,
    );
  }
}

/// A service on the business's menu — either one already approved and bookable,
/// or one this cleaner proposed themselves that's still awaiting admin review
/// (in which case [status] is 'pending' and it won't appear in [ApiClient.getServices]).
class MenuService {
  final int id;
  final String name;
  final String slug;
  final String description;
  final String priceType; // 'hourly' or 'fixed'
  final int priceCents; // the service's default/listed price
  final int durationMinutes;
  final String durationLabel;
  final String icon;
  final List<String> features;
  final String? badge;
  final String status;
  final int? createdByCleanerId; // non-null = this cleaner proposed it themselves

  bool get isHourly => priceType == 'hourly';

  MenuService({
    required this.id,
    required this.name,
    required this.slug,
    required this.description,
    required this.priceType,
    required this.priceCents,
    required this.durationMinutes,
    required this.durationLabel,
    required this.icon,
    required this.features,
    required this.badge,
    required this.status,
    required this.createdByCleanerId,
  });

  factory MenuService.fromJson(Map<String, dynamic> json) {
    // `features` is stored as a JSON-encoded string in Postgres, so it needs a
    // second decode — same as the customer app's Service model.
    var features = <String>[];
    final rawFeatures = json['features'];
    if (rawFeatures is String) {
      try {
        final decoded = jsonDecode(rawFeatures);
        if (decoded is List) features = decoded.map((e) => e.toString()).toList();
      } catch (_) {
        // Leave features empty rather than crash the whole list.
      }
    } else if (rawFeatures is List) {
      features = rawFeatures.map((e) => e.toString()).toList();
    }
    return MenuService(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      slug: json['slug'] as String? ?? '',
      description: json['description'] as String? ?? '',
      priceType: json['price_type'] as String? ?? 'hourly',
      priceCents: (json['price_cents'] as num?)?.toInt() ?? 0,
      durationMinutes: (json['duration_minutes'] as num?)?.toInt() ?? 60,
      durationLabel: json['duration_label'] as String? ?? '',
      icon: json['icon'] as String? ?? '✦',
      features: features,
      badge: json['badge'] as String?,
      status: json['status'] as String? ?? 'approved',
      createdByCleanerId: (json['created_by_cleaner_id'] as num?)?.toInt(),
    );
  }
}

/// One row of a cleaner's own rate for a service they offer — [priceCents]
/// null means they're using the service's default price rather than a
/// personal override.
class MyServiceRate {
  final int serviceId;
  final int? priceCents;

  MyServiceRate({required this.serviceId, required this.priceCents});

  factory MyServiceRate.fromJson(Map<String, dynamic> json) {
    return MyServiceRate(
      serviceId: json['service_id'] as int,
      priceCents: (json['price_cents'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() => {'id': serviceId, 'priceCents': priceCents};
}

/// One entry in a cleaner's rate-change history.
class PriceHistoryEntry {
  final int id;
  final int serviceId;
  final String serviceName;
  final String priceType;
  final int defaultPriceCents;
  final int? oldPriceCents;
  final int? newPriceCents;
  final String changedBy; // 'cleaner' | 'admin'
  final String changedAt; // ISO 8601

  PriceHistoryEntry({
    required this.id,
    required this.serviceId,
    required this.serviceName,
    required this.priceType,
    required this.defaultPriceCents,
    required this.oldPriceCents,
    required this.newPriceCents,
    required this.changedBy,
    required this.changedAt,
  });

  factory PriceHistoryEntry.fromJson(Map<String, dynamic> json) {
    return PriceHistoryEntry(
      id: json['id'] as int,
      serviceId: json['service_id'] as int,
      serviceName: json['service_name'] as String? ?? '',
      priceType: json['price_type'] as String? ?? 'hourly',
      defaultPriceCents: (json['default_price_cents'] as num?)?.toInt() ?? 0,
      oldPriceCents: (json['old_price_cents'] as num?)?.toInt(),
      newPriceCents: (json['new_price_cents'] as num?)?.toInt(),
      changedBy: json['changed_by'] as String? ?? 'admin',
      changedAt: json['changed_at']?.toString() ?? '',
    );
  }
}

/// One of the logged-in cleaner's assigned bookings.
class CleanerBooking {
  final int id;
  final String ref;
  final String serviceName;
  final String date; // 'YYYY-MM-DD'
  final String startTime;
  final String endTime;
  final String status; // 'pending' | 'confirmed' | 'completed' | 'cancelled'
  final String customerName;
  final String address;
  final String postcode;
  final int priceCents;
  final String? customerComment;

  bool get isPast => status == 'completed' || status == 'cancelled';

  CleanerBooking({
    required this.id,
    required this.ref,
    required this.serviceName,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.status,
    required this.customerName,
    required this.address,
    required this.postcode,
    required this.priceCents,
    required this.customerComment,
  });

  factory CleanerBooking.fromJson(Map<String, dynamic> json) {
    return CleanerBooking(
      id: json['id'] as int,
      ref: json['ref'] as String? ?? '',
      serviceName: json['service_name'] as String? ?? '',
      date: json['date'] as String? ?? '',
      startTime: json['start_time'] as String? ?? '',
      endTime: json['end_time'] as String? ?? '',
      status: json['status'] as String? ?? '',
      customerName: json['customer_name'] as String? ?? '',
      address: json['address'] as String? ?? '',
      postcode: json['postcode'] as String? ?? '',
      priceCents: (json['price_cents'] as num?)?.toInt() ?? 0,
      customerComment: json['customer_comment'] as String?,
    );
  }
}

/// One day of a cleaner's weekly working hours — a weekday (0=Mon..6=Sun) they're
/// available to be booked, with a start/end time. A weekday with no row means
/// they're off that day. `start`/`end` are what the server's PUT endpoint expects;
/// GET returns `start_time`/`end_time` instead — [fromJson] reads the GET shape,
/// [toJson] writes the PUT shape.
class WorkingHours {
  final int weekday;
  final String startTime; // 'HH:MM'
  final String endTime; // 'HH:MM'

  WorkingHours({required this.weekday, required this.startTime, required this.endTime});

  factory WorkingHours.fromJson(Map<String, dynamic> json) {
    return WorkingHours(
      weekday: json['weekday'] as int,
      startTime: json['start_time'] as String? ?? '',
      endTime: json['end_time'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {'weekday': weekday, 'start': startTime, 'end': endTime};
}

/// Thin wrapper around the Spotless Solutions JSON API's cleaner-facing routes.
///
/// Every authenticated request sends the stored session token as
/// "Authorization: Bearer <token>" — same contract as the customer app, see
/// src/auth.js on the server (cleanerTokenFromReq checks that header first,
/// then falls back to the website's ss_cleaner cookie).
class ApiClient {
  static const _tokenKey = 'ss_cleaner_token';

  Future<String?> _readToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  Future<void> _saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  Future<void> _clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }

  Map<String, dynamic> _decode(http.Response res) {
    Map<String, dynamic> body;
    try {
      body = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      throw ApiException(
        'The server sent back something unexpected (status ${res.statusCode}). '
            'Double-check kApiBaseUrl in api_client.dart and that the server is running.',
      );
    }
    if (res.statusCode >= 400) {
      throw ApiException(body['error'] as String? ?? 'Something went wrong (status ${res.statusCode}).');
    }
    return body;
  }

  Future<http.Response> _safeRequest(Future<http.Response> Function() send) async {
    try {
      return await send();
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException("Couldn't reach the server at $kApiBaseUrl. Is it running, and is the address right for how you're testing?");
    }
  }

  Future<Map<String, String>> _authHeaders({bool json = true}) async {
    final token = await _readToken();
    return {
      if (json) 'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // ---- Auth ----

  Future<Cleaner> register({
    required String name,
    required String email,
    required String password,
    required String phone,
    required String address,
    required String postcode,
  }) async {
    final res = await _safeRequest(() => http.post(
      Uri.parse('$kApiBaseUrl/api/cleaner/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': name, 'email': email, 'password': password,
        'phone': phone, 'address': address, 'postcode': postcode,
      }),
    ));
    final body = _decode(res);
    await _saveToken(body['token'] as String);
    return Cleaner.fromJson(body['cleaner'] as Map<String, dynamic>);
  }

  Future<Cleaner> login({required String email, required String password}) async {
    final res = await _safeRequest(() => http.post(
      Uri.parse('$kApiBaseUrl/api/cleaner/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    ));
    final body = _decode(res);
    await _saveToken(body['token'] as String);
    return Cleaner.fromJson(body['cleaner'] as Map<String, dynamic>);
  }

  Future<void> logout() async {
    final token = await _readToken();
    if (token != null) {
      try {
        await http.post(
          Uri.parse('$kApiBaseUrl/api/cleaner/auth/logout'),
          headers: {'Authorization': 'Bearer $token'},
        );
      } catch (_) {
        // Best-effort — proceed to clear the local token regardless.
      }
    }
    await _clearToken();
  }

  /// Returns null if there's no session, or if the stored token is no longer valid.
  Future<Cleaner?> me() async {
    final token = await _readToken();
    if (token == null) return null;
    final res = await _safeRequest(() => http.get(
      Uri.parse('$kApiBaseUrl/api/cleaner/me'),
      headers: {'Authorization': 'Bearer $token'},
    ));
    final body = _decode(res);
    final cleanerJson = body['cleaner'];
    if (cleanerJson == null) {
      await _clearToken();
      return null;
    }
    return Cleaner.fromJson(cleanerJson as Map<String, dynamic>);
  }

  // ---- Profile ----

  Future<Cleaner> updateProfile({String? phone, String? address, String? postcode}) async {
    final headers = await _authHeaders();
    final res = await _safeRequest(() => http.patch(
      Uri.parse('$kApiBaseUrl/api/cleaner/me'),
      headers: headers,
      body: jsonEncode({
        if (phone != null) 'phone': phone,
        if (address != null) 'address': address,
        if (postcode != null) 'postcode': postcode,
      }),
    ));
    final body = _decode(res);
    return Cleaner.fromJson(body['cleaner'] as Map<String, dynamic>);
  }

  /// Replaces this cleaner's whole set of offered services + rates in one go —
  /// same contract the website uses, so every change (add one, remove one,
  /// edit a rate) sends the full current list.
  Future<void> updateMyServices(List<MyServiceRate> services) async {
    final headers = await _authHeaders();
    final res = await _safeRequest(() => http.patch(
      Uri.parse('$kApiBaseUrl/api/cleaner/me'),
      headers: headers,
      body: jsonEncode({'services': services.map((s) => s.toJson()).toList()}),
    ));
    _decode(res);
  }

  /// Uploads a profile photo already read into memory as [imageBytes], with
  /// [extension] one of png/jpg/jpeg/webp/gif (matches what the server accepts).
  /// Returns the new avatar URL.
  Future<String> uploadPhoto(List<int> imageBytes, String extension) async {
    final mimeByExt = {'png': 'png', 'jpg': 'jpeg', 'jpeg': 'jpeg', 'webp': 'webp', 'gif': 'gif'};
    final mime = mimeByExt[extension.toLowerCase()];
    if (mime == null) throw ApiException('Please choose a PNG, JPG, WEBP or GIF image');
    final dataUrl = 'data:image/$mime;base64,${base64Encode(imageBytes)}';
    final headers = await _authHeaders();
    final res = await _safeRequest(() => http.post(
      Uri.parse('$kApiBaseUrl/api/cleaner/me/photo'),
      headers: headers,
      body: jsonEncode({'imageDataUrl': dataUrl}),
    ));
    final body = _decode(res);
    return body['avatar'] as String;
  }

  // ---- Services & rates ----

  /// The full active, approved service menu — same list customers book from.
  Future<List<MenuService>> getServices() async {
    final res = await _safeRequest(() => http.get(Uri.parse('$kApiBaseUrl/api/services')));
    final body = _decode(res);
    final list = body['services'] as List<dynamic>? ?? [];
    return list.map((s) => MenuService.fromJson(s as Map<String, dynamic>)).toList();
  }

  /// This cleaner's own rate rows — cross-reference against [getServices] by id
  /// to know which services they offer and at what rate.
  Future<List<MyServiceRate>> getMyServiceRates() async {
    final headers = await _authHeaders(json: false);
    final res = await _safeRequest(() => http.get(
      Uri.parse('$kApiBaseUrl/api/cleaner/me/services'),
      headers: headers,
    ));
    final body = _decode(res);
    final list = body['services'] as List<dynamic>? ?? [];
    return list.map((s) => MyServiceRate.fromJson(s as Map<String, dynamic>)).toList();
  }

  /// Services this cleaner proposed themselves that are still awaiting admin review.
  Future<List<MenuService>> getPendingProposedServices() async {
    final headers = await _authHeaders(json: false);
    final res = await _safeRequest(() => http.get(
      Uri.parse('$kApiBaseUrl/api/cleaner/me/pending-services'),
      headers: headers,
    ));
    final body = _decode(res);
    final list = body['pendingServices'] as List<dynamic>? ?? [];
    return list.map((s) => MenuService.fromJson(s as Map<String, dynamic>)).toList();
  }

  /// Proposes a brand-new service not already on the menu — saved pending admin
  /// approval, and this cleaner is auto-enrolled to offer it once approved.
  Future<int> proposeService({
    required String name,
    required String icon,
    required String description,
    required String priceType,
    required double price,
    int? durationMinutes,
    String durationLabel = '',
    List<String> features = const [],
  }) async {
    final headers = await _authHeaders();
    final res = await _safeRequest(() => http.post(
      Uri.parse('$kApiBaseUrl/api/cleaner/me/services'),
      headers: headers,
      body: jsonEncode({
        'name': name,
        'icon': icon,
        'description': description,
        'priceType': priceType,
        'price': price,
        if (durationMinutes != null) 'durationMinutes': durationMinutes,
        'durationLabel': durationLabel,
        'features': features,
      }),
    ));
    final body = _decode(res);
    return body['id'] as int;
  }

  /// Edits the full details of a service this cleaner proposed themselves —
  /// name, icon, description, pricing, duration, and features. Only works for
  /// services with `created_by_cleaner_id` equal to this cleaner (the server
  /// enforces this too); works whether the proposal is still pending review
  /// or already approved and live. Does not touch approval status either way.
  Future<MenuService> updateProposedService({
    required int serviceId,
    required String name,
    required String icon,
    required String description,
    required String priceType,
    required double price,
    int? durationMinutes,
    String durationLabel = '',
    List<String> features = const [],
  }) async {
    final headers = await _authHeaders();
    final res = await _safeRequest(() => http.patch(
      Uri.parse('$kApiBaseUrl/api/cleaner/me/services/$serviceId'),
      headers: headers,
      body: jsonEncode({
        'name': name,
        'icon': icon,
        'description': description,
        'priceType': priceType,
        'price': price,
        if (durationMinutes != null) 'durationMinutes': durationMinutes,
        'durationLabel': durationLabel,
        'features': features,
      }),
    ));
    final body = _decode(res);
    return MenuService.fromJson(body['service'] as Map<String, dynamic>);
  }

  Future<List<PriceHistoryEntry>> getPriceHistory() async {
    final headers = await _authHeaders(json: false);
    final res = await _safeRequest(() => http.get(
      Uri.parse('$kApiBaseUrl/api/cleaner/me/price-history'),
      headers: headers,
    ));
    final body = _decode(res);
    final list = body['history'] as List<dynamic>? ?? [];
    return list.map((h) => PriceHistoryEntry.fromJson(h as Map<String, dynamic>)).toList();
  }

  // ---- Working hours ----

  /// This cleaner's weekly working hours — a weekday missing from the list means
  /// they're off that day.
  Future<List<WorkingHours>> getMyHours() async {
    final headers = await _authHeaders(json: false);
    final res = await _safeRequest(() => http.get(
      Uri.parse('$kApiBaseUrl/api/cleaner/me/hours'),
      headers: headers,
    ));
    final body = _decode(res);
    final list = body['hours'] as List<dynamic>? ?? [];
    return list.map((h) => WorkingHours.fromJson(h as Map<String, dynamic>)).toList();
  }

  /// Replaces this cleaner's whole weekly schedule in one go — send every day
  /// they work, including ones that didn't change; omit a day entirely to mark
  /// it as off.
  Future<void> updateMyHours(List<WorkingHours> hours) async {
    final headers = await _authHeaders();
    final res = await _safeRequest(() => http.put(
      Uri.parse('$kApiBaseUrl/api/cleaner/me/hours'),
      headers: headers,
      body: jsonEncode({'hours': hours.map((h) => h.toJson()).toList()}),
    ));
    _decode(res);
  }

  // ---- Bookings ----

  Future<List<CleanerBooking>> getMyBookings() async {
    final headers = await _authHeaders(json: false);
    final res = await _safeRequest(() => http.get(
      Uri.parse('$kApiBaseUrl/api/cleaner/bookings'),
      headers: headers,
    ));
    final body = _decode(res);
    final list = body['bookings'] as List<dynamic>? ?? [];
    return list.map((b) => CleanerBooking.fromJson(b as Map<String, dynamic>)).toList();
  }

  Future<void> confirmBooking(int bookingId) async {
    final headers = await _authHeaders(json: false);
    final res = await _safeRequest(() => http.post(
      Uri.parse('$kApiBaseUrl/api/cleaner/bookings/$bookingId/confirm'),
      headers: headers,
    ));
    _decode(res);
  }

  Future<void> declineBooking(int bookingId) async {
    final headers = await _authHeaders(json: false);
    final res = await _safeRequest(() => http.post(
      Uri.parse('$kApiBaseUrl/api/cleaner/bookings/$bookingId/decline'),
      headers: headers,
    ));
    _decode(res);
  }
}