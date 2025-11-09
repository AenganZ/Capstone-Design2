import 'package:flutter/material.dart';
import 'dart:convert';
import '../models/missing_person.dart';
import '../services/api_service.dart';
import 'report_success_screen.dart';

class MissingPersonDetailScreen extends StatefulWidget {
  final MissingPerson person;
  final String driverId;

  const MissingPersonDetailScreen({
    super.key,
    required this.person,
    required this.driverId,
  });

  @override
  State<MissingPersonDetailScreen> createState() => _MissingPersonDetailScreenState();
}

class _MissingPersonDetailScreenState extends State<MissingPersonDetailScreen> {
  bool _isReporting = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          '실종자 상세 정보',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF1E40AF),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPhotoSection(),
            _buildBasicInfoSection(),
            _buildExtractedFeaturesSection(),
            _buildRiskFactorsSection(),
            _buildLocationSection(),
            const SizedBox(height: 80),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  // ✅ 사진 크기 증가: 500 → 600
  Widget _buildPhotoSection() {
    return Container(
      width: double.infinity,
      height: 600,  // ✅ 500 → 600으로 증가
      color: Colors.black,
      child: widget.person.photoBase64 != null && widget.person.photoBase64!.isNotEmpty
          ? _buildSafeImage()
          : const Center(
              child: Icon(
                Icons.person,
                size: 180,  // ✅ 아이콘도 더 크게
                color: Colors.white54,
              ),
            ),
    );
  }

  Widget _buildSafeImage() {
    try {
      if (widget.person.photoBase64 == null || widget.person.photoBase64!.isEmpty) {
        return _buildPlaceholderIcon();
      }
      
      final bytes = base64Decode(widget.person.photoBase64!);
      
      return Image.memory(
        bytes,
        width: double.infinity,
        height: 600,  // ✅ 높이 600
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          print('상세화면 이미지 로딩 실패: $error');
          return _buildPlaceholderIcon();
        },
      );
    } catch (e) {
      print('상세화면 이미지 디코딩 오류: ${e.toString()}');
      print('Base64 길이: ${widget.person.photoBase64?.length ?? 0}');
      return _buildPlaceholderIcon();
    }
  }

  Widget _buildPlaceholderIcon() {
    return const Center(
      child: Icon(
        Icons.person,
        size: 180,  // ✅ 플레이스홀더도 크게
        color: Colors.white54,
      ),
    );
  }

  Widget _buildBasicInfoSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Color(0xFFE5E7EB), width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.person.name ?? '이름 미상',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1F2937),
                  ),
                ),
              ),
              _buildPriorityBadge(),
            ],
          ),
          const SizedBox(height: 16),
          _buildInfoRow('나이', widget.person.age?.toString() ?? '미상'),
          _buildInfoRow('성별', widget.person.gender ?? '미상'),
          _buildInfoRow('카테고리', widget.person.getCategoryText()),
          if (widget.person.lastSeen != null)
            _buildInfoRow('최종 목격', widget.person.lastSeen!),
          if (widget.person.description != null && widget.person.description!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '상세 설명',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.person.description!,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Color(0xFF1F2937),
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildExtractedFeaturesSection() {
    if (widget.person.extractedFeatures.isEmpty) return const SizedBox.shrink();

    final features = widget.person.extractedFeatures;
    final featureCategories = {
      'basic_info': {'title': '기본 정보', 'icon': Icons.person, 'color': const Color(0xFFDBEAFE)},
      'appearance': {'title': '외모 특징', 'icon': Icons.face, 'color': const Color(0xFFFEF3C7)},
      'clothing': {'title': '의복', 'icon': Icons.checkroom, 'color': const Color(0xFFE0E7FF)},
      'behavior': {'title': '행동 특성', 'icon': Icons.directions_walk, 'color': const Color(0xFFFCE7F3)},
      'health': {'title': '건강 상태', 'icon': Icons.medical_services, 'color': const Color(0xFFFEE2E2)},
      'items': {'title': '소지품', 'icon': Icons.shopping_bag, 'color': const Color(0xFFD1FAE5)},
      'transport': {'title': '이동수단', 'icon': Icons.directions_car, 'color': const Color(0xFFCFFAFE)},
      'additional': {'title': '기타 정보', 'icon': Icons.info, 'color': const Color(0xFFF3F4F6)},
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Color(0xFFE5E7EB), width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '추출된 특징',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1F2937),
            ),
          ),
          const SizedBox(height: 16),
          ...features.entries.where((entry) {
            if (entry.value is! List) return false;
            final list = entry.value as List;
            return list.isNotEmpty;
          }).map((entry) {
            final category = featureCategories[entry.key];
            if (category == null) return const SizedBox.shrink();
            
            final items = entry.value as List;
            
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: category['color'] as Color,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        category['icon'] as IconData,
                        size: 20,
                        color: const Color(0xFF1F2937),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        category['title'] as String,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1F2937),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: items.map((item) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          item.toString(),
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF1F2937),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildRiskFactorsSection() {
    if (widget.person.riskFactors.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Color(0xFFE5E7EB), width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.warning,
                color: Color(0xFFEF4444),
                size: 24,
              ),
              SizedBox(width: 8),
              Text(
                '위험 요소',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1F2937),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: widget.person.riskFactors.map((factor) {
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFFEF4444),
                    width: 1,
                  ),
                ),
                child: Text(
                  factor,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF991B1B),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Color(0xFFE5E7EB), width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.location_on,
                color: Color(0xFF1E40AF),
                size: 24,
              ),
              SizedBox(width: 8),
              Text(
                '실종 장소',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1F2937),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F9FF),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              widget.person.location ?? '위치 정보 없음',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1F2937),
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: _isReporting
            ? const Center(
                child: CircularProgressIndicator(),
              )
            : ElevatedButton(
                onPressed: _showReportDialog,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFEF4444),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.report, size: 24),
                    SizedBox(width: 8),
                    Text(
                      '목격 신고하기',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildPriorityBadge() {
    Color color;
    switch (widget.person.priority) {
      case 'HIGH':
        color = const Color(0xFFEF4444);
        break;
      case 'LOW':
        color = const Color(0xFF10B981);
        break;
      default:
        color = const Color(0xFFF59E0B);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        widget.person.getPriorityText(),
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
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
                fontWeight: FontWeight.w600,
                color: Color(0xFF6B7280),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 16,
                color: Color(0xFF1F2937),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showReportDialog() {
    final descriptionController = TextEditingController();
    String confidenceLevel = 'MEDIUM';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('목격 신고'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '목격 상황을 상세히 설명해주세요',
                  style: TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descriptionController,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    hintText: '예: 대전역 앞에서 목격했습니다. 파란색 옷을 입고 있었습니다.',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '확신 수준',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                DropdownButton<String>(
                  value: confidenceLevel,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(value: 'HIGH', child: Text('확실함')),
                    DropdownMenuItem(value: 'MEDIUM', child: Text('보통')),
                    DropdownMenuItem(value: 'LOW', child: Text('불확실함')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() {
                        confidenceLevel = value;
                      });
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (descriptionController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('목격 상황을 입력해주세요')),
                  );
                  return;
                }

                Navigator.pop(context);
                await _submitReport(
                  descriptionController.text,
                  confidenceLevel,
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
                foregroundColor: Colors.white,
              ),
              child: const Text('신고하기'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitReport(
    String description,
    String confidenceLevel,
  ) async {
    setState(() {
      _isReporting = true;
    });

    try {
      final result = await ApiService.reportSighting(
        personId: widget.person.id,
        location: {
          'lat': 36.3504,
          'lng': 127.3845,
        },
        description: description,
        reporterId: widget.driverId,
        confidenceLevel: confidenceLevel,
      );

      setState(() {
        _isReporting = false;
      });

      if (result['success'] == true && mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => ReportSuccessScreen(
              personName: widget.person.name ?? '이름 미상',
              reportId: result['report_id'],
            ),
          ),
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message'] ?? '신고 접수 실패'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      setState(() {
        _isReporting = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('오류 발생: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}