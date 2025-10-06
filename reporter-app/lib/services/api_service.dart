import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static const String baseUrl = 'http://localhost:8000';
  static const Duration timeout = Duration(seconds: 30);

  static Future<bool> checkServerConnection() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/health'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(timeout);
      
      return response.statusCode == 200;
    } catch (e) {
      print('서버 연결 확인 실패: $e');
      return false;
    }
  }

  static Future<Map<String, dynamic>> submitMissingPerson({
    required String name,
    required int age,
    required String gender,
    required String missingLocation,
    required DateTime missingDateTime,
    required String reporterName,
    required String reporterPhone,
    required String reporterRelation,
    String? description,
    XFile? photo,
  }) async {
    try {
      String? photoBase64;
      
      if (photo != null) {
        final bytes = await photo.readAsBytes();
        photoBase64 = 'data:image/jpeg;base64,${base64Encode(bytes)}';
      }

      final missingPerson = {
        'name': name,
        'age': age,
        'gender': gender,
        'location': missingLocation,
        'description': description ?? '',
        'reporter_name': reporterName,
        'reporter_phone': reporterPhone,
        'reporter_relation': reporterRelation,
        'missing_datetime': missingDateTime.toIso8601String(),
        'status': 'PENDING',
        'category': _categorizeByAge(age),
        'lat': 36.5,
        'lng': 127.8,
      };

      final requestBody = {
        'missing_person': missingPerson,
        'photo_data': photoBase64,
      };

      final response = await http.post(
        Uri.parse('$baseUrl/api/missing_persons'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode(requestBody),
      ).timeout(timeout);

      final responseData = json.decode(response.body);

      if (response.statusCode == 200) {
        return {
          'success': true,
          'message': '실종자 신고가 접수되었습니다.',
          'person_id': responseData['person_id'],
        };
      } else {
        return {
          'success': false,
          'message': responseData['detail'] ?? '서버 오류가 발생했습니다.',
        };
      }
    } catch (e) {
      print('실종자 신고 제출 오류: $e');
      return {
        'success': false,
        'message': '네트워크 연결을 확인해주세요.',
      };
    }
  }

  static String _categorizeByAge(int age) {
    if (age <= 6) {
      return '미취학아동';
    } else if (age <= 18) {
      return '학령기아동';
    } else if (age >= 65) {
      return '치매환자';
    } else {
      return '성인가출';
    }
  }

  static Future<Map<String, dynamic>> getMissingPersons() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/missing_persons'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(timeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'success': true,
          'data': data['data'],
        };
      } else {
        return {
          'success': false,
          'message': '실종자 목록을 가져올 수 없습니다.',
        };
      }
    } catch (e) {
      print('실종자 목록 조회 오류: $e');
      return {
        'success': false,
        'message': '네트워크 연결을 확인해주세요.',
      };
    }
  }

  static Future<Map<String, dynamic>> uploadPhoto(XFile photo) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/api/upload_photo'),
      );

      request.files.add(await http.MultipartFile.fromPath(
        'file',
        photo.path,
      ));

      var streamedResponse = await request.send().timeout(timeout);
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'success': true,
          'url': data['url'],
          'filename': data['filename'],
        };
      } else {
        return {
          'success': false,
          'message': '사진 업로드에 실패했습니다.',
        };
      }
    } catch (e) {
      print('사진 업로드 오류: $e');
      return {
        'success': false,
        'message': '사진 업로드 중 오류가 발생했습니다.',
      };
    }
  }

  static Future<void> saveReportLocally(Map<String, dynamic> reportData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final reports = prefs.getStringList('local_reports') ?? [];
      reports.add(json.encode(reportData));
      await prefs.setStringList('local_reports', reports);
    } catch (e) {
      print('로컬 저장 실패: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> getLocalReports() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final reports = prefs.getStringList('local_reports') ?? [];
      return reports.map((report) => json.decode(report) as Map<String, dynamic>).toList();
    } catch (e) {
      print('로컬 데이터 조회 실패: $e');
      return [];
    }
  }

  static Future<void> clearLocalReports() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('local_reports');
    } catch (e) {
      print('로컬 데이터 삭제 실패: $e');
    }
  }

  static Future<bool> testConnection() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 5));
      
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  static Future<Map<String, dynamic>> getServerStatus() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/health'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'success': true,
          'status': data['status'],
          'firebase': data['firebase'],
          'timestamp': data['timestamp'],
        };
      } else {
        return {
          'success': false,
          'message': '서버 상태를 확인할 수 없습니다.',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': '서버에 연결할 수 없습니다.',
      };
    }
  }

  static String formatErrorMessage(dynamic error) {
    if (error is SocketException) {
      return '인터넷 연결을 확인해주세요.';
    } else if (error is http.ClientException) {
      return '서버에 연결할 수 없습니다.';
    } else if (error.toString().contains('timeout')) {
      return '요청 시간이 초과되었습니다.';
    } else {
      return '알 수 없는 오류가 발생했습니다.';
    }
  }
}