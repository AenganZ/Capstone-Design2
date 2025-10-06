class MissingReport {
  final String name;
  final int? age;
  final String? gender;
  final String missingLocation;
  final String missingDateTime;
  final String description;
  final String reporterName;
  final String reporterPhone;
  final String reporterRelation;
  final String? photoBase64;
  final String? additionalInfo;

  const MissingReport({
    required this.name,
    this.age,
    this.gender,
    required this.missingLocation,
    required this.missingDateTime,
    required this.description,
    required this.reporterName,
    required this.reporterPhone,
    required this.reporterRelation,
    this.photoBase64,
    this.additionalInfo,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'age': age,
      'gender': gender,
      'missing_location': missingLocation,
      'missing_datetime': missingDateTime,
      'description': description,
      'reporter_name': reporterName,
      'reporter_phone': reporterPhone,
      'reporter_relation': reporterRelation,
      'photo_base64': photoBase64,
      'additional_info': additionalInfo,
    };
  }

  factory MissingReport.fromJson(Map<String, dynamic> json) {
    return MissingReport(
      name: json['name'] ?? '',
      age: json['age'],
      gender: json['gender'],
      missingLocation: json['missing_location'] ?? '',
      missingDateTime: json['missing_datetime'] ?? '',
      description: json['description'] ?? '',
      reporterName: json['reporter_name'] ?? '',
      reporterPhone: json['reporter_phone'] ?? '',
      reporterRelation: json['reporter_relation'] ?? '',
      photoBase64: json['photo_base64'],
      additionalInfo: json['additional_info'],
    );
  }

  MissingReport copyWith({
    String? name,
    int? age,
    String? gender,
    String? missingLocation,
    String? missingDateTime,
    String? description,
    String? reporterName,
    String? reporterPhone,
    String? reporterRelation,
    String? photoBase64,
    String? additionalInfo,
  }) {
    return MissingReport(
      name: name ?? this.name,
      age: age ?? this.age,
      gender: gender ?? this.gender,
      missingLocation: missingLocation ?? this.missingLocation,
      missingDateTime: missingDateTime ?? this.missingDateTime,
      description: description ?? this.description,
      reporterName: reporterName ?? this.reporterName,
      reporterPhone: reporterPhone ?? this.reporterPhone,
      reporterRelation: reporterRelation ?? this.reporterRelation,
      photoBase64: photoBase64 ?? this.photoBase64,
      additionalInfo: additionalInfo ?? this.additionalInfo,
    );
  }
}

class ReportStatus {
  final int reportId;
  final String status;
  final String submittedAt;
  final String? reviewedAt;
  final String? reviewerNotes;
  final String? createdPersonId;

  const ReportStatus({
    required this.reportId,
    required this.status,
    required this.submittedAt,
    this.reviewedAt,
    this.reviewerNotes,
    this.createdPersonId,
  });

  factory ReportStatus.fromJson(Map<String, dynamic> json) {
    return ReportStatus(
      reportId: json['report_id'] ?? 0,
      status: json['status'] ?? '',
      submittedAt: json['submitted_at'] ?? '',
      reviewedAt: json['reviewed_at'],
      reviewerNotes: json['reviewer_notes'],
      createdPersonId: json['created_person_id'],
    );
  }

  bool get isPending => status == 'PENDING';
  bool get isApproved => status == 'APPROVED';
  bool get isRejected => status == 'REJECTED';

  String get statusText {
    switch (status) {
      case 'PENDING':
        return '검토 대기 중';
      case 'APPROVED':
        return '승인됨';
      case 'REJECTED':
        return '거부됨';
      default:
        return '알 수 없음';
    }
  }
}