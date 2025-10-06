import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../models/missing_report.dart';
import '../services/api_service.dart';

class StatusScreen extends StatefulWidget {
  const StatusScreen({super.key});

  @override
  State<StatusScreen> createState() => _StatusScreenState();
}

class _StatusScreenState extends State<StatusScreen> {
  final TextEditingController _reportIdController = TextEditingController();
  ReportStatus? _reportStatus;
  bool _isLoading = false;
  String? _errorMessage;
  int? _initialReportId;

  @override
  void initState() {
    super.initState();
    _loadLastReportId();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    
    final arguments = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    if (arguments != null && arguments['reportId'] != null) {
      _initialReportId = arguments['reportId'];
      _reportIdController.text = _initialReportId.toString();
      _checkStatus();
    }
  }

  @override
  void dispose() {
    _reportIdController.dispose();
    super.dispose();
  }

  Future<void> _loadLastReportId() async {
    if (_initialReportId != null) return;
    
    final prefs = await SharedPreferences.getInstance();
    final lastReportId = prefs.getInt('last_report_id');
    if (lastReportId != null) {
      setState(() {
        _reportIdController.text = lastReportId.toString();
      });
    }
  }

  Future<void> _checkStatus() async {
    final reportIdText = _reportIdController.text.trim();
    if (reportIdText.isEmpty) {
      setState(() {
        _errorMessage = '신고 번호를 입력해주세요';
      });
      return;
    }

    final reportId = int.tryParse(reportIdText);
    if (reportId == null) {
      setState(() {
        _errorMessage = '올바른 신고 번호를 입력해주세요';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _reportStatus = null;
    });

    try {
      final status = await ApiService.getReportStatus(reportId);
      setState(() {
        _reportStatus = status;
        _isLoading = false;
      });
    } on ApiException catch (e) {
      setState(() {
        _errorMessage = e.message;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = '상태 확인 중 오류가 발생했습니다';
        _isLoading = false;
      });
    }
  }

  void _copyReportId() {
    Clipboard.setData(ClipboardData(text: _reportIdController.text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('신고 번호가 복사되었습니다'),
        backgroundColor: Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'PENDING':
        return const Color(0xFFF59E0B);
      case 'APPROVED':
        return const Color(0xFF10B981);
      case 'REJECTED':
        return const Color(0xFFEF4444);
      default:
        return const Color(0xFF6B7280);
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'PENDING':
        return Icons.hourglass_empty;
      case 'APPROVED':
        return Icons.check_circle;
      case 'REJECTED':
        return Icons.cancel;
      default:
        return Icons.help;
    }
  }

  String _formatDateTime(String? dateTimeString) {
    if (dateTimeString == null) return '-';
    try {
      final dateTime = DateTime.parse(dateTimeString);
      return DateFormat('yyyy년 MM월 dd일 HH:mm').format(dateTime);
    } catch (e) {
      return dateTimeString;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('신고 상태 확인'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '신고 번호 입력',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1F2937),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _reportIdController,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              decoration: const InputDecoration(
                                labelText: '신고 번호',
                                hintText: '신고 시 받은 번호를 입력하세요',
                                prefixText: '#',
                              ),
                              onChanged: (value) {
                                setState(() {
                                  _errorMessage = null;
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.copy),
                            onPressed: _reportIdController.text.isNotEmpty 
                                ? _copyReportId 
                                : null,
                            tooltip: '복사',
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _checkStatus,
                          child: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : const Text('상태 확인'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: Color(0xFFEF4444),
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(
                            color: Color(0xFFEF4444),
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              if (_reportStatus != null) ...[
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _getStatusIcon(_reportStatus!.status),
                              color: _getStatusColor(_reportStatus!.status),
                              size: 24,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _reportStatus!.statusText,
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: _getStatusColor(_reportStatus!.status),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        
                        _buildStatusRow('신고 번호', '#${_reportStatus!.reportId}'),
                        _buildStatusRow('접수 일시', _formatDateTime(_reportStatus!.submittedAt)),
                        
                        if (_reportStatus!.reviewedAt != null)
                          _buildStatusRow('검토 일시', _formatDateTime(_reportStatus!.reviewedAt)),
                        
                        if (_reportStatus!.reviewerNotes != null && _reportStatus!.reviewerNotes!.isNotEmpty)
                          _buildStatusRow('검토 의견', _reportStatus!.reviewerNotes!),
                        
                        if (_reportStatus!.createdPersonId != null)
                          _buildStatusRow('실종자 ID', _reportStatus!.createdPersonId!),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),
                _buildStatusDescription(_reportStatus!.status),
              ],

              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(8),
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
                          '안내사항',
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
                      '• 신고 번호는 신고 접수 시 발급됩니다\n'
                      '• 관리자 검토는 보통 1-2시간 내에 완료됩니다\n'
                      '• 승인 시 즉시 수색 활동이 시작됩니다\n'
                      '• 추가 문의사항은 관리자에게 연락하세요',
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

  Widget _buildStatusRow(String label, String value) {
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
                fontSize: 14,
                color: Color(0xFF6B7280),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF1F2937),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusDescription(String status) {
    String title;
    String description;
    Color backgroundColor;
    Color borderColor;
    Color textColor;

    switch (status) {
      case 'PENDING':
        title = '검토 대기 중';
        description = '관리자가 신고 내용을 검토하고 있습니다. 잠시만 기다려주세요.';
        backgroundColor = const Color(0xFFFEF3C7);
        borderColor = const Color(0xFFF59E0B);
        textColor = const Color(0xFFF59E0B);
        break;
      case 'APPROVED':
        title = '승인 완료';
        description = '신고가 승인되어 실종자로 등록되었습니다. 수색 활동이 시작되었습니다.';
        backgroundColor = const Color(0xFFF0FDF4);
        borderColor = const Color(0xFF10B981);
        textColor = const Color(0xFF10B981);
        break;
      case 'REJECTED':
        title = '신고 거부';
        description = '신고가 거부되었습니다. 자세한 사유는 검토 의견을 확인해주세요.';
        backgroundColor = const Color(0xFFFEF2F2);
        borderColor = const Color(0xFFEF4444);
        textColor = const Color(0xFFEF4444);
        break;
      default:
        title = '알 수 없는 상태';
        description = '상태를 확인할 수 없습니다.';
        backgroundColor = const Color(0xFFF9FAFB);
        borderColor = const Color(0xFF6B7280);
        textColor = const Color(0xFF6B7280);
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: TextStyle(
              fontSize: 14,
              color: textColor,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}