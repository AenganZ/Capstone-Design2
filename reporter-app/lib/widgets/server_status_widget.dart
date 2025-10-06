import 'package:flutter/material.dart';
import 'dart:async';
import '../services/api_service.dart';

class ServerStatusWidget extends StatefulWidget {
  final bool showDetails;
  
  const ServerStatusWidget({
    super.key,
    this.showDetails = false,
  });

  @override
  State<ServerStatusWidget> createState() => _ServerStatusWidgetState();
}

class _ServerStatusWidgetState extends State<ServerStatusWidget> {
  bool _isConnected = false;
  bool _isChecking = false;
  Map<String, dynamic>? _serverStatus;
  Timer? _statusTimer;
  DateTime? _lastChecked;

  @override
  void initState() {
    super.initState();
    _checkServerStatus();
    _startPeriodicCheck();
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    super.dispose();
  }

  void _startPeriodicCheck() {
    _statusTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) {
        _checkServerStatus();
      }
    });
  }

  Future<void> _checkServerStatus() async {
    if (_isChecking) return;

    setState(() {
      _isChecking = true;
    });

    try {
      final status = await ApiService.getServerStatus();
      
      if (mounted) {
        setState(() {
          _isConnected = status['success'] == true;
          _serverStatus = status;
          _lastChecked = DateTime.now();
          _isChecking = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isConnected = false;
          _serverStatus = null;
          _lastChecked = DateTime.now();
          _isChecking = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.showDetails) {
      return _buildCompactStatus();
    }

    return _buildDetailedStatus();
  }

  Widget _buildCompactStatus() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _isConnected 
            ? const Color(0xFF10B981).withOpacity(0.1)
            : const Color(0xFFEF4444).withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _isConnected 
              ? const Color(0xFF10B981).withOpacity(0.3)
              : const Color(0xFFEF4444).withOpacity(0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: _isConnected ? const Color(0xFF10B981) : const Color(0xFFEF4444),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _isConnected ? '서버 연결됨' : '서버 연결 끊김',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: _isConnected ? const Color(0xFF10B981) : const Color(0xFFEF4444),
            ),
          ),
          if (_isChecking) ...[
            const SizedBox(width: 8),
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(
                  _isConnected ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailedStatus() {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.all(0),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _isConnected ? Icons.cloud_done : Icons.cloud_off,
                  color: _isConnected ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                  size: 24,
                ),
                const SizedBox(width: 8),
                const Text(
                  '서버 연결 상태',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1F2937),
                  ),
                ),
                const Spacer(),
                if (_isChecking)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF1E40AF)),
                    ),
                  )
                else
                  IconButton(
                    onPressed: _checkServerStatus,
                    icon: const Icon(Icons.refresh),
                    iconSize: 20,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _isConnected 
                    ? const Color(0xFF10B981).withOpacity(0.1)
                    : const Color(0xFFEF4444).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _isConnected 
                      ? const Color(0xFF10B981).withOpacity(0.3)
                      : const Color(0xFFEF4444).withOpacity(0.3),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: _isConnected ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isConnected ? '서버에 연결되어 있습니다' : '서버에 연결할 수 없습니다',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: _isConnected ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                          ),
                        ),
                        if (_lastChecked != null)
                          Text(
                            '마지막 확인: ${_formatTime(_lastChecked!)}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF6B7280),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            if (_isConnected && _serverStatus != null) ...[
              const SizedBox(height: 16),
              const Text(
                '서버 정보',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF374151),
                ),
              ),
              const SizedBox(height: 8),
              _buildInfoRow('상태', _serverStatus!['status'] ?? 'Unknown'),
              _buildInfoRow(
                'Firebase', 
                _serverStatus!['firebase'] == true ? '연결됨' : '연결 안됨',
                valueColor: _serverStatus!['firebase'] == true 
                    ? const Color(0xFF10B981) 
                    : const Color(0xFFEF4444),
              ),
              if (_serverStatus!['timestamp'] != null)
                _buildInfoRow(
                  '서버 시간', 
                  _formatServerTime(_serverStatus!['timestamp']),
                ),
            ],

            if (!_isConnected) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.warning_amber,
                      color: Color(0xFFF59E0B),
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '오프라인 모드',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFF59E0B),
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            '신고 내용이 로컬에 저장되며, 연결 복구 시 자동 전송됩니다.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFFF59E0B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF6B7280),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: valueColor ?? const Color(0xFF374151),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return '방금 전';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}분 전';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}시간 전';
    } else {
      return '${dateTime.month}/${dateTime.day} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
    }
  }

  String _formatServerTime(String timestamp) {
    try {
      final dt = DateTime.parse(timestamp);
      return '${dt.month}/${dt.day} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return timestamp;
    }
  }
}