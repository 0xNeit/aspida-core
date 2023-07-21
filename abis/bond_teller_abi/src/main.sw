library;

abi BondTeller {
    #[storage(read, write)]
    fn initialize(
        owner: Address,
        pida: ContractId,
        xp_locker: ContractId,
        pool: ContractId,
        dao: Address,
        principal: ContractId,
        bond_registry: ContractId,
    );

    #[storage(read)]
    fn bond_price() -> u64;

    #[storage(read)]
    fn calculate_amount_out(amount_in: u64, stake: bool) -> u64;

    #[storage(read)]
    fn calculate_amount_in(amount_out: u64, _stake: bool) -> u64;

    #[storage(read, write)]
    fn deposit(
        amount: u64,
        min_amount_out: u64,
        depositor: Identity,
        stake: bool
    ) -> (u64, u64);

    #[storage(read, write)]
    fn claim_payout(bond_id: u64);

    #[storage(read, write)]
    fn pause();

    #[storage(read, write)]
    fn unpause();

    #[storage(write)]
    fn set_terms(terms: Terms);

    #[storage(read, write)]
    fn set_fees(protocol_fee: u64);

    #[storage(read, write)]
    fn set_addresses(
        pida: ContractId,
        xp_locker: ContractId,
        pool: ContractId,
        dao: Address,
        principal: ContractId,
        bond_registry: ContractId
    );
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
