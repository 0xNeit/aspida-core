library;

/// Emitted when the underwriting pool is set.
pub struct UnderwritingPoolSet {
    uwp_name: str[20],
    amount: u64,
}

/// Emitted when underwriting pool is removed.
pub struct UnderwritingPoolRemoved {
    uwp_name: str[20],
}

/// Emitted when underwriting pool updater is set.
pub struct UwpUpdaterSet {
    uwp_updater: Identity,
}

/// Emitted when underwriting pool updater is removed.
pub struct UwpUpdaterRemoved {
    uwp_updater: Identity,
}
