import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'dart:io';
import '../models/missing_report.dart';
import '../services/api_service.dart';
import '../widgets/photo_selector_widget.dart';
import '../widgets/custom_text_field.dart';

class ReportFormScreen extends StatefulWidget {
  const ReportFormScreen({super.key});

  @override
  State<ReportFormScreen> createState() => _ReportFormScreenState();
}

class _ReportFormScreenState extends State<ReportFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _pageController = PageController();
  int _currentPage = 0;
  bool _isSubmitting = false;

  // 실종자 정보
  final _nameController = TextEditingController();
  final _ageController = TextEditingController();
  String? _selectedGender;
  final _missingLocationController = TextEditingController();
  DateTime? _missingDateTime;
  final _descriptionController = TextEditingController();
  final _additionalInfoController = TextEditingController();

  // 신고자 정보
  final _reporterNameController = TextEditingController();
  final _reporterPhoneController = TextEditingController();
  String? _selectedRelation;

  // 사진
  File? _selectedPhoto;
  String? _photoBase64;

  final List<String> _genderOptions = ['남자', '여자'];
  final List<String> _relationOptions = [
    '가족', '친구', '지인', '이웃', '기타'
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    _missingLocationController.dispose();
    _descriptionController.dispose();
    _additionalInfoController.dispose();
    _reporterNameController.dispose();
    _reporterPhoneController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < 2) {
      if (_validateCurrentPage()) {
        _pageController.nextPage(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    } else {
      _submitReport();
    }
  }

  void _previousPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  bool _validateCurrentPage() {
    switch (_currentPage) {
      case 0:
        return _validateMissingPersonInfo();
      case 1:
        return _validateReporterInfo();
      case 2:
        return true;
      default:
        return false;
    }
  }

  bool _validateMissingPersonInfo() {
    if (_nameController.text.trim().isEmpty) {
      _showSnackBar('실종자 이름을 입력해주세요', isError: true);
      return false;
    }
    if (_missingLocationController.text.trim().isEmpty) {
      _showSnackBar('실종 장소를 입력해주세요', isError: true);
      return false;
    }
    if (_missingDateTime == null) {
      _showSnackBar('실종 일시를 선택해주세요', isError: true);
      return false;
    }
    if (_descriptionController.text.trim().isEmpty) {
      _showSnackBar('실종 상황을 입력해주세요', isError: true);
      return false;
    }
    return true;
  }

  bool _validateReporterInfo() {
    if (_reporterNameController.text.trim().isEmpty) {
      _showSnackBar('신고자 이름을 입력해주세요', isError: true);
      return false;
    }
    if (_reporterPhoneController.text.trim().isEmpty) {
      _showSnackBar('신고자 연락처를 입력해주세요', isError: true);
      return false;
    }
    if (_selectedRelation == null) {
      _showSnackBar('실종자와의 관계를 선택해주세요', isError: true);
      return false;
    }
    return true;
  }

  Future<void> _selectDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now().subtract(const Duration(hours: 1)),
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now(),
      locale: const Locale('ko', 'KR'),
    );

    if (date != null && mounted) {
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(DateTime.now().subtract(const Duration(hours: 1))),
      );

      if (time != null) {
        setState(() {
          _missingDateTime = DateTime(
            date.year,
            date.month,
            date.day,
            time.hour,
            time.minute,
          );
        });
      }
    }
  }

  void _onPhotoSelected(File? photo, String? base64) {
    setState(() {
      _selectedPhoto = photo;
      _photoBase64 = base64;
    });
  }

  Future<void> _submitReport() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final report = MissingReport(
        name: _nameController.text.trim(),
        age: _ageController.text.isNotEmpty ? int.tryParse(_ageController.text) : null,
        gender: _selectedGender,
        missingLocation: _missingLocationController.text.trim(),
        missingDateTime: _missingDateTime!.toIso8601String(),
        description: _descriptionController.text.trim(),
        reporterName: _reporterNameController.text.trim(),
        reporterPhone: _reporterPhoneController.text.trim(),
        reporterRelation: _selectedRelation!,
        photoBase64: _photoBase64,
        additionalInfo: _additionalInfoController.text.trim().isNotEmpty 
            ? _additionalInfoController.text.trim() 
            : null,
      );

      final result = await ApiService.submitMissingReport(report);
      
      if (mounted) {
        Navigator.pushReplacementNamed(
          context,
          '/confirmation',
          arguments: {
            'reportId': result['report_id'],
            'message': result['message'],
          },
        );
      }
    } on ApiException catch (e) {
      _showSnackBar(e.message, isError: true);
    } catch (e) {
      _showSnackBar('알 수 없는 오류가 발생했습니다', isError: true);
    } finally {
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? const Color(0xFFEF4444) : const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('실종자 신고'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(8),
          child: LinearProgressIndicator(
            value: (_currentPage + 1) / 3,
            backgroundColor: Colors.white.withOpacity(0.3),
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        ),
      ),
      body: Form(
        key: _formKey,
        child: PageView(
          controller: _pageController,
          onPageChanged: (page) {
            setState(() {
              _currentPage = page;
            });
          },
          children: [
            _buildMissingPersonInfoPage(),
            _buildReporterInfoPage(),
            _buildPhotoAndReviewPage(),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNavigation(),
    );
  }

  Widget _buildMissingPersonInfoPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '실종자 정보',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1F2937),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '실종자의 기본 정보를 입력해주세요',
            style: TextStyle(
              fontSize: 16,
              color: Color(0xFF6B7280),
            ),
          ),
          const SizedBox(height: 24),

          CustomTextField(
            controller: _nameController,
            label: '실종자 이름*',
            hint: '실종자의 이름을 입력하세요',
            maxLength: 50,
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: CustomTextField(
                  controller: _ageController,
                  label: '나이',
                  hint: '만 나이',
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(3),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _selectedGender,
                  decoration: const InputDecoration(
                    labelText: '성별',
                  ),
                  items: _genderOptions.map((gender) {
                    return DropdownMenuItem(
                      value: gender,
                      child: Text(gender),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedGender = value;
                    });
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          CustomTextField(
            controller: _missingLocationController,
            label: '실종 장소*',
            hint: '실종된 장소를 구체적으로 입력하세요',
            maxLines: 2,
          ),
          const SizedBox(height: 16),

          InkWell(
            onTap: _selectDateTime,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFD1D5DB)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.access_time, color: Color(0xFF6B7280)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '실종 일시*',
                          style: TextStyle(
                            fontSize: 14,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _missingDateTime != null
                              ? DateFormat('yyyy년 MM월 dd일 HH:mm').format(_missingDateTime!)
                              : '실종 일시를 선택하세요',
                          style: TextStyle(
                            fontSize: 16,
                            color: _missingDateTime != null
                                ? const Color(0xFF1F2937)
                                : const Color(0xFF9CA3AF),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          CustomTextField(
            controller: _descriptionController,
            label: '실종 상황 설명*',
            hint: '실종 당시 상황, 특징, 착용 의복 등을 자세히 설명해주세요',
            maxLines: 4,
            maxLength: 500,
          ),
          const SizedBox(height: 16),

          CustomTextField(
            controller: _additionalInfoController,
            label: '추가 정보',
            hint: '기타 특이사항이나 도움이 될 수 있는 정보를 입력하세요',
            maxLines: 3,
            maxLength: 300,
          ),
        ],
      ),
    );
  }

  Widget _buildReporterInfoPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '신고자 정보',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1F2937),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '신고자의 정보를 입력해주세요',
            style: TextStyle(
              fontSize: 16,
              color: Color(0xFF6B7280),
            ),
          ),
          const SizedBox(height: 24),

          CustomTextField(
            controller: _reporterNameController,
            label: '신고자 이름*',
            hint: '신고자의 이름을 입력하세요',
            maxLength: 50,
          ),
          const SizedBox(height: 16),

          CustomTextField(
            controller: _reporterPhoneController,
            label: '연락처*',
            hint: '010-0000-0000',
            keyboardType: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9-]')),
              LengthLimitingTextInputFormatter(13),
            ],
          ),
          const SizedBox(height: 16),

          DropdownButtonFormField<String>(
            value: _selectedRelation,
            decoration: const InputDecoration(
              labelText: '실종자와의 관계*',
            ),
            items: _relationOptions.map((relation) {
              return DropdownMenuItem(
                value: relation,
                child: Text(relation),
              );
            }).toList(),
            onChanged: (value) {
              setState(() {
                _selectedRelation = value;
              });
            },
            validator: (value) {
              if (value == null || value.isEmpty) {
                return '실종자와의 관계를 선택해주세요';
              }
              return null;
            },
          ),
          const SizedBox(height: 24),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.3)),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.warning_amber,
                      color: Color(0xFFF59E0B),
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Text(
                      '개인정보 수집 및 이용 안내',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFF59E0B),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Text(
                  '입력하신 개인정보는 실종자 수색 목적으로만 사용되며, '
                  '수색이 완료된 후 안전하게 삭제됩니다.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFFF59E0B),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoAndReviewPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '사진 등록 및 확인',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1F2937),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '실종자의 사진을 등록하고 입력한 정보를 확인해주세요',
            style: TextStyle(
              fontSize: 16,
              color: Color(0xFF6B7280),
            ),
          ),
          const SizedBox(height: 24),

          PhotoSelectorWidget(
            onPhotoSelected: _onPhotoSelected,
            selectedPhoto: _selectedPhoto,
          ),
          const SizedBox(height: 24),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '입력 정보 확인',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1F2937),
                  ),
                ),
                const SizedBox(height: 16),
                _buildInfoRow('실종자 이름', _nameController.text),
                if (_ageController.text.isNotEmpty)
                  _buildInfoRow('나이', '${_ageController.text}세'),
                if (_selectedGender != null)
                  _buildInfoRow('성별', _selectedGender!),
                _buildInfoRow('실종 장소', _missingLocationController.text),
                if (_missingDateTime != null)
                  _buildInfoRow(
                    '실종 일시',
                    DateFormat('yyyy년 MM월 dd일 HH:mm').format(_missingDateTime!),
                  ),
                _buildInfoRow('신고자', _reporterNameController.text),
                _buildInfoRow('연락처', _reporterPhoneController.text),
                if (_selectedRelation != null)
                  _buildInfoRow('관계', _selectedRelation!),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
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
              value.isNotEmpty ? value : '입력되지 않음',
              style: TextStyle(
                fontSize: 14,
                color: value.isNotEmpty ? const Color(0xFF1F2937) : const Color(0xFF9CA3AF),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNavigation() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Color(0xFFE2E8F0)),
        ),
      ),
      child: SafeArea(
        child: Row(
          children: [
            if (_currentPage > 0)
              Expanded(
                child: OutlinedButton(
                  onPressed: _previousPage,
                  child: const Text('이전'),
                ),
              ),
            if (_currentPage > 0) const SizedBox(width: 16),
            Expanded(
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _nextPage,
                child: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : Text(_currentPage == 2 ? '신고 제출' : '다음'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}