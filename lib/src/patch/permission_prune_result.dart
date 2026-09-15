class PermissionPruneResult {
  const PermissionPruneResult({
    required this.content,
    required this.changed,
    required this.removed,
  });

  final String content;
  final bool changed;
  final List<String> removed;
}

/// Matches a whole `flupo:managed` block, including its leading indent (so
/// the block can be rebuilt with the same indent, or dropped entirely).
final RegExp managedBlockPattern = RegExp(
  r'^([ \t]*)<!-- flupo:managed:start -->\n([\s\S]*?)^[ \t]*<!-- flupo:managed:end -->\n?',
  multiLine: true,
);
