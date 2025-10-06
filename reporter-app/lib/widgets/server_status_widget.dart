import 'package:flutter/material.dart';

class ServerStatusWidget extends StatelessWidget {
  final bool isConnected;
  final bool isChecking;
  final VoidCallback? onRefresh;

  const ServerStatusWidget({
    super.key,
    required this.isConnected,
    required this.isChecking,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    Color statusColor;
    IconData statusIcon;
    String statusText;
    String statusDescription;

    if (isChecking) {
      statusColor = const Color(0xFFF59E0B);
      statusIcon = Icons.sync;
      statusText = '서버 연결 확인 중...';
      statusDescription = '잠시만 기다려주세요';
    } else if (isConnected) {
      statusColor = const Color(0xFF10B981);
      statusIcon = Icons.check_circle;
      statusText = '서버 연결됨';
      statusDescription = '신고 접수가 가능합니다';
    } else {
      statusColor = const Color(0xFFEF4444);
      statusIcon = Icons.error;
      statusText = '서버 연결 실패';
      statusDescription = '네트워크 상태를 확인해주세요';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: statusColor.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          if (isChecking)
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(statusColor),
              ),
            )
          else
            Icon(
              statusIcon,
              color: statusColor,
              size: 24,
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  statusDescription,
                  style: TextStyle(
                    fontSize: 14,
                    color: statusColor.withOpacity(0.8),
                  ),
                ),
              ],
            ),
          ),
          if (onRefresh != null && !isChecking)
            IconButton(
              icon: Icon(
                Icons.refresh,
                color: statusColor,
              ),
              onPressed: onRefresh,
              tooltip: '다시 확인',
            ),
        ],
      ),
    );
  }
}