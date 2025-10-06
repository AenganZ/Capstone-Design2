// main.dart
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:dio/dio.dart';
import 'dart:convert';
import 'dart:async';

// 상태 관리를 위한 Provider 클래스들
class DriverProvider with ChangeNotifier {
  Map<String, dynamic>? _driverInfo;
  bool _isOnline = false;
  Position? _currentLocation;
  List<Map<String, dynamic>> _missingPersons = [];
  List<Map<String, dynamic>> _myReports = [];
  Map<String, dynamic> _statistics = {};
  
  Map<String, dynamic>? get driverInfo => _driverInfo;
  bool get isOnline => _isOnline;
  Position? get currentLocation => _currentLocation;
  List<Map<String, dynamic>> get missingPersons => _missingPersons;
  List<Map<String, dynamic>> get myReports => _myReports;
  Map<String, dynamic> get statistics => _statistics;

  void setDriverInfo(Map<String, dynamic> info) {
    _driverInfo = info;
    notifyListeners();
  }

  void setOnlineStatus(bool status) {
    _isOnline = status;
    notifyListeners();
  }

  void updateLocation(Position position) {
    _currentLocation = position;
    notifyListeners();
  }

  void setMissingPersons(List<Map<String, dynamic>> persons) {
    _missingPersons = persons;
    notifyListeners();
  }

  void addReport(Map<String, dynamic> report) {
    _myReports.insert(0, report);
    notifyListeners();
  }

  void updateStatistics(Map<String, dynamic> stats) {
    _statistics = stats;
    notifyListeners();
  }
}

// API 서비스 클래스
class ApiService {
  static const String baseUrl = 'http://your-server.com:8001';
  final Dio _dio = Dio();
  String? _token;

  ApiService() {
    _dio.options.baseUrl = baseUrl;
    _dio.options.connectTimeout = Duration(seconds: 30);
    _dio.options.receiveTimeout = Duration(seconds: 30);
    
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        if (_token != null) {
          options.headers['Authorization'] = 'Bearer $_token';
        }
        handler.next(options);
      },
    ));
  }

  Future<Map<String, dynamic>> registerDriver({
    required String name,
    required String phone,
    required String vehicleNumber,
    required String vehicleType,
    required String licenseNumber,
    String? companyName,
    String? emergencyContact,
  }) async {
    try {
      final response = await _dio.post('/api/driver/register', data: {
        'name': name,
        'phone': phone,
        'vehicle_number': vehicleNumber,
        'vehicle_type': vehicleType,
        'license_number': licenseNumber,
        'company_name': companyName,
        'emergency_contact': emergencyContact,
      });
      
      if (response.data['token'] != null) {
        _token = response.data['token'];
        await _saveToken(_token!);
      }
      
      return response.data;
    } on DioException catch (e) {
      throw Exception(e.response?.data['detail'] ?? '등록 중 오류가 발생했습니다.');
    }
  }

  Future<Map<String, dynamic>> loginDriver({
    required String phone,
    required String licenseNumber,
  }) async {
    try {
      final response = await _dio.post('/api/driver/login', data: {
        'phone': phone,
        'license_number': licenseNumber,
      });
      
      if (response.data['token'] != null) {
        _token = response.data['token'];
        await _saveToken(_token!);
      }
      
      return response.data;
    } on DioException catch (e) {
      throw Exception(e.response?.data['detail'] ?? '로그인 중 오류가 발생했습니다.');
    }
  }

  Future<void> updateLocation(double latitude, double longitude, {double? speed, double? heading}) async {
    await _dio.post('/api/driver/location', data: {
      'latitude': latitude,
      'longitude': longitude,
      'speed': speed ?? 0.0,
      'heading': heading ?? 0.0,
      'accuracy': 5.0,
    });
  }

  Future<void> updateStatus(String status) async {
    await _dio.post('/api/driver/status', data: {
      'status': status,
    });
  }

  Future<Map<String, dynamic>> reportSighting({
    required String personId,
    required double latitude,
    required double longitude,
    required String description,
    required int confidenceLevel,
    String? photoBase64,
  }) async {
    final response = await _dio.post('/api/driver/report_sighting', data: {
      'person_id': personId,
      'latitude': latitude,
      'longitude': longitude,
      'description': description,
      'confidence_level': confidenceLevel,
      'photo_base64': photoBase64,
    });
    return response.data;
  }

  Future<List<Map<String, dynamic>>> getMissingPersons() async {
    final response = await _dio.get('/api/missing_persons');
    return List<Map<String, dynamic>>.from(response.data['data']);
  }

  Future<Map<String, dynamic>> getDriverStatistics() async {
    final response = await _dio.get('/api/driver/statistics');
    return response.data['data'];
  }

  Future<void> _saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('driver_token', token);
  }

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('driver_token');
  }

  Future<void> initializeToken() async {
    _token = await _getToken();
  }
}

// 메인 애플리케이션
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  
  runApp(
    ChangeNotifierProvider(
      create: (context) => DriverProvider(),
      child: MissingPersonDriverApp(),
    ),
  );
}

class MissingPersonDriverApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '실종자 찾기 도우미',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        fontFamily: 'NotoSansKR',
        appBarTheme: AppBarTheme(
          backgroundColor: Color(0xFF1E40AF),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      ),
      home: SplashScreen(),
      routes: {
        '/login': (context) => LoginScreen(),
        '/register': (context) => RegisterScreen(),
        '/home': (context) => HomeScreen(),
        '/missing-persons': (context) => MissingPersonsScreen(),
        '/report': (context) => ReportScreen(),
        '/profile': (context) => ProfileScreen(),
      },
    );
  }
}

// 스플래시 화면
class SplashScreen extends StatefulWidget {
  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final ApiService _apiService = ApiService();

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    await _apiService.initializeToken();
    await _setupFirebaseMessaging();
    await _requestPermissions();
    
    await Future.delayed(Duration(seconds: 2));
    
    final prefs = await SharedPreferences.getInstance();
    final driverInfo = prefs.getString('driver_info');
    
    if (driverInfo != null) {
      Navigator.pushReplacementNamed(context, '/home');
    } else {
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  Future<void> _setupFirebaseMessaging() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;
    
    await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    String? token = await messaging.getToken();
    print('FCM Token: $token');

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      _showMissingPersonAlert(message);
    });
  }

  void _showMissingPersonAlert(RemoteMessage message) {
    if (message.data['person_id'] != null) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text('🚨 실종자 발견 요청'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${message.data['name'] ?? '이름 미상'} (${message.data['age'] ?? '나이 미상'}세)'),
              SizedBox(height: 8),
              Text('위치: ${message.data['location'] ?? '위치 미상'}'),
              SizedBox(height: 8),
              Text('우선순위: ${message.data['priority'] ?? 'MEDIUM'}', 
                style: TextStyle(
                  color: message.data['priority'] == 'HIGH' ? Colors.red : Colors.orange,
                  fontWeight: FontWeight.bold,
                )),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('나중에'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.pushNamed(context, '/missing-persons');
              },
              child: Text('확인'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _requestPermissions() async {
    await Permission.locationWhenInUse.request();
    await Permission.camera.request();
    await Permission.notification.request();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF1E40AF),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search,
              size: 100,
              color: Colors.white,
            ),
            SizedBox(height: 24),
            Text(
              '실종자 찾기 도우미',
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Text(
              '택시·배달 기사용',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 16,
              ),
            ),
            SizedBox(height: 50),
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

// 로그인 화면
class LoginScreen extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _licenseController = TextEditingController();
  final ApiService _apiService = ApiService();
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('로그인'),
        centerTitle: true,
      ),
      body: Padding(
        padding: EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.local_taxi,
                size: 80,
                color: Color(0xFF1E40AF),
              ),
              SizedBox(height: 32),
              TextFormField(
                controller: _phoneController,
                decoration: InputDecoration(
                  labelText: '전화번호',
                  hintText: '010-1234-5678',
                  prefixIcon: Icon(Icons.phone),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                keyboardType: TextInputType.phone,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return '전화번호를 입력해주세요';
                  }
                  if (!RegExp(r'^010-\d{4}-\d{4}$').hasMatch(value)) {
                    return '올바른 전화번호 형식이 아닙니다';
                  }
                  return null;
                },
              ),
              SizedBox(height: 16),
              TextFormField(
                controller: _licenseController,
                decoration: InputDecoration(
                  labelText: '면허번호',
                  hintText: '12-34-567890-12',
                  prefixIcon: Icon(Icons.credit_card),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return '면허번호를 입력해주세요';
                  }
                  return null;
                },
              ),
              SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _login,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(0xFF1E40AF),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isLoading
                      ? CircularProgressIndicator(color: Colors.white)
                      : Text(
                          '로그인',
                          style: TextStyle(fontSize: 16, color: Colors.white),
                        ),
                ),
              ),
              SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.pushNamed(context, '/register'),
                child: Text('계정이 없으신가요? 회원가입'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final result = await _apiService.loginDriver(
        phone: _phoneController.text,
        licenseNumber: _licenseController.text,
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('driver_info', json.encode(result));

      if (mounted) {
        Provider.of<DriverProvider>(context, listen: false).setDriverInfo(result);
        Navigator.pushReplacementNamed(context, '/home');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}

// 회원가입 화면
class RegisterScreen extends StatefulWidget {
  @override
  _RegisterScreenState createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _vehicleController = TextEditingController();
  final _licenseController = TextEditingController();
  final _companyController = TextEditingController();
  final _emergencyController = TextEditingController();
  final ApiService _apiService = ApiService();
  
  String _vehicleType = 'taxi';
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('기사 등록'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: '이름',
                  prefixIcon: Icon(Icons.person),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return '이름을 입력해주세요';
                  }
                  if (value.length < 2) {
                    return '이름은 2글자 이상이어야 합니다';
                  }
                  return null;
                },
              ),
              SizedBox(height: 16),
              TextFormField(
                controller: _phoneController,
                decoration: InputDecoration(
                  labelText: '전화번호',
                  hintText: '010-1234-5678',
                  prefixIcon: Icon(Icons.phone),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                keyboardType: TextInputType.phone,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return '전화번호를 입력해주세요';
                  }
                  if (!RegExp(r'^010-\d{4}-\d{4}$').hasMatch(value)) {
                    return '올바른 전화번호 형식이 아닙니다';
                  }
                  return null;
                },
              ),
              SizedBox(height: 16),
              TextFormField(
                controller: _vehicleController,
                decoration: InputDecoration(
                  labelText: '차량번호',
                  hintText: '서울12가3456',
                  prefixIcon: Icon(Icons.directions_car),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return '차량번호를 입력해주세요';
                  }
                  return null;
                },
              ),
              SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _vehicleType,
                decoration: InputDecoration(
                  labelText: '업종',
                  prefixIcon: Icon(Icons.work),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                items: [
                  DropdownMenuItem(value: 'taxi', child: Text('택시')),
                  DropdownMenuItem(value: 'delivery', child: Text('배달')),
                ],
                onChanged: (value) {
                  setState(() => _vehicleType = value!);
                },
              ),
              SizedBox(height: 16),
              TextFormField(
                controller: _licenseController,
                decoration: InputDecoration(
                  labelText: '면허번호',
                  hintText: '12-34-567890-12',
                  prefixIcon: Icon(Icons.credit_card),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return '면허번호를 입력해주세요';
                  }
                  return null;
                },
              ),
              SizedBox(height: 16),
              TextFormField(
                controller: _companyController,
                decoration: InputDecoration(
                  labelText: '소속 회사 (선택사항)',
                  prefixIcon: Icon(Icons.business),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              SizedBox(height: 16),
              TextFormField(
                controller: _emergencyController,
                decoration: InputDecoration(
                  labelText: '긴급 연락처 (선택사항)',
                  hintText: '010-1234-5678',
                  prefixIcon: Icon(Icons.emergency),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                keyboardType: TextInputType.phone,
              ),
              SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _register,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(0xFF1E40AF),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isLoading
                      ? CircularProgressIndicator(color: Colors.white)
                      : Text(
                          '등록하기',
                          style: TextStyle(fontSize: 16, color: Colors.white),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final result = await _apiService.registerDriver(
        name: _nameController.text,
        phone: _phoneController.text,
        vehicleNumber: _vehicleController.text,
        vehicleType: _vehicleType,
        licenseNumber: _licenseController.text,
        companyName: _companyController.text.isEmpty ? null : _companyController.text,
        emergencyContact: _emergencyController.text.isEmpty ? null : _emergencyController.text,
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('driver_info', json.encode(result));

      if (mounted) {
        Provider.of<DriverProvider>(context, listen: false).setDriverInfo(result);
        Navigator.pushReplacementNamed(context, '/home');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}

// 홈 화면
class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ApiService _apiService = ApiService();
  Timer? _locationTimer;
  Timer? _dataTimer;

  @override
  void initState() {
    super.initState();
    _loadDriverInfo();
    _startLocationTracking();
    _loadData();
    _startDataRefresh();
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    _dataTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadDriverInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final driverInfoStr = prefs.getString('driver_info');
    if (driverInfoStr != null) {
      final driverInfo = json.decode(driverInfoStr);
      Provider.of<DriverProvider>(context, listen: false).setDriverInfo(driverInfo);
    }
  }

  void _startLocationTracking() {
    _locationTimer = Timer.periodic(Duration(seconds: 10), (timer) async {
      if (Provider.of<DriverProvider>(context, listen: false).isOnline) {
        try {
          Position position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
          );
          
          Provider.of<DriverProvider>(context, listen: false).updateLocation(position);
          
          await _apiService.updateLocation(
            position.latitude,
            position.longitude,
            speed: position.speed,
            heading: position.heading,
          );
        } catch (e) {
          print('위치 업데이트 오류: $e');
        }
      }
    });
  }

  void _startDataRefresh() {
    _dataTimer = Timer.periodic(Duration(minutes: 1), (timer) {
      _loadData();
    });
  }

  Future<void> _loadData() async {
    try {
      final missingPersons = await _apiService.getMissingPersons();
      final statistics = await _apiService.getDriverStatistics();
      
      Provider.of<DriverProvider>(context, listen: false).setMissingPersons(missingPersons);
      Provider.of<DriverProvider>(context, listen: false).updateStatistics(statistics);
    } catch (e) {
      print('데이터 로드 오류: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DriverProvider>(
      builder: (context, driverProvider, child) {
        final driverInfo = driverProvider.driverInfo;
        final stats = driverProvider.statistics;
        
        return Scaffold(
          appBar: AppBar(
            title: Text('실종자 찾기 도우미'),
            centerTitle: true,
            actions: [
              IconButton(
                icon: Icon(Icons.person),
                onPressed: () => Navigator.pushNamed(context, '/profile'),
              ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: _loadData,
            child: SingleChildScrollView(
              physics: AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDriverCard(driverInfo, driverProvider),
                  SizedBox(height: 20),
                  _buildStatisticsCard(stats),
                  SizedBox(height: 20),
                  _buildQuickActions(),
                  SizedBox(height: 20),
                  _buildRecentMissingPersons(driverProvider.missingPersons),
                  SizedBox(height: 20),
                  _buildInfoCard(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDriverCard(Map<String, dynamic>? driverInfo, DriverProvider provider) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${driverInfo?['name'] ?? '기사'}님',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '${driverInfo?['vehicle_number'] ?? ''} | ${driverInfo?['vehicle_type'] == 'taxi' ? '택시' : '배달'}',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            Column(
              children: [
                Switch(
                  value: provider.isOnline,
                  onChanged: _toggleOnlineStatus,
                  activeColor: Colors.green,
                ),
                Text(
                  provider.isOnline ? '운행 중' : '오프라인',
                  style: TextStyle(
                    color: provider.isOnline ? Colors.green : Colors.grey,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatisticsCard(Map<String, dynamic> stats) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '나의 기여도',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _buildStatItem('오늘 신고', '${stats['today_reports'] ?? 0}건')),
                Expanded(child: _buildStatItem('총 신고', '${stats['total_reports'] ?? 0}건')),
                Expanded(child: _buildStatItem('성공률', '${stats['success_rate'] ?? 0}%')),
              ],
            ),
            SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _buildStatItem('평점', '${stats['rating'] ?? 0.0}⭐')),
                Expanded(child: _buildStatItem('포인트', '${stats['total_points'] ?? 0}P')),
                Expanded(child: _buildStatItem('이번주', '${stats['week_reports'] ?? 0}건')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1E40AF),
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
      ],
    );
  }

  Widget _buildQuickActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '빠른 액션',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildActionButton(
                '실종자 목록',
                Icons.list,
                Colors.blue,
                () => Navigator.pushNamed(context, '/missing-persons'),
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: _buildActionButton(
                '발견 신고',
                Icons.report,
                Colors.red,
                () => Navigator.pushNamed(context, '/report'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionButton(String title, IconData icon, Color color, VoidCallback onTap) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(icon, size: 32, color: color),
              SizedBox(height: 8),
              Text(
                title,
                style: TextStyle(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecentMissingPersons(List<Map<String, dynamic>> missingPersons) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '최근 실종자',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            TextButton(
              onPressed: () => Navigator.pushNamed(context, '/missing-persons'),
              child: Text('전체 보기'),
            ),
          ],
        ),
        SizedBox(height: 8),
        missingPersons.isEmpty
            ? Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    '현재 실종자 정보가 없습니다.',
                    style: TextStyle(color: Colors.grey[600]),
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : Column(
                children: missingPersons.take(3).map((person) {
                  return Card(
                    elevation: 2,
                    margin: EdgeInsets.only(bottom: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: person['priority'] == 'HIGH' ? Colors.red : Colors.orange,
                        child: Text(
                          person['name']?.substring(0, 1) ?? '?',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                      title: Text('${person['name'] ?? '이름 미상'} (${person['age'] ?? '나이 미상'}세)'),
                      subtitle: Text(person['location'] ?? '위치 미상'),
                      trailing: Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () {
                        Navigator.pushNamed(context, '/missing-persons');
                      },
                    ),
                  );
                }).toList(),
              ),
      ],
    );
  }

  Widget _buildInfoCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '📋 실종자 찾기 안내',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            _buildInfoItem('실종자 발견 시 즉시 112 신고 후 앱을 통해 신고해주세요'),
            _buildInfoItem('의심되는 상황도 적극적으로 신고해주세요'),
            _buildInfoItem('개인정보 보호를 위해 사진 촬영은 자제해주세요'),
            _buildInfoItem('기사님들의 도움으로 많은 생명을 구할 수 있습니다'),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoItem(String text) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('• ', style: TextStyle(color: Color(0xFF1E40AF))),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 14, color: Colors.grey[700]),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleOnlineStatus(bool value) async {
    try {
      await _apiService.updateStatus(value ? 'online' : 'offline');
      Provider.of<DriverProvider>(context, listen: false).setOnlineStatus(value);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(value ? '운행을 시작합니다' : '운행을 종료합니다'),
          backgroundColor: value ? Colors.green : Colors.grey,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('상태 변경 중 오류가 발생했습니다')),
      );
    }
  }
}

// 실종자 목록 화면
class MissingPersonsScreen extends StatefulWidget {
  @override
  _MissingPersonsScreenState createState() => _MissingPersonsScreenState();
}

class _MissingPersonsScreenState extends State<MissingPersonsScreen> {
  final ApiService _apiService = ApiService();
  String _filterType = 'all';
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('실종자 목록'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _refreshData,
          ),
        ],
      ),
      body: Consumer<DriverProvider>(
        builder: (context, driverProvider, child) {
          List<Map<String, dynamic>> filteredPersons = _filterPersons(driverProvider.missingPersons);
          
          return Column(
            children: [
              _buildFilterSection(),
              Expanded(
                child: filteredPersons.isEmpty
                    ? _buildEmptyState()
                    : RefreshIndicator(
                        onRefresh: _refreshData,
                        child: ListView.builder(
                          padding: EdgeInsets.all(16),
                          itemCount: filteredPersons.length,
                          itemBuilder: (context, index) {
                            return _buildPersonCard(filteredPersons[index]);
                          },
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFilterSection() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
      ),
      child: Column(
        children: [
          TextField(
            decoration: InputDecoration(
              hintText: '이름 또는 위치로 검색...',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: Colors.white,
            ),
            onChanged: (value) {
              setState(() => _searchQuery = value);
            },
          ),
          SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip('전체', 'all'),
                _buildFilterChip('고위험', 'high'),
                _buildFilterChip('미취학아동', 'child'),
                _buildFilterChip('치매환자', 'dementia'),
                _buildFilterChip('성인', 'adult'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    bool isSelected = _filterType == value;
    return Padding(
      padding: EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (selected) {
          setState(() => _filterType = value);
        },
        backgroundColor: Colors.white,
        selectedColor: Color(0xFF1E40AF).withOpacity(0.2),
        labelStyle: TextStyle(
          color: isSelected ? Color(0xFF1E40AF) : Colors.grey[700],
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }

  Widget _buildPersonCard(Map<String, dynamic> person) {
    return Card(
      elevation: 3,
      margin: EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _showPersonDetail(person),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              _buildPersonAvatar(person),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${person['name'] ?? '이름 미상'} (${person['age'] ?? '나이 미상'}세)',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        _buildPriorityBadge(person['priority']),
                      ],
                    ),
                    SizedBox(height: 4),
                    Text(
                      person['location'] ?? '위치 미상',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 14,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '분류: ${person['category'] ?? '기타'}',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                    if (person['risk_factors'] != null && person['risk_factors'].isNotEmpty)
                      Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Wrap(
                          spacing: 4,
                          children: (person['risk_factors'] as List).take(2).map<Widget>((factor) {
                            return Container(
                              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.red[100],
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                factor.toString(),
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.red[700],
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                  ],
                ),
              ),
              Column(
                children: [
                  ElevatedButton(
                    onPressed: () => _quickReport(person),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      minimumSize: Size(80, 36),
                    ),
                    child: Text('신고', style: TextStyle(color: Colors.white, fontSize: 12)),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '${_calculateDistance(person)}km',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPersonAvatar(Map<String, dynamic> person) {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: person['priority'] == 'HIGH' ? Colors.red[100] : Colors.orange[100],
        border: Border.all(
          color: person['priority'] == 'HIGH' ? Colors.red : Colors.orange,
          width: 2,
        ),
      ),
      child: person['photo_url'] != null
          ? ClipOval(
              child: Image.network(
                person['photo_url'],
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return _buildAvatarFallback(person);
                },
              ),
            )
          : _buildAvatarFallback(person),
    );
  }

  Widget _buildAvatarFallback(Map<String, dynamic> person) {
    return Center(
      child: Text(
        person['name']?.substring(0, 1) ?? '?',
        style: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: person['priority'] == 'HIGH' ? Colors.red : Colors.orange,
        ),
      ),
    );
  }

  Widget _buildPriorityBadge(String? priority) {
    Color color = priority == 'HIGH' ? Colors.red : Colors.orange;
    String text = priority == 'HIGH' ? '긴급' : '보통';
    
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off,
            size: 80,
            color: Colors.grey[400],
          ),
          SizedBox(height: 16),
          Text(
            '검색 결과가 없습니다',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 8),
          Text(
            '다른 검색어를 시도해보세요',
            style: TextStyle(color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _filterPersons(List<Map<String, dynamic>> persons) {
    List<Map<String, dynamic>> filtered = persons;

    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((person) {
        String name = person['name']?.toString().toLowerCase() ?? '';
        String location = person['location']?.toString().toLowerCase() ?? '';
        String query = _searchQuery.toLowerCase();
        return name.contains(query) || location.contains(query);
      }).toList();
    }

    if (_filterType != 'all') {
      filtered = filtered.where((person) {
        switch (_filterType) {
          case 'high':
            return person['priority'] == 'HIGH';
          case 'child':
            return person['category']?.contains('아동') == true || 
                   (person['age'] != null && person['age'] <= 18);
          case 'dementia':
            return person['category']?.contains('치매') == true;
          case 'adult':
            return person['age'] != null && person['age'] >= 19;
          default:
            return true;
        }
      }).toList();
    }

    return filtered;
  }

  String _calculateDistance(Map<String, dynamic> person) {
    return '2.3';
  }

  Future<void> _refreshData() async {
    try {
      final missingPersons = await _apiService.getMissingPersons();
      Provider.of<DriverProvider>(context, listen: false).setMissingPersons(missingPersons);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('데이터 새로고침 실패')),
      );
    }
  }

  void _showPersonDetail(Map<String, dynamic> person) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => PersonDetailModal(person: person),
    );
  }

  void _quickReport(Map<String, dynamic> person) {
    Navigator.pushNamed(
      context,
      '/report',
      arguments: {'person': person},
    );
  }
}

// 실종자 상세 모달
class PersonDetailModal extends StatelessWidget {
  final Map<String, dynamic> person;

  PersonDetailModal({required this.person});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.9,
      minChildSize: 0.5,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SingleChildScrollView(
            controller: scrollController,
            padding: EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                SizedBox(height: 20),
                _buildHeader(),
                SizedBox(height: 20),
                if (person['photo_url'] != null) _buildPhoto(),
                _buildDetailSection('기본 정보', _buildBasicInfo()),
                if (person['description'] != null) 
                  _buildDetailSection('상세 설명', Text(person['description'])),
                if (person['ner_entities'] != null)
                  _buildDetailSection('추출된 특징', _buildFeatures()),
                if (person['risk_factors'] != null)
                  _buildDetailSection('위험 요소', _buildRiskFactors()),
                SizedBox(height: 20),
                _buildActionButtons(context),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: person['priority'] == 'HIGH' ? Colors.red[100] : Colors.orange[100],
            border: Border.all(
              color: person['priority'] == 'HIGH' ? Colors.red : Colors.orange,
              width: 2,
            ),
          ),
          child: Center(
            child: Text(
              person['name']?.substring(0, 1) ?? '?',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: person['priority'] == 'HIGH' ? Colors.red : Colors.orange,
              ),
            ),
          ),
        ),
        SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${person['name'] ?? '이름 미상'} (${person['age'] ?? '나이 미상'}세)',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 4),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: person['priority'] == 'HIGH' ? Colors.red : Colors.orange,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  person['priority'] == 'HIGH' ? '긴급' : '보통',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPhoto() {
    return Container(
      margin: EdgeInsets.only(bottom: 20),
      height: 200,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          person['photo_url'],
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              color: Colors.grey[100],
              child: Center(
                child: Icon(Icons.person, size: 80, color: Colors.grey[400]),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildDetailSection(String title, Widget content) {
    return Container(
      margin: EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E40AF),
            ),
          ),
          SizedBox(height: 8),
          content,
        ],
      ),
    );
  }

  Widget _buildBasicInfo() {
    return Column(
      children: [
        _buildInfoRow('나이', '${person['age'] ?? '미상'}세'),
        _buildInfoRow('성별', person['gender'] ?? '미상'),
        _buildInfoRow('분류', person['category'] ?? '기타'),
        _buildInfoRow('실종 위치', person['location'] ?? '위치 미상'),
        _buildInfoRow('신고 시간', _formatDateTime(person['created_at'])),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatures() {
    Map<String, dynamic> entities = person['ner_entities'] ?? {};
    if (entities.isEmpty) {
      return Text('추출된 특징이 없습니다.', style: TextStyle(color: Colors.grey[600]));
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: entities.entries.expand((entry) {
        List<dynamic> values = entry.value is List ? entry.value : [entry.value];
        return values.map<Widget>((value) {
          return Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Color(0xFF1E40AF).withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Color(0xFF1E40AF).withOpacity(0.3)),
            ),
            child: Text(
              value.toString(),
              style: TextStyle(
                color: Color(0xFF1E40AF),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          );
        }).toList();
      }).toList(),
    );
  }

  Widget _buildRiskFactors() {
    List<dynamic> riskFactors = person['risk_factors'] ?? [];
    if (riskFactors.isEmpty) {
      return Text('위험 요소가 없습니다.', style: TextStyle(color: Colors.grey[600]));
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: riskFactors.map<Widget>((factor) {
        return Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.red[50],
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.red[200]!),
          ),
          child: Text(
            factor.toString(),
            style: TextStyle(
              color: Colors.red[700],
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: Icon(Icons.close),
            label: Text('닫기'),
            style: OutlinedButton.styleFrom(
              padding: EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
        SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushNamed(
                context,
                '/report',
                arguments: {'person': person},
              );
            },
            icon: Icon(Icons.report, color: Colors.white),
            label: Text('발견 신고', style: TextStyle(color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              padding: EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
      ],
    );
  }

  String _formatDateTime(String? dateTime) {
    if (dateTime == null) return '미상';
    try {
      DateTime dt = DateTime.parse(dateTime);
      return '${dt.month}/${dt.day} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return '미상';
    }
  }
}

// 발견 신고 화면
class ReportScreen extends StatefulWidget {
  @override
  _ReportScreenState createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final ApiService _apiService = ApiService();
  
  Map<String, dynamic>? _selectedPerson;
  int _confidenceLevel = 3;
  Position? _currentLocation;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    if (args != null && args['person'] != null) {
      _selectedPerson = args['person'];
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      setState(() => _currentLocation = position);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('위치 정보를 가져올 수 없습니다')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('발견 신고'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildLocationInfo(),
              SizedBox(height: 20),
              _buildPersonSelection(),
              SizedBox(height: 20),
              _buildConfidenceSlider(),
              SizedBox(height: 20),
              _buildDescriptionField(),
              SizedBox(height: 20),
              _buildGuidelines(),
              SizedBox(height: 32),
              _buildSubmitButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLocationInfo() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.location_on, color: Colors.red),
                SizedBox(width: 8),
                Text(
                  '현재 위치',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            SizedBox(height: 8),
            if (_currentLocation != null)
              Text(
                '위도: ${_currentLocation!.latitude.toStringAsFixed(6)}\n'
                '경도: ${_currentLocation!.longitude.toStringAsFixed(6)}',
                style: TextStyle(color: Colors.grey[600]),
              )
            else
              Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Text('위치 정보를 가져오는 중...'),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPersonSelection() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '실종자 선택',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            if (_selectedPerson != null)
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: _selectedPerson!['priority'] == 'HIGH' ? Colors.red : Colors.orange,
                      child: Text(
                        _selectedPerson!['name']?.substring(0, 1) ?? '?',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${_selectedPerson!['name'] ?? '이름 미상'} (${_selectedPerson!['age'] ?? '나이 미상'}세)',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            _selectedPerson!['location'] ?? '위치 미상',
                            style: TextStyle(color: Colors.grey[600], fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => setState(() => _selectedPerson = null),
                      icon: Icon(Icons.close, color: Colors.grey),
                    ),
                  ],
                ),
              )
            else
              Consumer<DriverProvider>(
                builder: (context, driverProvider, child) {
                  return Column(
                    children: [
                      Text(
                        '신고할 실종자를 선택하세요',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                      SizedBox(height: 8),
                      SizedBox(
                        height: 120,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: driverProvider.missingPersons.length,
                          itemBuilder: (context, index) {
                            final person = driverProvider.missingPersons[index];
                            return GestureDetector(
                              onTap: () => setState(() => _selectedPerson = person),
                              child: Container(
                                width: 100,
                                margin: EdgeInsets.only(right: 8),
                                padding: EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey[300]!),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Column(
                                  children: [
                                    CircleAvatar(
                                      backgroundColor: person['priority'] == 'HIGH' ? Colors.red : Colors.orange,
                                      child: Text(
                                        person['name']?.substring(0, 1) ?? '?',
                                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      person['name'] ?? '이름 미상',
                                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                                      textAlign: TextAlign.center,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      '${person['age'] ?? '미상'}세',
                                      style: TextStyle(fontSize: 9, color: Colors.grey[600]),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfidenceSlider() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '확신도 (${_confidenceLevel}/5)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              _getConfidenceDescription(_confidenceLevel),
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
            SizedBox(height: 12),
            Slider(
              value: _confidenceLevel.toDouble(),
              min: 1,
              max: 5,
              divisions: 4,
              activeColor: _getConfidenceColor(_confidenceLevel),
              onChanged: (value) {
                setState(() => _confidenceLevel = value.round());
              },
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('의심', style: TextStyle(fontSize: 12, color: Colors.grey)),
                Text('확신', style: TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _getConfidenceDescription(int level) {
    switch (level) {
      case 1: return '약간 의심됨 - 확실하지 않음';
      case 2: return '의심됨 - 가능성이 있음';
      case 3: return '보통 - 어느 정도 확실함';
      case 4: return '높음 - 상당히 확실함';
      case 5: return '매우 높음 - 거의 확실함';
      default: return '';
    }
  }

  Color _getConfidenceColor(int level) {
    if (level <= 2) return Colors.orange;
    if (level <= 3) return Colors.blue;
    return Colors.green;
  }

  Widget _buildDescriptionField() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '상세 설명',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            TextFormField(
              controller: _descriptionController,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: '발견한 상황을 자세히 설명해주세요...\n예: 지하철 2호선 강남역 3번 출구 근처에서 혼자 서성이고 있었습니다.',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                filled: true,
                fillColor: Colors.grey[50],
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return '상황을 설명해주세요';
                }
                if (value.trim().length < 10) {
                  return '10글자 이상 입력해주세요';
                }
                return null;
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGuidelines() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue),
                SizedBox(width: 8),
                Text(
                  '신고 가이드라인',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            SizedBox(height: 12),
            _buildGuidelineItem('실종자 발견 시 즉시 112에 신고하세요'),
            _buildGuidelineItem('의심스러운 상황도 적극적으로 신고해주세요'),
            _buildGuidelineItem('개인정보 보호를 위해 사진 촬영은 자제하세요'),
            _buildGuidelineItem('정확한 위치와 상황을 상세히 기록하세요'),
          ],
        ),
      ),
    );
  }

  Widget _buildGuidelineItem(String text) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('• ', style: TextStyle(color: Colors.blue)),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 14, color: Colors.grey[700]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: _isSubmitting || _selectedPerson == null || _currentLocation == null
            ? null
            : _submitReport,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.red,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: _isSubmitting
            ? CircularProgressIndicator(color: Colors.white)
            : Text(
                '신고 제출',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
      ),
    );
  }

  Future<void> _submitReport() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedPerson == null || _currentLocation == null) return;

    setState(() => _isSubmitting = true);

    try {
      final result = await _apiService.reportSighting(
        personId: _selectedPerson!['id'],
        latitude: _currentLocation!.latitude,
        longitude: _currentLocation!.longitude,
        description: _descriptionController.text,
        confidenceLevel: _confidenceLevel,
      );

      Provider.of<DriverProvider>(context, listen: false).addReport({
        'person_id': _selectedPerson!['id'],
        'person_name': _selectedPerson!['name'],
        'confidence_level': _confidenceLevel,
        'description': _descriptionController.text,
        'reported_at': DateTime.now().toIso8601String(),
        'reward_points': result['reward_points'] ?? 0,
      });

      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: Text('신고 완료'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 60),
                SizedBox(height: 16),
                Text(
                  '신고가 성공적으로 접수되었습니다.',
                  textAlign: TextAlign.center,
                ),
                if (result['reward_points'] != null)
                  Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      '${result['reward_points']}포인트를 획득했습니다!',
                      style: TextStyle(
                        color: Colors.blue,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ),
            actions: [
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).pop();
                },
                child: Text('확인'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('신고 제출 중 오류가 발생했습니다: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }
}

// 프로필 화면
class ProfileScreen extends StatefulWidget {
  @override
  _ProfileScreenState createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final ApiService _apiService = ApiService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('프로필'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Icons.logout),
            onPressed: _logout,
          ),
        ],
      ),
      body: Consumer<DriverProvider>(
        builder: (context, driverProvider, child) {
          final driverInfo = driverProvider.driverInfo;
          final stats = driverProvider.statistics;
          
          return SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: Column(
              children: [
                _buildProfileHeader(driverInfo),
                SizedBox(height: 20),
                _buildDetailedStats(stats),
                SizedBox(height: 20),
                _buildRecentReports(driverProvider.myReports),
                SizedBox(height: 20),
                _buildSettingsSection(),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildProfileHeader(Map<String, dynamic>? driverInfo) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          children: [
            CircleAvatar(
              radius: 40,
              backgroundColor: Color(0xFF1E40AF),
              child: Text(
                driverInfo?['name']?.substring(0, 1) ?? '?',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
            SizedBox(height: 16),
            Text(
              '${driverInfo?['name'] ?? '기사'}님',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 4),
            Text(
              '${driverInfo?['vehicle_number'] ?? ''} | ${driverInfo?['vehicle_type'] == 'taxi' ? '택시' : '배달'}',
              style: TextStyle(color: Colors.grey[600]),
            ),
            SizedBox(height: 8),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '인증된 기사',
                style: TextStyle(
                  color: Colors.green[700],
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailedStats(Map<String, dynamic> stats) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '상세 통계',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _buildStatCard('총 신고', '${stats['total_reports'] ?? 0}', '건', Colors.blue)),
                SizedBox(width: 12),
                Expanded(child: _buildStatCard('성공 신고', '${stats['successful_reports'] ?? 0}', '건', Colors.green)),
              ],
            ),
            SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _buildStatCard('성공률', '${stats['success_rate'] ?? 0}', '%', Colors.orange)),
                SizedBox(width: 12),
                Expanded(child: _buildStatCard('평점', '${stats['rating'] ?? 0.0}', '⭐', Colors.purple)),
              ],
            ),
            SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _buildStatCard('포인트', '${stats['total_points'] ?? 0}', 'P', Colors.red)),
                SizedBox(width: 12),
                Expanded(child: _buildStatCard('평균 시간', '${stats['avg_session_hours'] ?? 0}', 'h', Colors.teal)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String value, String unit, Color color) {
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(
            '$value$unit',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentReports(List<Map<String, dynamic>> reports) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '최근 신고 내역',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            reports.isEmpty
                ? Center(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        '신고 내역이 없습니다.',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    physics: NeverScrollableScrollPhysics(),
                    itemCount: reports.take(5).length,
                    separatorBuilder: (context, index) => Divider(),
                    itemBuilder: (context, index) {
                      final report = reports[index];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.green[100],
                          child: Icon(Icons.check, color: Colors.green),
                        ),
                        title: Text(report['person_name'] ?? '실종자'),
                        subtitle: Text(
                          '확신도: ${report['confidence_level']}/5\n'
                          '${_formatDateTime(report['reported_at'])}',
                        ),
                        trailing: report['reward_points'] != null
                            ? Container(
                                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.blue[100],
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '+${report['reward_points']}P',
                                  style: TextStyle(
                                    color: Colors.blue[700],
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              )
                            : null,
                      );
                    },
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsSection() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          ListTile(
            leading: Icon(Icons.notifications, color: Color(0xFF1E40AF)),
            title: Text('알림 설정'),
            trailing: Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('알림 설정 기능은 준비 중입니다')),
              );
            },
          ),
          Divider(),
          ListTile(
            leading: Icon(Icons.help, color: Color(0xFF1E40AF)),
            title: Text('도움말'),
            trailing: Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('도움말 기능은 준비 중입니다')),
              );
            },
          ),
          Divider(),
          ListTile(
            leading: Icon(Icons.info, color: Color(0xFF1E40AF)),
            title: Text('앱 정보'),
            trailing: Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text('앱 정보'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('실종자 찾기 도우미'),
                      Text('버전: 1.0.0'),
                      SizedBox(height: 8),
                      Text('대전 이동 안전망 시스템'),
                      Text('택시·배달 기사용 앱'),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text('확인'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  String _formatDateTime(String? dateTime) {
    if (dateTime == null) return '';
    try {
      DateTime dt = DateTime.parse(dateTime);
      return '${dt.month}/${dt.day} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return '';
    }
  }

  Future<void> _logout() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('로그아웃'),
        content: Text('정말 로그아웃하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('취소'),
          ),
          ElevatedButton(
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.clear();
              
              if (mounted) {
                Navigator.of(context).pop();
                Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('로그아웃', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}