library;

pub struct Bond {
    payout_amount: u64,                  // amount of pida to be paid in total on the bond
    payout_already_claimed: u64,         // amount of pida that has already been claimed on the bond
    principal_paid: u64,                 // amount of principal paid for this bond
    vesting_start: u64,                  // timestamp at which bond was minted
    local_vesting_term: u64              // vesting term for this bond
}

pub struct Terms {
    start_price: u64,         // The starting price, measured in `principal` for one PIDA.
    minimum_price: u64,       // The minimum price of a bond, measured in `principal` for one PIDA.
    max_payout: u64,          // The maximum PIDA that can be sold in a single bond.
    price_adj_num: u64,       // Used to calculate price increase after bond purchase.
    price_adj_denom: u64,     // Used to calculate price increase after bond purchase.
    capacity: u64,            // The amount still sellable.
    capacity_is_payout: bool,    // True if `capacity` is measured in PIDA, false if measured in `principal`.
    start_time: u64,         // The time that purchases start.
    end_time: u64,           // The time that purchases end.
    global_vesting_term: u64, // The duration that users must wait to redeem bonds.
    half_life: u64,          // Used to calculate price decay.
}

pub struct TokenMetadata {
    name: str[17],
    symbol: str[3],
}

impl TokenMetadata {
    pub fn new() -> Self {
        Self {
            name: "Aspida Bond Token",
            symbol: "ABT",
        }
    }
}