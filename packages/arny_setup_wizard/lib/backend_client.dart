import 'dart:convert';
import 'package:http/http.dart' as http;

class BackendClient {
  static const String defaultBackendUrl = 'http://localhost:8000';

  static Future<Map<String, String>> signIn(String email, String password, {String backendUrl = defaultBackendUrl}) async {
    print("[BackendClient] Attempting to sign in to $backendUrl as $email...");
    final url = backendUrl.replaceAll(RegExp(r'/+$'), '');
    final response = await http.post(
      Uri.parse('$url/auth/signin'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'action': 'signin',
        'email': email,
        'password': password,
      }),
    );

    if (response.statusCode != 200) {
      print("[BackendClient] Sign in failed: HTTP ${response.statusCode} - ${response.body}");
      throw Exception("Sign in failed: HTTP ${response.statusCode}\n${response.body}");
    }

    final json = jsonDecode(response.body);
    final accessToken = json['data']?['session']?['access_token'];
    final userId = json['data']?['user']?['id'];

    if (accessToken == null || userId == null) {
      print("[BackendClient] Sign in succeeded but missing token or user ID in response.");
      throw Exception("Sign in succeeded but missing token or user ID.");
    }

    print("[BackendClient] Sign in successful. UserId: $userId");
    return {
      'accessToken': accessToken,
      'userId': userId,
    };
  }

  static Future<Map<String, dynamic>> fetchProfile(String accessToken, String userId, {String backendUrl = defaultBackendUrl}) async {
    print("[BackendClient] Fetching profile for user $userId...");
    final url = backendUrl.replaceAll(RegExp(r'/+$'), '');
    final response = await http.post(
      Uri.parse('$url/user/status'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
      body: jsonEncode({'user_id': userId}),
    );

    if (response.statusCode != 200) {
      print("[BackendClient] Profile fetch failed: HTTP ${response.statusCode}");
      throw Exception("Failed to fetch profile: HTTP ${response.statusCode}");
    }

    final json = jsonDecode(response.body);
    final data = json['data'] ?? json;
    final user = data['user'] ?? data;
    final profile = data['profile'] ?? {};

    final email = user['email'] ?? data['email'] ?? '';
    final displayName = profile['display_name'] ?? profile['displayName'] ?? profile['name'] ?? user['name'] ?? '';
    print("[BackendClient] Profile fetched: $displayName ($email)");

    return {
      'email': email,
      'displayName': displayName,
    };
  }

  static Future<void> postHeartbeat({
    required String accessToken,
    required String gatewayToken,
    required String gatewayUrl,
    String backendUrl = defaultBackendUrl,
  }) async {
    print("[BackendClient] Sending gateway heartbeat to $backendUrl for gateway $gatewayUrl...");
    final url = backendUrl.replaceAll(RegExp(r'/+$'), '');
    final response = await http.post(
      Uri.parse('$url/openclaw/gateway/heartbeat'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
      body: jsonEncode({
        'gateway_url': gatewayUrl,
        'gateway_token': gatewayToken,
      }),
    );

    if (response.statusCode != 200) {
      print("[BackendClient] Gateway Heartbeat failed: HTTP ${response.statusCode} - ${response.body}");
      throw Exception("Gateway Heartbeat failed: HTTP ${response.statusCode}");
    }
    print("[BackendClient] Gateway Heartbeat successful.");
  }
}
