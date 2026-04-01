import 'package:shared_preferences/shared_preferences.dart';

class UserPreferences {
  static const String _keyEmail = 'arny_email';
  static const String _keyUserId = 'arny_user_id';
  static const String _keyAccessToken = 'arny_access_token';
  static const String _keyAssistantName = 'arny_assistant_name';
  static const String _keyAutoStart = 'arny_auto_start';

  // We NEVER store passwords - only session tokens and user preferences
  
  static Future<void> saveUserSession({
    required String email,
    required String userId,
    required String accessToken,
    required String assistantName,
    required bool autoStart,
  }) async {
    print("[UserPreferences] Saving user session (email: $email, userId: $userId)");
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyEmail, email);
    await prefs.setString(_keyUserId, userId);
    await prefs.setString(_keyAccessToken, accessToken);
    await prefs.setString(_keyAssistantName, assistantName);
    await prefs.setBool(_keyAutoStart, autoStart);
  }

  static Future<Map<String, dynamic>?> loadUserSession() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString(_keyEmail);
    final userId = prefs.getString(_keyUserId);
    final accessToken = prefs.getString(_keyAccessToken);
    
    if (email == null || userId == null || accessToken == null) {
      print("[UserPreferences] No saved user session found");
      return null;
    }

    print("[UserPreferences] Loaded user session (email: $email, userId: $userId)");
    return {
      'email': email,
      'userId': userId,
      'accessToken': accessToken,
      'assistantName': prefs.getString(_keyAssistantName) ?? 'Arny',
      'autoStart': prefs.getBool(_keyAutoStart) ?? true,
    };
  }

  static Future<void> clearUserSession() async {
    print("[UserPreferences] Clearing user session");
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyEmail);
    await prefs.remove(_keyUserId);
    await prefs.remove(_keyAccessToken);
    await prefs.remove(_keyAssistantName);
    await prefs.remove(_keyAutoStart);
  }
}