import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase project URL and anon key, read from the gitignored `.env` at the
/// repo root (loaded in main.dart). Copy `.env.example` to `.env` and fill in.
///
/// The anon key is public by design and is meant to be guarded by row-level
/// security on the tables — never put a service-role key in `.env`, it would
/// ship inside the app bundle.
String get kSupabaseUrl => dotenv.env['SUPABASE_URL'] ?? '';
String get kSupabaseAnonKey => dotenv.env['SUPABASE_ANON_KEY'] ?? '';

/// Storage bucket holding cleaner profile photos, as `<cleaners.id>.<ext>`.
/// Created by the migration in spotless-cleaning/supabase/migrations.
const String kAvatarBucket = 'cleaner-avatars';

/// Thrown for any API error — network failure, a rejected query, or a row
/// that isn't the shape we expect. `message` is safe to show to the user.
class ApiException implements Exception {
  final String message;
  ApiException(this.message);

  @override
  String toString() => message;
}

/// Postgres stores several of these flags as integer 1/0 rather than boolean,
/// so accept either shape.
bool _asBool(dynamic v) => v == true || v == 1;

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

  /// The avatar as something [NetworkImage] can actually load. Photos uploaded
  /// through the app are absolute Supabase Storage URLs; the seeded rows hold
  /// server-relative paths like '/images/avatars/sw.png' that nothing serves
  /// any more, so those read as "no photo" and fall back to initials.
  String? get avatarUrl =>
      (avatar != null && avatar!.startsWith('http')) ? avatar : null;

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
      active: _asBool(json['active']),
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

/// One entry in a cleaner's rate-change history. [serviceName], [priceType] and
/// [defaultPriceCents] come from the joined `services` row.
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
    final service = json['services'] as Map<String, dynamic>? ?? const {};
    return PriceHistoryEntry(
      id: json['id'] as int,
      serviceId: json['service_id'] as int,
      serviceName: service['name'] as String? ?? '',
      priceType: service['price_type'] as String? ?? 'hourly',
      defaultPriceCents: (service['price_cents'] as num?)?.toInt() ?? 0,
      oldPriceCents: (json['old_price_cents'] as num?)?.toInt(),
      newPriceCents: (json['new_price_cents'] as num?)?.toInt(),
      changedBy: json['changed_by'] as String? ?? 'admin',
      changedAt: json['changed_at']?.toString() ?? '',
    );
  }
}

