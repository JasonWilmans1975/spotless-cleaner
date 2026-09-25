import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Identifies the app to OpenStreetMap's services, which their usage policies
/// require (tiles and Nominatim both reject anonymous clients).
const kOsmUserAgent = 'SpotlessCleaner/1.0 (com.example.spotlessCleanerApp)';

/// The first result's coordinates from a Nominatim `format=jsonv2` search
/// response, or null if there were none / it doesn't parse.
LatLng? parseNominatim(String body) {
  try {
    final list = jsonDecode(body);
    if (list is! List || list.isEmpty) return null;
    final first = list.first as Map<String, dynamic>;
    final lat = double.tryParse('${first['lat']}');
    final lon = double.tryParse('${first['lon']}');
    return lat == null || lon == null ? null : LatLng(lat, lon);
  } catch (_) {
    return null;
  }
}

final _cache = <String, LatLng?>{};
DateTime? _lastRequest;

/// Where [address] is, via OpenStreetMap's free Nominatim geocoder — for the
/// Job details map. Results (including "not found") are cached for the app
/// session, and requests are spaced at least a second apart, per Nominatim's
/// usage policy. Network errors return null without caching, so a later
/// visit can try again.
///
/// ponytail: in-memory cache + a simple 1s gap — fine for one cleaner opening
/// jobs; store coordinates on the booking if lookups ever get heavy.
Future<LatLng?> geocodeAddress(String address, {http.Client? client}) async {
  final key = address.trim().toLowerCase();
  if (key.isEmpty) return null;
  if (_cache.containsKey(key)) return _cache[key];

  final since = _lastRequest == null ? null : DateTime.now().difference(_lastRequest!);
  if (since != null && since < const Duration(seconds: 1)) {
    await Future<void>.delayed(const Duration(seconds: 1) - since);
  }
  _lastRequest = DateTime.now();

  final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
    'q': address,
    'format': 'jsonv2',
    'limit': '1',
  });
  try {
    final get = client?.get ?? http.get;
    final res = await get(uri, headers: {'User-Agent': kOsmUserAgent}).timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) return null;
    return _cache[key] = parseNominatim(res.body);
  } catch (_) {
    return null;
  }
}
