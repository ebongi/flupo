class PermissionPatchResult {
  const PermissionPatchResult({
    required this.content,
    required this.changed,
    required this.added,
  });

  final String content;
  final bool changed;
  final List<String> added;
}
