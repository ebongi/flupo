class AndroidIdentifierPatchResult {
  const AndroidIdentifierPatchResult({
    required this.content,
    required this.changed,
    this.previousIdentifier,
    this.skippedReason,
  });

  final String content;
  final bool changed;
  final String? previousIdentifier;

  /// Non-null when no `applicationId` assignment could be found at all —
  /// this is reported as a warning by the caller, not a hard failure.
  final String? skippedReason;
}

/// AndroidManifest.xml has no `package=` attribute in modern Flutter
/// scaffolds — the real Android application ID lives in
/// `android/app/build.gradle(.kts)`'s `applicationId` assignment, so that's
/// what this patches, as plain text (Gradle files aren't XML).
AndroidIdentifierPatchResult patchAndroidApplicationId(
  String gradleContent, {
  required bool isKotlinDsl,
  required String newIdentifier,
}) {
  final pattern = isKotlinDsl
      ? RegExp(r'(applicationId\s*=\s*")([^"]*)(")')
      : RegExp(r'(applicationId\s+")([^"]*)(")');

  final match = pattern.firstMatch(gradleContent);
  if (match == null) {
    return AndroidIdentifierPatchResult(
      content: gradleContent,
      changed: false,
      skippedReason: 'No applicationId assignment found.',
    );
  }

  final previousIdentifier = match.group(2);
  if (previousIdentifier == newIdentifier) {
    return AndroidIdentifierPatchResult(
      content: gradleContent,
      changed: false,
      previousIdentifier: previousIdentifier,
    );
  }

  final newContent = gradleContent.replaceAllMapped(
    pattern,
    (m) => '${m.group(1)}$newIdentifier${m.group(3)}',
  );

  return AndroidIdentifierPatchResult(
    content: newContent,
    changed: true,
    previousIdentifier: previousIdentifier,
  );
}
