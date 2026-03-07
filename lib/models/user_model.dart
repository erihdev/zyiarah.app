class ZyiarahUser {
  final String uid;
  final String name;
  final String email;
  final String phone;
  final String role; // 'client' or 'driver'

  ZyiarahUser({
    required this.uid,
    required this.name,
    required this.email,
    required this.phone,
    required this.role,
  });

  factory ZyiarahUser.fromMap(String id, Map<String, dynamic> data) {
    return ZyiarahUser(
      uid: id,
      name: data['name'] ?? '',
      email: data['email'] ?? '',
      phone: data['phone'] ?? '',
      role: data['role'] ?? 'client',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'email': email,
      'phone': phone,
      'role': role,
    };
  }
}
