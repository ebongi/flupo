/// Comments wrapping every block flupo inserts into native project files,
/// so a future `flupo patch --prune` can find and remove only flupo-owned
/// content without ever touching anything the user wrote by hand.
const managedSentinelStart = '<!-- flupo:managed:start -->';
const managedSentinelEnd = '<!-- flupo:managed:end -->';
