import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:typed_data';

class PhotoSelectorWidget extends StatefulWidget {
  final Function(XFile?) onPhotoSelected;
  final XFile? selectedPhoto;

  const PhotoSelectorWidget({
    super.key,
    required this.onPhotoSelected,
    this.selectedPhoto,
  });

  @override
  State<PhotoSelectorWidget> createState() => _PhotoSelectorWidgetState();
}

class _PhotoSelectorWidgetState extends State<PhotoSelectorWidget> {
  final ImagePicker _picker = ImagePicker();
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '실종자 사진',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Color(0xFF374151),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          '최근 사진을 등록하면 수색에 큰 도움이 됩니다',
          style: TextStyle(
            fontSize: 14,
            color: Color(0xFF6B7280),
          ),
        ),
        const SizedBox(height: 16),
        
        if (widget.selectedPhoto != null) ...[
          _buildSelectedPhoto(),
          const SizedBox(height: 16),
        ],
        
        _buildPhotoButtons(),
        
        if (_isLoading) ...[
          const SizedBox(height: 16),
          const Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF1E40AF)),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSelectedPhoto() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          children: [
            FutureBuilder<Uint8List>(
              future: widget.selectedPhoto!.readAsBytes(),
              builder: (context, snapshot) {
                if (snapshot.hasData) {
                  return Image.memory(
                    snapshot.data!,
                    width: double.infinity,
                    height: 200,
                    fit: BoxFit.cover,
                  );
                } else if (snapshot.hasError) {
                  return Container(
                    height: 200,
                    color: const Color(0xFFF3F4F6),
                    child: const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 48,
                            color: Color(0xFF6B7280),
                          ),
                          SizedBox(height: 8),
                          Text(
                            '이미지를 불러올 수 없습니다',
                            style: TextStyle(color: Color(0xFF6B7280)),
                          ),
                        ],
                      ),
                    ),
                  );
                } else {
                  return Container(
                    height: 200,
                    color: const Color(0xFFF3F4F6),
                    child: const Center(
                      child: CircularProgressIndicator(),
                    ),
                  );
                }
              },
            ),
            Positioned(
              top: 8,
              right: 8,
              child: GestureDetector(
                onTap: () {
                  widget.onPhotoSelected(null);
                },
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.close,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoButtons() {
    return Row(
      children: [
        Expanded(
          child: _buildPhotoButton(
            icon: Icons.camera_alt,
            label: '카메라로 촬영',
            onTap: () => _pickImage(ImageSource.camera),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildPhotoButton(
            icon: Icons.photo_library,
            label: '갤러리에서 선택',
            onTap: () => _pickImage(ImageSource.gallery),
          ),
        ),
      ],
    );
  }

  Widget _buildPhotoButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: _isLoading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _isLoading ? const Color(0xFFF9FAFB) : Colors.white,
          border: Border.all(
            color: _isLoading ? const Color(0xFFE5E7EB) : const Color(0xFF1E40AF),
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 32,
              color: _isLoading ? const Color(0xFF9CA3AF) : const Color(0xFF1E40AF),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: _isLoading ? const Color(0xFF9CA3AF) : const Color(0xFF1E40AF),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 400,
        maxHeight: 400,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        print('선택된 사진: ${pickedFile.name}');
        
        // 웹에서도 작동하도록 XFile의 메서드 직접 사용
        final fileSize = await pickedFile.length();
        print('파일 크기: $fileSize bytes');
        
        if (fileSize == 0) {
          print('에러: 파일이 비어있음');
          if (mounted) {
            _showErrorDialog('파일이 비어있습니다. 다른 사진을 선택해주세요.');
          }
          return;
        }
        
        if (fileSize > 10 * 1024 * 1024) {
          if (mounted) {
            _showErrorDialog('파일 크기가 너무 큽니다. 10MB 이하의 이미지를 선택해주세요.');
          }
          return;
        }

        // 파일을 읽을 수 있는지 테스트
        try {
          final bytes = await pickedFile.readAsBytes();
          if (bytes.isEmpty) {
            throw Exception('파일 데이터가 비어있습니다');
          }
          print('파일 읽기 성공: ${bytes.length} bytes');
        } catch (e) {
          print('파일 읽기 실패: $e');
          if (mounted) {
            _showErrorDialog('파일을 읽을 수 없습니다: ${e.toString()}');
          }
          return;
        }

        print('사진 선택 성공!');
        widget.onPhotoSelected(pickedFile);
      } else {
        print('사진 선택 취소됨');
      }
    } catch (e, stackTrace) {
      print('=== 사진 선택 오류 ===');
      print('오류: $e');
      print('스택 트레이스: $stackTrace');
      if (mounted) {
        _showErrorDialog('사진을 불러오는 중 오류가 발생했습니다.\n${e.toString()}');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('오류'),
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