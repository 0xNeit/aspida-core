library;

/// @notice Emitted when a bond is created.
pub struct CreateBond {
    lock_id: u64,
    principal_amount: u64,
    payout_amount: u64, 
    vesting_start: u64,
    vesting_time: u64
}

/// @notice Emitted when a bond is redeemed.
pub struct RedeemBond {
    bond_id: u64,
    recipient: Identity,
    payout_amount: u64
}

/// @notice Emitted when deposits are paused.
pub struct Paused {}

/// @notice Emitted when deposits are unpaused.
pub struct Unpaused {}

/// @notice Emitted when terms are set.
pub struct TermsSet{}

/// @notice Emitted when fees are set.
pub struct FeesSet {}

/// @notice Emitted when fees are set.
pub struct AddressesSet {}