import 'package:dio/dio.dart';

import '../device_info.dart';
import '../storage/secure_store.dart';

Future<String?> probeNode(String nodeUrl) async {
  try {
    final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 5), receiveTimeout: const Duration(seconds: 5)));
    final resp = await dio.get('$nodeUrl/node/info');
    final data = resp.data;
    if (data is Map && data['bully_node'] == true) {
      return data['name'] as String? ?? nodeUrl;
    }
    return null;
  } catch (_) {
    return null;
  }
}

class ApiClient {
  final Dio _dio;
  final String baseUrl;

  ApiClient(this.baseUrl) : _dio = Dio(BaseOptions(baseUrl: baseUrl)) {
    _dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) async {
      final token = await SecureStore.getAuthToken(baseUrl);
      if (token != null) {
        options.headers['Authorization'] = 'Bearer $token';
      }
      handler.next(options);
    }));
  }

  Future<Map<String, dynamic>> register(String username, String password) async {
    final resp = await _dio.post('/auth/register', data: {
      'username': username,
      'password': password,
      'device_name': DeviceInfo.deviceName(),
      'platform': DeviceInfo.platform(),
    });
    return resp.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> login(String username, String password) async {
    final resp = await _dio.post('/auth/login', data: {
      'username': username,
      'password': password,
      'device_name': DeviceInfo.deviceName(),
      'platform': DeviceInfo.platform(),
    });
    return resp.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> listSessions() async {
    final resp = await _dio.get('/sessions');
    return resp.data as Map<String, dynamic>;
  }

  Future<void> revokeSession(String sessionId) => _dio.delete('/sessions/$sessionId');

  Future<void> revokeAllOtherSessions() => _dio.post('/sessions/revoke-all');

  Future<void> setSessionInactivityTimeout(int seconds) =>
      _dio.put('/sessions/policy', data: {'inactivity_timeout_seconds': seconds});

  Future<List<dynamic>> searchUsers(String query) async {
    final resp = await _dio.get('/users/search', queryParameters: {'q': query});
    return resp.data as List<dynamic>;
  }

  Future<Map<String, dynamic>> createDm(String peerUserId) async {
    final resp = await _dio.post('/conversations/dm', data: {'peer_user_id': peerUserId});
    return resp.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> createGroup(String name, List<String> memberIds) async {
    final resp = await _dio.post('/conversations/group', data: {'name': name, 'member_user_ids': memberIds});
    return resp.data as Map<String, dynamic>;
  }

  Future<List<dynamic>> listConversations() async {
    final resp = await _dio.get('/conversations');
    return resp.data as List<dynamic>;
  }

  Future<Map<String, dynamic>> getUser(String userId) async {
    final resp = await _dio.get('/users/$userId');
    return resp.data as Map<String, dynamic>;
  }

  Future<List<dynamic>> conversationMembers(String conversationId) async {
    final resp = await _dio.get('/conversations/$conversationId/members');
    return resp.data as List<dynamic>;
  }

  Future<void> uploadPrekeys(Map<String, dynamic> body) => _dio.post('/keys/upload', data: body);

  Future<Map<String, dynamic>> fetchKeyBundle(String userId) async {
    final resp = await _dio.get('/keys/bundle', queryParameters: {'user_id': userId});
    return resp.data as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> fetchIceServers() async {
    final resp = await _dio.get('/ice-servers');
    final servers = (resp.data as Map<String, dynamic>)['ice_servers'] as List;
    return servers.cast<Map<String, dynamic>>();
  }
}
