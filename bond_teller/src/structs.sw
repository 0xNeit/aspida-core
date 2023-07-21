library;

pub struct Bond {
    payout_amount: u64,                  // amount of pida to be paid in total on the bond
    payout_already_claimed: u64,         // amount of pida that has already been claimed on the bond
    principal_paid: u64,                 // amount of principal paid for this bond
    vesting_start: u64,                  // timestamp at which bond was minted
    local_vesting_term: u64              // vesting term for this bond
}

pub struct BondMeta {
    name: str[17],
    symbol: str[3],
}

impl BondMeta {
    pub fn new() -> Self {
        Self {
            name: "Aspida Bond Token",
            symbol: "ABT",
        }
    }
}