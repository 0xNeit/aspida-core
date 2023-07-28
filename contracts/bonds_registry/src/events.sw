library;

/// Emitted when a teller is added.
pub struct TellerAdded {
    teller: Identity,
}

/// Emitted when a teller is removed.
pub struct TellerRemoved {
    teller: Identity,
}