/// One of the logged-in cleaner's assigned bookings. [serviceName] comes from
/// the joined `services` row.
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
    final service = json['services'] as Map<String, dynamic>? ?? const {};
    return CleanerBooking(
      id: json['id'] as int,
      ref: json['ref'] as String? ?? '',
      serviceName: service['name'] as String? ?? '',
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
/// they're off that day.
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

/// Cleaner-facing data access, talking straight to Supabase — Auth for
/// sign-up/sign-in, PostgREST for the tables, Storage for profile photos.
///
/// The session is persisted by supabase_flutter itself, so there's no token to
/// hold on to here. A cleaner's `auth.users` row is tied to their `cleaners`
/// row by `cleaners.auth_user_id`; [_cleanerId] resolves one to the other.
class ApiClient {
  SupabaseClient get _db => Supabase.instance.client;

  /// Runs [body], turning anything Supabase throws into an [ApiException] whose
  /// message is safe to put in front of a user.
  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on ApiException {
      rethrow;
    } on AuthException catch (e) {
      throw ApiException(e.message);
    } on PostgrestException catch (e) {
      throw ApiException(e.message);
    } on StorageException catch (e) {
      throw ApiException(e.message);
    } catch (_) {
      throw ApiException(
        "Couldn't reach Supabase at $kSupabaseUrl. Check your connection, and that "
        "SUPABASE_URL / SUPABASE_ANON_KEY in .env are right.",
      );
    }
  }

  /// The `cleaners.id` for the signed-in user. Throws if nobody is signed in,
  /// or if their auth account has no matching cleaner row.
  Future<int> _cleanerId() async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) throw ApiException('You need to sign in again.');
    final row = await _db.from('cleaners').select('id').eq('auth_user_id', userId).maybeSingle();
    if (row == null) throw ApiException('No cleaner profile is linked to this account.');
    return row['id'] as int;
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
    return _guard(() async {
      final auth = await _db.auth.signUp(email: email, password: password);
      final userId = auth.user?.id;
      if (userId == null) {
        throw ApiException('Check your inbox to confirm your email address, then sign in.');
      }
      // New applicants start pending an admin review, same as the web signup.
      final row = await _db.from('cleaners').insert({
        'auth_user_id': userId,
        'name': name,
        'email': email,
        'phone': phone,
        'address': address,
        'postcode': postcode,
        'initials': _initials(name),
        'status': 'pending',
        'active': 0,
      }).select().single();
      return Cleaner.fromJson(row);
    });
  }

  Future<Cleaner> login({required String email, required String password}) async {
    return _guard(() async {
      await _db.auth.signInWithPassword(email: email, password: password);
      final cleaner = await me();
      if (cleaner == null) throw ApiException('No cleaner profile is linked to this account.');
      return cleaner;
    });
  }

  Future<void> logout() async {
    try {
      await _db.auth.signOut();
    } catch (_) {
      // Best-effort — the local session is cleared either way.
    }
  }

  /// Returns null if there's no session, or the session's user has no cleaner row.
  Future<Cleaner?> me() async {
    return _guard(() async {
      final userId = _db.auth.currentUser?.id;
      if (userId == null) return null;
      final row = await _db.from('cleaners').select().eq('auth_user_id', userId).maybeSingle();
      return row == null ? null : Cleaner.fromJson(row);
    });
  }

  // ---- Profile ----

  Future<Cleaner> updateProfile({String? phone, String? address, String? postcode}) async {
    return _guard(() async {
      final id = await _cleanerId();
      final row = await _db
          .from('cleaners')
          .update({
            if (phone != null) 'phone': phone,
            if (address != null) 'address': address,
            if (postcode != null) 'postcode': postcode,
          })
          .eq('id', id)
          .select()
          .single();
      return Cleaner.fromJson(row);
    });
  }

  /// Replaces this cleaner's whole set of offered services + rates in one go —
  /// same contract the website uses, so every change (add one, remove one,
  /// edit a rate) sends the full current list. Rate changes are written to
  /// `cleaner_price_history` so the history screen stays accurate.
  ///
  /// ponytail: delete-then-insert rather than one transaction — PostgREST has no
  /// client-side multi-statement transaction. A failure between the two leaves
  /// the cleaner with no services; move this into a Postgres RPC if that matters.
  Future<void> updateMyServices(List<MyServiceRate> services) async {
    return _guard(() async {
      final id = await _cleanerId();
      final existing = await _db
          .from('cleaner_services')
          .select('service_id, price_cents')
          .eq('cleaner_id', id);
      final oldRates = {
        for (final r in existing) r['service_id'] as int: (r['price_cents'] as num?)?.toInt(),
      };

      await _db.from('cleaner_services').delete().eq('cleaner_id', id);
      if (services.isNotEmpty) {
        await _db.from('cleaner_services').insert([
          for (final s in services)
            {'cleaner_id': id, 'service_id': s.serviceId, 'price_cents': s.priceCents},
        ]);
      }

      final changes = [
        for (final s in services)
          if (!oldRates.containsKey(s.serviceId) || oldRates[s.serviceId] != s.priceCents)
            {
              'cleaner_id': id,
              'service_id': s.serviceId,
              'old_price_cents': oldRates[s.serviceId],
              'new_price_cents': s.priceCents,
              'changed_by': 'cleaner',
            },
      ];
      if (changes.isNotEmpty) await _db.from('cleaner_price_history').insert(changes);
    });
  }

  /// Uploads a profile photo already read into memory as [imageBytes], with
  /// [extension] one of png/jpg/jpeg/webp/gif. Stores it in the [kAvatarBucket]
  /// Storage bucket and returns its public URL.
  Future<String> uploadPhoto(List<int> imageBytes, String extension) async {
    final mimeByExt = {'png': 'png', 'jpg': 'jpeg', 'jpeg': 'jpeg', 'webp': 'webp', 'gif': 'gif'};
    final mime = mimeByExt[extension.toLowerCase()];
    if (mime == null) throw ApiException('Please choose a PNG, JPG, WEBP or GIF image');
    return _guard(() async {
      final id = await _cleanerId();
      // One stable path per cleaner, overwritten on each upload, so old photos
      // don't pile up in the bucket.
      final path = '$id.$extension';
      await _db.storage.from(kAvatarBucket).uploadBinary(
            path,
            Uint8List.fromList(imageBytes),
            fileOptions: FileOptions(contentType: 'image/$mime', upsert: true),
          );
      // Cache-bust, or the CDN keeps serving the previous photo at this path.
      final url = '${_db.storage.from(kAvatarBucket).getPublicUrl(path)}'
          '?v=${DateTime.now().millisecondsSinceEpoch}';
      await _db.from('cleaners').update({'avatar': url}).eq('id', id);
      return url;
    });
  }

  // ---- Services & rates ----

  /// The full active, approved service menu — same list customers book from.
  Future<List<MenuService>> getServices() async {
    return _guard(() async {
      final rows = await _db
          .from('services')
          .select()
          .eq('status', 'approved')
          .eq('active', 1)
          .order('sort_order');
      return rows.map(MenuService.fromJson).toList();
    });
  }

  /// This cleaner's own rate rows — cross-reference against [getServices] by id
  /// to know which services they offer and at what rate.
  Future<List<MyServiceRate>> getMyServiceRates() async {
    return _guard(() async {
      final id = await _cleanerId();
      final rows =
          await _db.from('cleaner_services').select('service_id, price_cents').eq('cleaner_id', id);
      return rows.map(MyServiceRate.fromJson).toList();
    });
  }

  /// Services this cleaner proposed themselves that are still awaiting admin review.
  Future<List<MenuService>> getPendingProposedServices() async {
    return _guard(() async {
      final id = await _cleanerId();
      final rows = await _db
          .from('services')
          .select()
          .eq('created_by_cleaner_id', id)
          .eq('status', 'pending')
          .order('id');
      return rows.map(MenuService.fromJson).toList();
    });
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
    return _guard(() async {
      final id = await _cleanerId();
      final row = await _db.from('services').insert({
        'name': name,
        'slug': _slugify(name),
        'icon': icon,
        'description': description,
        'price_type': priceType,
        'price_cents': (price * 100).round(),
        'duration_minutes': durationMinutes ?? 60,
        'duration_label': durationLabel,
        'features': jsonEncode(features),
        'status': 'pending',
        'active': 1,
        'created_by_cleaner_id': id,
      }).select('id').single();
      final serviceId = row['id'] as int;
      await _db
          .from('cleaner_services')
          .insert({'cleaner_id': id, 'service_id': serviceId, 'price_cents': null});
      return serviceId;
    });
  }

  /// Edits the full details of a service this cleaner proposed themselves —
  /// name, icon, description, pricing, duration, and features. The
  /// `created_by_cleaner_id` filter is what keeps this to their own proposals;
  /// works whether the proposal is still pending review or already approved and
  /// live, and doesn't change approval status either way.
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
    return _guard(() async {
      final id = await _cleanerId();
      final row = await _db
          .from('services')
          .update({
            'name': name,
            'icon': icon,
            'description': description,
            'price_type': priceType,
            'price_cents': (price * 100).round(),
            'duration_minutes': durationMinutes ?? 60,
            'duration_label': durationLabel,
            'features': jsonEncode(features),
          })
          .eq('id', serviceId)
          .eq('created_by_cleaner_id', id)
          .select()
          .maybeSingle();
      if (row == null) throw ApiException("That's not one of your own proposed services.");
      return MenuService.fromJson(row);
    });
  }

  Future<List<PriceHistoryEntry>> getPriceHistory() async {
    return _guard(() async {
      final id = await _cleanerId();
      final rows = await _db
          .from('cleaner_price_history')
          .select('*, services(name, price_type, price_cents)')
          .eq('cleaner_id', id)
          .order('changed_at', ascending: false);
      return rows.map(PriceHistoryEntry.fromJson).toList();
    });
  }

  // ---- Working hours ----

  /// This cleaner's weekly working hours — a weekday missing from the list means
  /// they're off that day.
  Future<List<WorkingHours>> getMyHours() async {
    return _guard(() async {
      final id = await _cleanerId();
      final rows = await _db
          .from('cleaner_hours')
          .select('weekday, start_time, end_time')
          .eq('cleaner_id', id)
          .order('weekday');
      return rows.map(WorkingHours.fromJson).toList();
    });
  }

  /// Replaces this cleaner's whole weekly schedule in one go — send every day
  /// they work, including ones that didn't change; omit a day entirely to mark
  /// it as off.
  ///
  /// ponytail: same delete-then-insert caveat as [updateMyServices].
  Future<void> updateMyHours(List<WorkingHours> hours) async {
    return _guard(() async {
      final id = await _cleanerId();
      await _db.from('cleaner_hours').delete().eq('cleaner_id', id);
      if (hours.isEmpty) return;
      await _db.from('cleaner_hours').insert([
        for (final h in hours)
          {
            'cleaner_id': id,
            'weekday': h.weekday,
            'start_time': h.startTime,
            'end_time': h.endTime,
          },
      ]);
    });
  }

  // ---- Bookings ----

  Future<List<CleanerBooking>> getMyBookings() async {
    return _guard(() async {
      final id = await _cleanerId();
      final rows = await _db
          .from('bookings')
          .select('*, services(name)')
          .eq('cleaner_id', id)
          .order('date', ascending: false)
          .order('start_time', ascending: false);
      return rows.map(CleanerBooking.fromJson).toList();
    });
  }

  Future<void> confirmBooking(int bookingId) => _setBookingStatus(bookingId, 'confirmed');

  Future<void> declineBooking(int bookingId) => _setBookingStatus(bookingId, 'cancelled');

  /// The `cleaner_id` filter is what stops a cleaner acting on someone else's
  /// booking, so it has to stay on both of these.
  Future<void> _setBookingStatus(int bookingId, String status) async {
    return _guard(() async {
      final id = await _cleanerId();
      final row = await _db
          .from('bookings')
          .update({'status': status})
          .eq('id', bookingId)
          .eq('cleaner_id', id)
          .select('id')
          .maybeSingle();
      if (row == null) throw ApiException("That booking isn't assigned to you.");
    });
  }
}

/// 'Sarah Wilson' -> 'SW'. Matches the `initials` the seeded cleaner rows use.
String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
  return parts.take(2).map((p) => p[0].toUpperCase()).join();
}

/// 'Deep Oven Clean' -> 'deep-oven-clean-<suffix>'. The suffix keeps two cleaners
/// proposing the same name from colliding on the unique slug.
String _slugify(String name) {
  final base = name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  final suffix = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  return base.isEmpty ? 'service-$suffix' : '$base-$suffix';
}
