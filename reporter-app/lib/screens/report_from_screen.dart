import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import '../services/api_service.dart';
import '../widgets/photo_selector_widget.dart';

class ReportFormScreen extends StatefulWidget {
  const ReportFormScreen({super.key});

  @override
  State<ReportFormScreen> createState() => _ReportFormScreenState();
}

class _ReportFormScreenState extends State<ReportFormScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  final int _totalPages = 4;

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _ageController = TextEditingController();
  final _missingLocationController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _reporterNameController = TextEditingController();
  final _reporterPhoneController = TextEditingController();

  String? _selectedGender;
  String? _selectedRelation;
  DateTime? _missingDateTime;
  XFile? _selectedPhoto;
  bool _isSubmitting = false;
  bool _agreeToPoliciy = false;

  final List<String> _genderOptions = ['남성', '여성'];
  final List<String> _relationOptions = [
    '본인',
    '배우자',
    '부모',
    '자녀',
    '형제자매',
    '친척',
    '지인',
    '기타'
  ];

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    _ageController.dispose();
    _missingLocationController.dispose();
    _descriptionController.dispose();
    _reporterNameController.dispose();
    _reporterPhoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFF1E40AF),
        foregroundColor: Colors.white,
        title: const Text(
          '대전시 실종자 신고',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text(
                '${_currentPage + 1}/$_totalPages',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildProgressIndicator(),
          Expanded(
            child: PageView(
              controller: _pageController,
              onPageChanged: (index) {
                setState(() {
                  _currentPage = index;
                });
              },
              children: [
                _buildBasicInfoPage(),
                _buildDetailInfoPage(),
                _buildPhotoAndReviewPage(),
                _buildSubmissionPage(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomNavigation(),
    );
  }

  Widget _buildProgressIndicator() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Column(
        children: [
          Row(
            children: List.generate(_totalPages, (index) {
              final isActive = index <= _currentPage;
              final isCompleted = index < _currentPage;
              
              return Expanded(
                child: Container(
                  height: 4,
                  margin: EdgeInsets.only(
                    right: index < _totalPages - 1 ? 4 : 0,
                  ),
                  decoration: BoxDecoration(
                    color: isCompleted
                        ? const Color(0xFF10B981)
                        : isActive
                            ? const Color(0xFF1E40AF)
                            : const Color(0xFFE5E7EB),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 8),
          Text(
            _getPageTitle(_currentPage),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF374151),
            ),
          ),
        ],
      ),
    );
  }

  String _getPageTitle(int page) {
    switch (page) {
      case 0:
        return '기본 정보 입력';
      case 1:
        return '상세 정보 입력';
      case 2:
        return '사진 등록 및 확인';
      case 3:
        return '신고 접수';
      default:
        return '';
    }
  }

  Widget _buildBasicInfoPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '실종자 기본 정보',
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
          
          _buildTextField(
            controller: _nameController,
            label: '실종자 이름',
            isRequired: true,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return '실종자 이름을 입력해주세요';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),

          _buildTextField(
            controller: _ageController,
            label: '나이',
            isRequired: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            validator: (value) {
              if (value == null || value.isEmpty) {
                return '나이를 입력해주세요';
              }
              final age = int.tryParse(value);
              if (age == null || age < 0 || age > 120) {
                return '올바른 나이를 입력해주세요';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),

          _buildDropdownField(
            label: '성별',
            value: _selectedGender,
            items: _genderOptions,
            onChanged: (value) {
              setState(() {
                _selectedGender = value;
              });
            },
            validator: (value) {
              if (value == null || value.isEmpty) {
                return '성별을 선택해주세요';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),

          _buildTextField(
            controller: _missingLocationController,
            label: '실종 장소',
            isRequired: true,
            maxLines: 2,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return '실종 장소를 입력해주세요';
              }
              return null;
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDetailInfoPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '상세 정보 및 신고자 정보',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1F2937),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '실종 상황과 신고자 정보를 입력해주세요',
            style: TextStyle(
              fontSize: 16,
              color: Color(0xFF6B7280),
            ),
          ),
          const SizedBox(height: 24),

          _buildDateTimeField(),
          const SizedBox(height: 16),

          _buildTextField(
            controller: _descriptionController,
            label: '상세 설명',
            isRequired: false,
            maxLines: 4,
            hintText: '실종 당시 착용한 옷, 특징, 상황 등을 자세히 설명해주세요',
          ),
          const SizedBox(height: 24),

          const Text(
            '신고자 정보',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1F2937),
            ),
          ),
          const SizedBox(height: 16),

          _buildTextField(
            controller: _reporterNameController,
            label: '신고자 이름',
            isRequired: true,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return '신고자 이름을 입력해주세요';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),

          _buildTextField(
            controller: _reporterPhoneController,
            label: '연락처',
            isRequired: true,
            keyboardType: TextInputType.phone,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return '연락처를 입력해주세요';
              }
              if (!RegExp(r'^[0-9-]+$').hasMatch(value)) {
                return '올바른 전화번호 형식으로 입력해주세요';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),

          _buildDropdownField(
            label: '실종자와의 관계',
            value: _selectedRelation,
            items: _relationOptions,
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
          const SizedBox(height: 24),

          _buildPrivacyPolicySection(),
        ],
      ),
    );
  }

  Widget _buildSubmissionPage() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const Spacer(),
          Icon(
            _isSubmitting ? Icons.upload : Icons.check_circle_outline,
            size: 80,
            color: _isSubmitting ? const Color(0xFF1E40AF) : const Color(0xFF10B981),
          ),
          const SizedBox(height: 24),
          Text(
            _isSubmitting ? '신고를 접수하는 중...' : '신고 준비 완료',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1F2937),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _isSubmitting 
                ? '잠시만 기다려주세요. 서버에 신고 내용을 전송하고 있습니다.'
                : '모든 정보가 올바르게 입력되었습니다.\n아래 버튼을 눌러 신고를 접수해주세요.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              color: Color(0xFF6B7280),
              height: 1.5,
            ),
          ),
          if (_isSubmitting) ...[
            const SizedBox(height: 24),
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF1E40AF)),
            ),
          ],
          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    bool isRequired = false,
    String? hintText,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          text: TextSpan(
            text: label,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF374151),
            ),
            children: [
              if (isRequired)
                const TextSpan(
                  text: ' *',
                  style: TextStyle(color: Color(0xFFEF4444)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          maxLines: maxLines,
          validator: validator,
          decoration: InputDecoration(
            hintText: hintText,
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF1E40AF), width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFEF4444)),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdownField({
    required String label,
    required String? value,
    required List<String> items,
    required Function(String?) onChanged,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          text: TextSpan(
            text: label,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF374151),
            ),
            children: const [
              TextSpan(
                text: ' *',
                style: TextStyle(color: Color(0xFFEF4444)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: value,
          onChanged: onChanged,
          validator: validator,
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF1E40AF), width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          items: items.map((String item) {
            return DropdownMenuItem<String>(
              value: item,
              child: Text(item),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildDateTimeField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '실종 일시 *',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Color(0xFF374151),
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: _selectDateTime,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: const Color(0xFFD1D5DB)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.calendar_today,
                  color: _missingDateTime != null
                      ? const Color(0xFF1E40AF)
                      : const Color(0xFF9CA3AF),
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _missingDateTime != null
                        ? DateFormat('yyyy년 MM월 dd일 HH:mm').format(_missingDateTime!)
                        : '실종 일시를 선택해주세요',
                    style: TextStyle(
                      fontSize: 16,
                      color: _missingDateTime != null
                          ? const Color(0xFF374151)
                          : const Color(0xFF9CA3AF),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
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
              style: TextStyle(
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrivacyPolicySection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
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
          const SizedBox(height: 8),
          const Text(
            '입력하신 개인정보는 실종자 수색 목적으로만 사용되며, '
            '수색이 완료된 후 안전하게 삭제됩니다.',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFFF59E0B),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Checkbox(
                value: _agreeToPoliciy,
                onChanged: (value) {
                  setState(() {
                    _agreeToPoliciy = value ?? false;
                  });
                },
                activeColor: const Color(0xFF1E40AF),
              ),
              const Expanded(
                child: Text(
                  '개인정보 수집 및 이용에 동의합니다',
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF374151),
                  ),
                ),
              ),
            ],
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
          top: BorderSide(color: Color(0xFFE5E7EB)),
        ),
      ),
      child: Row(
        children: [
          if (_currentPage > 0)
            Expanded(
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _previousPage,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF1E40AF),
                  side: const BorderSide(color: Color(0xFF1E40AF)),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  '이전',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          if (_currentPage > 0) const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _nextPage,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E40AF),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                _getNextButtonText(),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getNextButtonText() {
    if (_isSubmitting) return '처리 중...';
    if (_currentPage == _totalPages - 1) return '신고 접수';
    return '다음';
  }

  void _onPhotoSelected(XFile? photo) {
    setState(() {
      _selectedPhoto = photo;
    });
  }

  Future<void> _selectDateTime() async {
    final DateTime? date = await showDatePicker(
      context: context,
      initialDate: _missingDateTime ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
    );

    if (date != null && mounted) {
      final TimeOfDay? time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_missingDateTime ?? DateTime.now()),
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

  void _previousPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _nextPage() {
    if (_currentPage < _totalPages - 1) {
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

  bool _validateCurrentPage() {
    switch (_currentPage) {
      case 0:
        return _nameController.text.isNotEmpty &&
               _ageController.text.isNotEmpty &&
               _selectedGender != null &&
               _missingLocationController.text.isNotEmpty;
      case 1:
        return _missingDateTime != null &&
               _reporterNameController.text.isNotEmpty &&
               _reporterPhoneController.text.isNotEmpty &&
               _selectedRelation != null;
      case 2:
        return _agreeToPoliciy;
      default:
        return true;
    }
  }

  Future<void> _submitReport() async {
    if (!_validateCurrentPage() || _isSubmitting) return;

    setState(() {
      _isSubmitting = true;
    });

    try {
      final result = await ApiService.submitMissingPerson(
        name: _nameController.text,
        age: int.parse(_ageController.text),
        gender: _selectedGender!,
        missingLocation: _missingLocationController.text,
        missingDateTime: _missingDateTime!,
        reporterName: _reporterNameController.text,
        reporterPhone: _reporterPhoneController.text,
        reporterRelation: _selectedRelation!,
        description: _descriptionController.text.isEmpty ? null : _descriptionController.text,
        photo: _selectedPhoto,
      );

      if (mounted) {
        if (result['success']) {
          _showSuccessDialog(result['person_id']);
        } else {
          _showErrorDialog(result['message']);
        }
      }
    } catch (e) {
      if (mounted) {
        _showErrorDialog('신고 접수 중 오류가 발생했습니다.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  void _showSuccessDialog(String personId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        icon: const Icon(
          Icons.check_circle,
          color: Color(0xFF10B981),
          size: 48,
        ),
        title: const Text('신고 접수 완료'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '실종자 신고가 성공적으로 접수되었습니다.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '신고번호: ${personId.substring(0, 8)}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E40AF),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '관리자가 검토 후 수색 활동을 시작합니다.',
              style: TextStyle(
                fontSize: 14,
                color: Color(0xFF6B7280),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E40AF),
              foregroundColor: Colors.white,
            ),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(
          Icons.error_outline,
          color: Color(0xFFEF4444),
          size: 48,
        ),
        title: const Text('신고 접수 실패'),
        content: Text(message),
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