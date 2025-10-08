class MissingPerson {
  final String id;
  final String? name;
  final int? age;
  final String? gender;
  final String? location;
  final String? description;
  final String? photoUrl;
  final String? photoBase64;
  final String priority;
  final List<String> riskFactors;
  final Map<String, dynamic> nerEntities;
  final Map<String, dynamic> extractedFeatures;
  final double? lat;
  final double? lng;
  final String? category;
  final String? createdAt;
  final String? lastSeen;
  final String? clothingDescription;
  final String? medicalCondition;
  final String? emergencyContact;

  MissingPerson({
    required this.id,
    this.name,
    this.age,
    this.gender,
    this.location,
    this.description,
    this.photoUrl,
    this.photoBase64,
    this.priority = 'MEDIUM',
    this.riskFactors = const [],
    this.nerEntities = const {},
    this.extractedFeatures = const {},
    this.lat,
    this.lng,
    this.category,
    this.createdAt,
    this.lastSeen,
    this.clothingDescription,
    this.medicalCondition,
    this.emergencyContact,
  });

  factory MissingPerson.fromJson(Map<String, dynamic> json) {
    return MissingPerson(
      id: json['id'] ?? '',
      name: json['name'],
      age: json['age'],
      gender: json['gender'],
      location: json['location'],
      description: json['description'],
      photoUrl: json['photo_url'],
      photoBase64: json['photo_base64'],
      priority: json['priority'] ?? 'MEDIUM',
      riskFactors: json['risk_factors'] != null 
          ? List<String>.from(json['risk_factors'])
          : [],
      nerEntities: json['ner_entities'] ?? {},
      extractedFeatures: json['extracted_features'] ?? {},
      lat: json['lat']?.toDouble(),
      lng: json['lng']?.toDouble(),
      category: json['category'],
      createdAt: json['created_at'],
      lastSeen: json['last_seen'],
      clothingDescription: json['clothing_description'],
      medicalCondition: json['medical_condition'],
      emergencyContact: json['emergency_contact'],
    );
  }

  String getPriorityText() {
    switch (priority) {
      case 'HIGH':
        return '긴급';
      case 'MEDIUM':
        return '보통';
      case 'LOW':
        return '낮음';
      default:
        return '보통';
    }
  }

  String getCategoryText() {
    return category ?? '미분류';
  }
}