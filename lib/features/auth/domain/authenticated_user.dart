/// Usuario autenticado tal como lo devuelve `GET auth/me`.
///
/// Única fuente de verdad para `roles`/`isPhoneVerified` en el cliente:
/// el estado de la solicitud de conductor (DRAFT/PENDING_REVIEW/...) vive
/// aparte, en `DriverApplication` (`GET drivers/me`).
class AuthenticatedUser {
  const AuthenticatedUser({
    required this.id,
    required this.phoneE164,
    required this.roles,
    required this.status,
    required this.isPhoneVerified,
  });

  final String id;
  final String phoneE164;
  final List<String> roles;

  /// Estado de la cuenta (`ACTIVE`/`PENDING`/`SUSPENDED`/`BLOCKED`),
  /// tal como lo envía Backend. Sin mapear a enum: este checkpoint
  /// solo necesita leer `roles`/`isPhoneVerified` para el routing.
  final String status;

  final bool isPhoneVerified;

  bool get isDriver => roles.contains('DRIVER');

  bool get isPassenger => roles.contains('PASSENGER');

  factory AuthenticatedUser.fromJson(Map<String, dynamic> json) {
    final rawRoles = json['roles'];

    final roles = rawRoles is List
        ? rawRoles.map((role) => role.toString()).toList()
        : <String>[];

    return AuthenticatedUser(
      id: json['id']?.toString() ?? '',
      phoneE164: json['phoneE164']?.toString() ?? '',
      roles: roles,
      status: json['status']?.toString() ?? '',
      isPhoneVerified: json['isPhoneVerified'] == true,
    );
  }
}
