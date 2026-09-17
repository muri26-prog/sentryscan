enum VtStatus { notChecked, clean, suspicious, malicious, unknownToVt, rateLimited, error }

/// Rezultat poizvedbe VirusTotal API v3 `/files/{sha256}` za en APK hash.
class VtVerdict {
  final String sha256;
  final VtStatus status;
  final int maliciousCount;
  final int suspiciousCount;
  final int harmlessCount;
  final int undetectedCount;
  final DateTime checkedAt;
  final String? errorMessage;

  const VtVerdict({
    required this.sha256,
    required this.status,
    required this.maliciousCount,
    required this.suspiciousCount,
    required this.harmlessCount,
    required this.undetectedCount,
    required this.checkedAt,
    this.errorMessage,
  });

  factory VtVerdict.unknown(String sha256) => VtVerdict(
        sha256: sha256,
        status: VtStatus.unknownToVt,
        maliciousCount: 0,
        suspiciousCount: 0,
        harmlessCount: 0,
        undetectedCount: 0,
        checkedAt: DateTime.now(),
      );

  factory VtVerdict.error(String sha256, String message) => VtVerdict(
        sha256: sha256,
        status: VtStatus.error,
        maliciousCount: 0,
        suspiciousCount: 0,
        harmlessCount: 0,
        undetectedCount: 0,
        checkedAt: DateTime.now(),
        errorMessage: message,
      );

  Map<String, Object?> toDbMap() => {
        'sha256': sha256,
        'status': status.name,
        'maliciousCount': maliciousCount,
        'suspiciousCount': suspiciousCount,
        'harmlessCount': harmlessCount,
        'undetectedCount': undetectedCount,
        'checkedAt': checkedAt.millisecondsSinceEpoch,
        'errorMessage': errorMessage,
      };

  factory VtVerdict.fromDbMap(Map<String, Object?> map) => VtVerdict(
        sha256: map['sha256'] as String,
        status: VtStatus.values.firstWhere(
          (s) => s.name == map['status'],
          orElse: () => VtStatus.error,
        ),
        maliciousCount: map['maliciousCount'] as int? ?? 0,
        suspiciousCount: map['suspiciousCount'] as int? ?? 0,
        harmlessCount: map['harmlessCount'] as int? ?? 0,
        undetectedCount: map['undetectedCount'] as int? ?? 0,
        checkedAt: DateTime.fromMillisecondsSinceEpoch(map['checkedAt'] as int? ?? 0),
        errorMessage: map['errorMessage'] as String?,
      );
}
