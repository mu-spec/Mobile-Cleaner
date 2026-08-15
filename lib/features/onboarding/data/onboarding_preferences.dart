import 'package:shared_preferences/shared_preferences.dart';

abstract final class OnboardingPreferences {
  static const String _completedKey = 'onboarding_completed';

  static Future<bool> isCompleted() async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_completedKey) ?? false;
  }

  static Future<void> markCompleted() async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_completedKey, true);
  }

  static Future<void> reset() async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_completedKey, false);
  }
}
