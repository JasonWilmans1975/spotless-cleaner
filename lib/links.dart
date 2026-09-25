import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Directions to [address] in the phone's maps app: Apple Maps on iOS,
/// Google Maps elsewhere.
Uri mapsUri(String address, {TargetPlatform? platform}) {
  final ios = (platform ?? defaultTargetPlatform) == TargetPlatform.iOS;
  return ios
      ? Uri.https('maps.apple.com', '/', {'daddr': address})
      : Uri.https('www.google.com', '/maps/dir/', {'api': '1', 'destination': address});
}

/// Opens directions to [address]; false if nothing could open it.
Future<bool> openDirections(String address) async {
  try {
    return await launchUrl(mapsUri(address), mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

/// Starts a call to [phone] (spaces and dashes are fine); false if the device can't.
Future<bool> callPhone(String phone) async {
  final digits = phone.replaceAll(RegExp(r'[^0-9+]'), '');
  if (digits.isEmpty) return false;
  try {
    return await launchUrl(Uri(scheme: 'tel', path: digits));
  } catch (_) {
    return false;
  }
}
