import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/missing_person.dart';
import '../services/api_service.dart';
import '../widgets/missing_person_card.dart';
import 'missing_person_detail_screen.dart';
import '../services/websocket_service.dart';
import '../widgets/missing_person_alert_dialog.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<MissingPerson> _persons = [];
  bool _isLoading = true;
  bool _isServerConnected = false;
  String _driverId = '';
  String _driverName = '';

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
  await _loadDriverInfo();
  await _checkServerConnection();
  await _loadMissingPersons();
  _setupWebSocket();
}

void _setupWebSocket() {
  WebSocketService.connect((message) {
    print('WebSocket 메시지 수신: $message');
    
    if (message['type'] == 'new_missing_person_notification') {
      final personData = message['person'];
      
      if (mounted) {
        _showNewPersonDialog(personData);
        _loadMissingPersons();
      }
    }
  });
}

void _showNewPersonDialog(Map<String, dynamic> personData) {
  try {
    final person = MissingPerson.fromJson(personData);
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => MissingPersonAlertDialog(
        person: person,
        onViewDetails: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => MissingPersonDetailScreen(
                person: person,
                driverId: _driverId,
              ),
            ),
          );
        },
      ),
    );
  } catch (e) {
    print('알림 표시 오류: $e');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('새로운 실종자 알림'),
        content: Text('${personData['name'] ?? '이름 미상'}님을 찾고 있습니다'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }
}

@override
void dispose() {
  WebSocketService.disconnect();
  super.dispose();
}

  Future<void> _loadDriverInfo() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _driverId = prefs.getString('driver_id') ?? '';
      _driverName = prefs.getString('driver_name') ?? '';
    });

    if (_driverId.isEmpty) {
      await _showDriverInfoDialog();
    }
  }

  Future<void> _showDriverInfoDialog() async {
    final nameController = TextEditingController();
    
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('기사 정보 입력'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: '이름',
                hintText: '홍길동',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              if (nameController.text.isNotEmpty) {
                final prefs = await SharedPreferences.getInstance();
                final id = DateTime.now().millisecondsSinceEpoch.toString();
                await prefs.setString('driver_id', id);
                await prefs.setString('driver_name', nameController.text);
                
                setState(() {
                  _driverId = id;
                  _driverName = nameController.text;
                });
                
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
              }
            },
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  Future<void> _checkServerConnection() async {
    final isConnected = await ApiService.checkServerConnection();
    setState(() {
      _isServerConnected = isConnected;
    });
  }

  Future<void> _loadMissingPersons() async {
    setState(() {
      _isLoading = true;
    });

    final persons = await ApiService.getMissingPersons();
    
    setState(() {
      _persons = persons;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          '대전 이동 안전망',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF1E40AF),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(
              _isServerConnected ? Icons.cloud_done : Icons.cloud_off,
              color: _isServerConnected ? Colors.white : Colors.red[200],
            ),
            onPressed: _checkServerConnection,
          ),
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: _showDriverInfo,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadMissingPersons,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadMissingPersons,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (!_isServerConnected) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.cloud_off,
              size: 64,
              color: Color(0xFF9CA3AF),
            ),
            const SizedBox(height: 16),
            const Text(
              '서버에 연결할 수 없습니다',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1F2937),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '네트워크 연결을 확인해주세요',
              style: TextStyle(
                color: Color(0xFF6B7280),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () async {
                await _checkServerConnection();
                if (_isServerConnected) {
                  _loadMissingPersons();
                }
              },
              icon: const Icon(Icons.refresh),
              label: const Text('다시 시도'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E40AF),
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }

    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF1E40AF)),
        ),
      );
    }

    if (_persons.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.check_circle_outline,
              size: 64,
              color: Color(0xFF10B981),
            ),
            const SizedBox(height: 16),
            const Text(
              '현재 실종자가 없습니다',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1F2937),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '새로운 실종자가 등록되면 표시됩니다',
              style: TextStyle(
                color: Color(0xFF6B7280),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: Color(0xFF1E40AF),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '실종자 ${_persons.length}명',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$_driverName 기사님',
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(top: 8, bottom: 16),
            itemCount: _persons.length,
            itemBuilder: (context, index) {
              return MissingPersonCard(
                person: _persons[index],
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => MissingPersonDetailScreen(
                        person: _persons[index],
                        driverId: _driverId,
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  void _showDriverInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('기사 정보'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('이름: $_driverName'),
            const SizedBox(height: 8),
            Text('ID: $_driverId'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }
}