class Driver {
  final String id;
  final String name;
  final String phoneNumber;
  final String? licenseNumber;
  final String status;

  Driver({
    required this.id,
    required this.name,
    required this.phoneNumber,
    this.licenseNumber,
    required this.status,
  });

  factory Driver.fromJson(Map<String, dynamic> json) {
    return Driver(
      id: json['id'],
      name: json['name'],
      phoneNumber: json['phone_number'],
      licenseNumber: json['license_number'],
      status: json['status'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'phone_number': phoneNumber,
      'license_number': licenseNumber,
      'status': status,
    };
  }
}
