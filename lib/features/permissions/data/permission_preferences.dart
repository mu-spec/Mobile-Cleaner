import 'package:shared_preferences/shared_preferences.dart';

abstract final class PermissionPreferences {
  static const String _educationSeenKey = 'permission_education_seen';

  static Future<bool> isEducationSeen() async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_educationSeenKey) ?? false;
  }

  static Future<void> markEducationSeen() async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_educationSeenKey, true);
  }
}
