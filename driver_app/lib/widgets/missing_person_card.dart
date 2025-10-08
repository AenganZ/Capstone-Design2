import 'package:flutter/material.dart';
import 'dart:convert';
import '../models/missing_person.dart';

class MissingPersonCard extends StatelessWidget {
  final MissingPerson person;
  final VoidCallback onTap;

  const MissingPersonCard({
    super.key,
    required this.person,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildPhoto(),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            person.name ?? '이름 미상',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1F2937),
                            ),
                          ),
                        ),
                        _buildPriorityBadge(),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _buildInfoRow(Icons.person, _buildBasicInfo()),
                    const SizedBox(height: 4),
                    _buildInfoRow(Icons.location_on, person.location ?? '위치 미상'),
                    const SizedBox(height: 4),
                    _buildInfoRow(Icons.category, person.getCategoryText()),
                    if (person.riskFactors.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: person.riskFactors.take(3).map((factor) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEE2E2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              factor,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF991B1B),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPhoto() {
    if (person.photoBase64 != null && person.photoBase64!.isNotEmpty) {
      try {
        String cleanBase64 = person.photoBase64!
            .replaceAll(RegExp(r'\s+'), '')
            .replaceAll(RegExp(r'[^A-Za-z0-9+/=]'), '');
        
        if (cleanBase64.isEmpty) {
          return _buildPlaceholderPhoto();
        }
        
        final bytes = base64Decode(cleanBase64);
        return Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            image: DecorationImage(
              image: MemoryImage(bytes),
              fit: BoxFit.cover,
            ),
          ),
        );
      } catch (e) {
        print('이미지 디코딩 오류: $e');
        return _buildPlaceholderPhoto();
      }
    }
    return _buildPlaceholderPhoto();
  }

  Widget _buildPlaceholderPhoto() {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: const Color(0xFFE5E7EB),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(
        Icons.person,
        size: 40,
        color: Color(0xFF9CA3AF),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        person.getPriorityText(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFF6B7280)),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF6B7280),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  String _buildBasicInfo() {
    final parts = <String>[];
    if (person.age != null) parts.add('${person.age}세');
    if (person.gender != null) parts.add(person.gender!);
    return parts.isEmpty ? '정보 없음' : parts.join(' ');
  }
}