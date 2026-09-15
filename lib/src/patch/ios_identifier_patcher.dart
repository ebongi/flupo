class IosIdentifierPatchResult {
  const IosIdentifierPatchResult({
    required this.content,
    required this.changed,
    this.previousIdentifier,
    this.sanitizedIdentifier,
    this.warning,
  });

  final String content;
  final bool changed;
  final String? previousIdentifier;
  final String? sanitizedIdentifier;
  final String? warning;
}

final RegExp _productBundleIdentifierPattern = RegExp(
  r'PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);',
);

/// `Info.plist`'s `CFBundleIdentifier` is the build variable
/// `$(PRODUCT_BUNDLE_IDENTIFIER)`, not a literal — the real iOS bundle ID
/// lives in `project.pbxproj`, a legacy NeXT-style plist (not XML, so this
/// is a targeted text/regex patch, not a parse).
///
/// Rather than assuming a `com.example.*`-style starting point, this reads
/// whichever identifier the Runner target currently has as the "before"
/// baseline and replaces exact matches of it — correct regardless of the
/// project's current identifier, and naturally idempotent on rerun (a
/// second run's baseline is simply whatever the first run just wrote).
IosIdentifierPatchResult patchPbxprojBundleIdentifier(
  String pbxprojContent,
  String rawIdentifier,
) {
  // Apple bundle identifiers disallow underscores, which Android's
  // applicationId permits (observed in the wild: flupo_go vs flupoGo).
  final sanitized = rawIdentifier.replaceAll('_', '');
  final underscoreWarning = sanitized != rawIdentifier
      ? 'iOS bundle identifiers cannot contain underscores; using '
            '"$sanitized" instead of "$rawIdentifier".'
      : null;

  final values = _productBundleIdentifierPattern
      .allMatches(pbxprojContent)
      .map((m) => m.group(1)!)
      .toSet();
  if (values.isEmpty) {
    return IosIdentifierPatchResult(
      content: pbxprojContent,
      changed: false,
      warning: 'No PRODUCT_BUNDLE_IDENTIFIER entries found in project.pbxproj.',
    );
  }

  final runnerValues = values.where((v) => !v.endsWith('.RunnerTests')).toSet();
  if (runnerValues.length != 1) {
    return IosIdentifierPatchResult(
      content: pbxprojContent,
      changed: false,
      warning:
          'Could not determine a single Runner target bundle identifier in '
          'project.pbxproj (found: ${runnerValues.join(', ')}). Skipping '
          'the iOS identifier patch — edit it manually.',
    );
  }
  final baseline = runnerValues.single;

  if (baseline == sanitized) {
    return IosIdentifierPatchResult(
      content: pbxprojContent,
      changed: false,
      previousIdentifier: baseline,
      sanitizedIdentifier: sanitized,
      warning: underscoreWarning,
    );
  }

  final newContent = pbxprojContent
      .replaceAll(
        'PRODUCT_BUNDLE_IDENTIFIER = $baseline;',
        'PRODUCT_BUNDLE_IDENTIFIER = $sanitized;',
      )
      .replaceAll(
        'PRODUCT_BUNDLE_IDENTIFIER = $baseline.RunnerTests;',
        'PRODUCT_BUNDLE_IDENTIFIER = $sanitized.RunnerTests;',
      );

  return IosIdentifierPatchResult(
    content: newContent,
    changed: true,
    previousIdentifier: baseline,
    sanitizedIdentifier: sanitized,
    warning: underscoreWarning,
  );
}
