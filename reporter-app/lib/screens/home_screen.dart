import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../widgets/server_status_widget.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isServerConnected = false;
  bool _isCheckingConnection = true;

  @override
  void initState() {
    super.initState();
    _checkServerConnection();
  }

  Future<void> _checkServerConnection() async {
    setState(() {
      _isCheckingConnection = true;
    });

    try {
      final isConnected = await ApiService.checkServerConnection();
      setState(() {
        _isServerConnected = isConnected;
        _isCheckingConnection = false;
      });
    } catch (e) {
      setState(() {
        _isServerConnected = false;
        _isCheckingConnection = false;
      });
    }
  }

  void _showEmergencyDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          '긴급상황 안내',
          style: TextStyle(
            color: Color(0xFFEF4444),
            fontWeight: FontWeight.bold,
          ),
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '생명이 위험한 긴급상황이라면:',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 8),
            Text('• 즉시 112 (경찰서)로 신고'),
            Text('• 119 (소방서)로 구조 요청'),
            SizedBox(height: 16),
            Text(
              '이 앱은 실종자 정보를 관리자에게 전달하여\n수색 활동을 지원하는 용도입니다.',
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFF6B7280),
              ),
            ),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('실종자 신고'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _checkServerConnection,
            tooltip: '서버 연결 확인',
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ServerStatusWidget(
                isConnected: _isServerConnected,
                isChecking: _isCheckingConnection,
                onRefresh: _checkServerConnection,
              ),
              const SizedBox(height: 24),
              
              // 메인 액션 카드
              Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.person_search,
                        size: 64,
                        color: Color(0xFF1E40AF),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        '실종자 신고',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1F2937),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '실종자의 정보와 사진을 등록하여\n수색 활동을 요청할 수 있습니다.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          color: Color(0xFF6B7280),
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isServerConnected
                              ? () => Navigator.pushNamed(context, '/report')
                              : null,
                          child: const Text('신고 시작'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // 추가 기능들
              Row(
                children: [
                  Expanded(
                    child: Card(
                      child: InkWell(
                        onTap: () => Navigator.pushNamed(context, '/status'),
                        borderRadius: BorderRadius.circular(12),
                        child: const Padding(
                          padding: EdgeInsets.all(16),
                          child: Column(
                            children: [
                              Icon(
                                Icons.track_changes,
                                size: 40,
                                color: Color(0xFF059669),
                              ),
                              SizedBox(height: 8),
                              Text(
                                '신고 상태\n확인',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1F2937),
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Card(
                      child: InkWell(
                        onTap: _showEmergencyDialog,
                        borderRadius: BorderRadius.circular(12),
                        child: const Padding(
                          padding: EdgeInsets.all(16),
                          child: Column(
                            children: [
                              Icon(
                                Icons.emergency,
                                size: 40,
                                color: Color(0xFFEF4444),
                              ),
                              SizedBox(height: 8),
                              Text(
                                '긴급상황\n안내',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1F2937),
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // 안내 정보
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF1E40AF).withOpacity(0.2)),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Color(0xFF1E40AF),
                          size: 20,
                        ),
                        SizedBox(width: 8),
                        Text(
                          '신고 절차 안내',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1E40AF),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 12),
                    Text(
                      '1. 실종자의 기본 정보 입력\n'
                      '2. 실종자 사진 등록\n'
                      '3. 실종 상황 상세 설명\n'
                      '4. 신고자 정보 입력\n'
                      '5. 관리자 검토 및 승인 대기',
                      style: TextStyle(
                        fontSize: 14,
                        color: Color(0xFF1E40AF),
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}