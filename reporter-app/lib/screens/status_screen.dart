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
    setState(() {
      _isLoading = true;
    });

    try {
      final results = await Future.wait([
        ApiService.getServerStatus(),
        ApiService.getLocalReports(),
      ]);

      final serverStatus = results[0] as Map<String, dynamic>;
      final localReports = results[1] as List<Map<String, dynamic>>;

      setState(() {
        _serverStatus = serverStatus;
        _localReports = localReports;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
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
              _buildStatusRow('Firebase', _serverStatus!['firebase'] == true ? '연결됨' : '연결 안됨'),
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
                if (_localReports.isNotEmpty)
                  TextButton(
                    onPressed: _retryFailedReports,
                    child: const Text('재전송'),
                  ),
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
              ...(_localReports.map((report) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.pending,
                          color: Color(0xFFF59E0B),
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${report['name']} (${report['age']}세)',
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
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

  Future<void> _retryFailedReports() async {
    try {
      final localReports = await ApiService.getLocalReports();
      int successCount = 0;
      int failCount = 0;

      for (var report in localReports) {
        try {
          final result = await ApiService.submitMissingPerson(
            name: report['name'],
            age: report['age'],
            gender: report['gender'],
            missingLocation: report['location'],
            missingDateTime: DateTime.parse(report['missing_datetime']),
            reporterName: report['reporter_name'],
            reporterPhone: report['reporter_phone'],
            reporterRelation: report['reporter_relation'],
            description: report['description'],
          );

          if (result['success']) {
            successCount++;
          } else {
            failCount++;
          }
        } catch (e) {
          failCount++;
        }
      }

      if (successCount > 0) {
        await ApiService.clearLocalReports();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$successCount개 신고 전송 성공, $failCount개 실패'),
            backgroundColor: successCount > 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444),
          ),
        );
        _loadStatusData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('재전송 중 오류가 발생했습니다'),
            backgroundColor: Color(0xFFEF4444),
          ),
        );
      }
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
            child: const Text('삭제'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ApiService.clearLocalReports();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('로컬 데이터가 삭제되었습니다'),
            backgroundColor: Color(0xFF10B981),
          ),
        );
        _loadStatusData();
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
              '개발: AenganZ 팀',
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