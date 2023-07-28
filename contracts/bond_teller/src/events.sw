library;

/// Emitted when a bond is created.
pub struct CreateBond {
    lock_id: u64,
    principal_amount: u64,
    payout_amount: u64, 
    vesting_start: u64,
    vesting_time: u64
}

/// Emitted when a bond is redeemed.
pub struct RedeemBond {
    bond_id: u64,
    recipient: Identity,
    payout_amount: u64
}

/// Emitted when deposits are paused.
pub struct Paused {}

/// Emitted when deposits are unpaused.
pub struct Unpaused {}

/// Emitted when terms are set.
pub struct TermsSet{}

/// Emitted when fees are set.
pub struct FeesSet {}

/// Emitted when fees are set.
pub struct AddressesSet {}