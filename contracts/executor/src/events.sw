library;

/// Emitted when a signer is added.
pub struct ExecutorAdded {
    executor: Address,
}

/// Emitted when a signer is removed.
pub struct ExecutorRemoved {
    executor: Address,
}
