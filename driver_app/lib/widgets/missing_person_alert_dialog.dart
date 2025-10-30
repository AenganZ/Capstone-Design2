import 'package:flutter/material.dart';
import 'dart:convert';
import '../models/missing_person.dart';

class MissingPersonAlertDialog extends StatelessWidget {
  final MissingPerson person;
  final VoidCallback onViewDetails;

  const MissingPersonAlertDialog({
    super.key,
    required this.person,
    required this.onViewDetails,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 800),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(context),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    _buildPhotoSection(),
                    _buildBasicInfoSection(),
                    _buildExtractedFeaturesSection(),
                    _buildRiskFactorsSection(),
                    _buildLocationSection(),
                  ],
                ),
              ),
            ),
            _buildActionButtons(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Color(0xFFEF4444),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.notification_important,
            color: Colors.white,
            size: 28,
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              '긴급 실종자 알림',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoSection() {
    return Container(
      width: double.infinity,
      height: 300,
      color: Colors.black,
      child: person.photoBase64 != null && person.photoBase64!.isNotEmpty
          ? _buildSafeImage()
          : const Center(
              child: Icon(
                Icons.person,
                size: 100,
                color: Colors.white54,
              ),
            ),
    );
  }

  Widget _buildSafeImage() {
    try {
      if (person.photoBase64 == null || person.photoBase64!.isEmpty) {
        return _buildPlaceholderIcon();
      }
      
      final bytes = base64Decode(person.photoBase64!);
      
      return Image.memory(
        bytes,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          print('다이얼로그 이미지 로딩 실패: $error');
          return _buildPlaceholderIcon();
        },
      );
    } catch (e) {
      print('다이얼로그 이미지 디코딩 오류: ${e.toString()}');
      return _buildPlaceholderIcon();
    }
  }

  Widget _buildPlaceholderIcon() {
    return const Center(
      child: Icon(
        Icons.person,
        size: 100,
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
                  person.name ?? '이름 미상',
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
          _buildInfoRow('나이', person.age?.toString() ?? '미상'),
          _buildInfoRow('성별', person.gender ?? '미상'),
          _buildInfoRow('카테고리', person.category ?? '미상'),
          if (person.description != null && person.description!.isNotEmpty)
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
                    person.description!,
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
    if (person.extractedFeatures.isEmpty) return const SizedBox.shrink();

    final features = person.extractedFeatures;
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
    if (person.riskFactors.isEmpty) return const SizedBox.shrink();

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
            children: person.riskFactors.map((factor) {
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
              person.location ?? '위치 정보 없음',
              style: const TextStyle(
                fontSize: 16,
                color: Color(0xFF1F2937),
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Color(0xFFE5E7EB), width: 1),
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                side: const BorderSide(color: Color(0xFF1E40AF)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                '닫기',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E40AF),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                onViewDetails();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E40AF),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: const Text(
                '상세 보기',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPriorityBadge() {
    Color color;
    switch (person.priority) {
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
        person.priority == 'HIGH' ? '긴급' : person.priority == 'LOW' ? '낮음' : '보통',
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
}