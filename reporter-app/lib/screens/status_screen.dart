import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../widgets/server_status_widget.dart';

class StatusScreen extends StatefulWidget {
  const StatusScreen({super.key});

  @override
  State<StatusScreen> createState() => _StatusScreenState();
}

class _StatusScreenState extends State<StatusScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _serverStatus;
  List<Map<String, dynamic>> _localReports = [];

  @override
  void initState() {
    super.initState();
    _loadStatusData();
  }

  Future<void> _loadStatusData() async {
    if (!mounted) return;
    
    setState(() {
      _isLoading = true;
    });

    try {
      print('=== 상태 데이터 로드 시작 ===');
      
      final results = await Future.wait([
        ApiService.getServerStatus(),
        ApiService.getLocalReports(),
      ]);

      final serverStatus = results[0] as Map<String, dynamic>;
      final localReports = results[1] as List<Map<String, dynamic>>;
      
      print('서버 상태: ${serverStatus['success']}');
      print('로컬 신고 개수: ${localReports.length}');
      
      if (localReports.isNotEmpty) {
        print('로컬 신고 내역:');
        for (var report in localReports) {
          print('  - ${report['name']} (${report['age']}세)');
        }
      } else {
        print('로컬 신고 없음');
      }

      if (!mounted) return;
      
      setState(() {
        _serverStatus = serverStatus;
        _localReports = localReports;
        _isLoading = false;
      });
      
      print('=== 상태 데이터 로드 완료 ===');
    } catch (e, stackTrace) {
      print('상태 데이터 로드 오류: $e');
      print('스택 트레이스: $stackTrace');
      
      if (!mounted) return;
      
      setState(() {
        _isLoading = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('데이터를 불러오는 중 오류가 발생했습니다'),
            backgroundColor: Color(0xFFEF4444),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('시스템 상태'),
        actions: [
          IconButton(
            onPressed: _loadStatusData,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF1E40AF)),
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadStatusData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildServerStatusCard(),
                  const SizedBox(height: 16),
                  _buildLocalReportsCard(),
                  const SizedBox(height: 16),
                  _buildQuickActionsCard(),
                ],
              ),
            ),
    );
  }

  Widget _buildServerStatusCard() {
    final isConnected = _serverStatus?['success'] == true;
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isConnected ? Icons.cloud_done : Icons.cloud_off,
                  color: isConnected ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                  size: 24,
                ),
                const SizedBox(width: 8),
                const Text(
                  '서버 연결 상태',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isConnected 
                    ? const Color(0xFF10B981).withOpacity(0.1)
                    : const Color(0xFFEF4444).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: isConnected ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isConnected ? '서버 연결됨' : '서버 연결 끊김',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isConnected ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                    ),
                  ),
                ],
              ),
            ),
            if (isConnected && _serverStatus != null) ...[
              const SizedBox(height: 12),
              _buildStatusRow('상태', _serverStatus!['status'] ?? 'Unknown'),
              if (_serverStatus!['timestamp'] != null)
                _buildStatusRow('마지막 업데이트', _formatTimestamp(_serverStatus!['timestamp'])),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLocalReportsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.save_outlined,
                  color: Color(0xFF1E40AF),
                  size: 24,
                ),
                const SizedBox(width: 8),
                const Text(
                  '로컬 저장된 신고',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
              ],
            ),
            const SizedBox(height: 12),
            if (_localReports.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9FAFB),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      color: Color(0xFF10B981),
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Text(
                      '저장된 신고가 없습니다',
                      style: TextStyle(color: Color(0xFF6B7280)),
                    ),
                  ],
                ),
              )
            else
              ...(_localReports.map((report) => InkWell(
                    onTap: () => _showReportDetail(report),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.pending,
                            color: Color(0xFFF59E0B),
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${report['name']} (${report['age']}세, ${report['gender']})',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  report['location'] ?? '',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF6B7280),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.arrow_forward_ios,
                            size: 16,
                            color: Color(0xFFF59E0B),
                          ),
                        ],
                      ),
                    ),
                  ))),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.speed,
                  color: Color(0xFF1E40AF),
                  size: 24,
                ),
                SizedBox(width: 8),
                Text(
                  '빠른 작업',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildActionButton(
              icon: Icons.refresh,
              label: '서버 연결 테스트',
              onTap: _testConnection,
            ),
            const SizedBox(height: 8),
            _buildActionButton(
              icon: Icons.clear_all,
              label: '로컬 데이터 삭제',
              onTap: _clearLocalData,
            ),
            const SizedBox(height: 8),
            _buildActionButton(
              icon: Icons.info_outline,
              label: '앱 정보',
              onTap: _showAppInfo,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: Color(0xFF6B7280)),
          ),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFE5E7EB)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: const Color(0xFF1E40AF),
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF374151),
                ),
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios,
              color: Color(0xFF9CA3AF),
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(String timestamp) {
    try {
      final dt = DateTime.parse(timestamp);
      return '${dt.month}/${dt.day} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return timestamp;
    }
  }

  void _showReportDetail(Map<String, dynamic> report) async {
    // 서버에서 최신 상태 확인
    Map<String, dynamic>? serverStatus;
    if (report['person_id'] != null) {
      try {
        final statusResult = await ApiService.checkReportStatus(report['person_id']);
        if (statusResult['success']) {
          serverStatus = statusResult;
        }
      } catch (e) {
        print('상태 확인 오류: $e');
      }
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.person, color: Color(0xFF1E40AF)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${report['name']}님 신고 내역',
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 서버 상태 표시
              if (serverStatus != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: serverStatus['status'] == 'APPROVED'
                        ? const Color(0xFF10B981).withOpacity(0.1)
                        : serverStatus['status'] == 'REJECTED'
                            ? const Color(0xFFEF4444).withOpacity(0.1)
                            : const Color(0xFFF59E0B).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            serverStatus['status'] == 'APPROVED'
                                ? Icons.check_circle
                                : serverStatus['status'] == 'REJECTED'
                                    ? Icons.cancel
                                    : Icons.pending,
                            color: serverStatus['status'] == 'APPROVED'
                                ? const Color(0xFF10B981)
                                : serverStatus['status'] == 'REJECTED'
                                    ? const Color(0xFFEF4444)
                                    : const Color(0xFFF59E0B),
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            serverStatus['status'] == 'APPROVED'
                                ? '승인됨'
                                : serverStatus['status'] == 'REJECTED'
                                    ? '거절됨'
                                    : '검토 대기 중',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: serverStatus['status'] == 'APPROVED'
                                  ? const Color(0xFF10B981)
                                  : serverStatus['status'] == 'REJECTED'
                                      ? const Color(0xFFEF4444)
                                      : const Color(0xFFF59E0B),
                            ),
                          ),
                        ],
                      ),
                      if (serverStatus['status'] == 'REJECTED' && 
                          serverStatus['rejection_reason'] != null) ...[
                        const SizedBox(height: 8),
                        const Text(
                          '거절 사유:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          serverStatus['rejection_reason'],
                          style: const TextStyle(
                            color: Color(0xFFEF4444),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              
              _buildDetailRow('이름', report['name']),
              _buildDetailRow('나이', '${report['age']}세'),
              _buildDetailRow('성별', report['gender']),
              _buildDetailRow('실종 장소', report['location']),
              _buildDetailRow('실종 일시', _formatDateTime(report['missing_datetime'])),
              const Divider(height: 24),
              _buildDetailRow('신고자', report['reporter_name']),
              _buildDetailRow('연락처', report['reporter_phone']),
              _buildDetailRow('관계', report['reporter_relation']),
              if (report['description'] != null && report['description'].isNotEmpty) ...[
                const Divider(height: 24),
                const Text(
                  '상세 설명',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF374151),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  report['description'],
                  style: const TextStyle(color: Color(0xFF6B7280)),
                ),
              ],
              const Divider(height: 24),
              _buildDetailRow('신고 번호', report['person_id']?.substring(0, 8) ?? 'N/A'),
              _buildDetailRow('신고 일시', _formatDateTime(report['created_at'])),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF6B7280),
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                color: Color(0xFF1F2937),
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(String? datetime) {
    if (datetime == null) return 'N/A';
    try {
      final dt = DateTime.parse(datetime);
      return '${dt.year}년 ${dt.month}월 ${dt.day}일 ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return datetime;
    }
  }

  Future<void> _testConnection() async {
    final result = await ApiService.testConnection();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result ? '서버 연결 성공' : '서버 연결 실패'),
          backgroundColor: result ? const Color(0xFF10B981) : const Color(0xFFEF4444),
        ),
      );
    }
  }

  Future<void> _clearLocalData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('로컬 데이터 삭제'),
        content: const Text('저장된 모든 로컬 데이터를 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('삭제'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await ApiService.clearLocalReports();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('로컬 데이터가 삭제되었습니다'),
              backgroundColor: Color(0xFF10B981),
            ),
          );
          await _loadStatusData();
        }
      } catch (e) {
        print('로컬 데이터 삭제 오류: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('데이터 삭제 중 오류가 발생했습니다'),
              backgroundColor: Color(0xFFEF4444),
            ),
          );
        }
      }
    }
  }

  void _showAppInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('앱 정보'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '대전시 실종자 신고 앱',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text('버전: 1.0.0'),
            SizedBox(height: 8),
            Text('대전 이동 안전망 시스템'),
            Text('실종자 신고 및 관리 플랫폼'),
            SizedBox(height: 8),
            Text(
              '개발: 레드성준 팀',
              style: TextStyle(color: Color(0xFF6B7280)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }
}