import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/missing_person.dart';

class ApiService {
  static const String baseUrl = 'http://localhost:8001';
  static const Duration timeout = Duration(seconds: 30);

  static Future<bool> checkServerConnection() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/health'),
      ).timeout(timeout);
      return response.statusCode == 200;
    } catch (e) {
      print('서버 연결 확인 오류: $e');
      return false;
    }
  }

  static Future<List<MissingPerson>> getMissingPersons() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/missing_persons?status=ACTIVE'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(timeout);

      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        final List<dynamic> persons = data['persons'] ?? [];
        return persons.map((json) => MissingPerson.fromJson(json)).toList();
      }
      return [];
    } catch (e) {
      print('실종자 목록 조회 오류: $e');
      return [];
    }
  }

  static Future<MissingPerson?> getMissingPersonDetail(String personId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/person/$personId'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(timeout);

      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        return MissingPerson.fromJson(data);
      }
      return null;
    } catch (e) {
      print('실종자 상세 조회 오류: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>> reportSighting({
    required String personId,
    required Map<String, double> location,
    required String description,
    String? photoBase64,
    String? reporterId,
    String confidenceLevel = 'MEDIUM',
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/report_sighting'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'person_id': personId,
          'reporter_location': location,
          'description': description,
          'photo_base64': photoBase64,
          'reporter_id': reporterId,
          'confidence_level': confidenceLevel,
        }),
      ).timeout(timeout);

      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        return {
          'success': true,
          'message': data['message'],
          'report_id': data['report_id'].toString(),
        };
      } else {
        return {'success': false, 'message': '신고 접수 실패'};
      }
    } catch (e) {
      print('목격 신고 오류: $e');
      return {'success': false, 'message': '네트워크 오류'};
    }
  }
}