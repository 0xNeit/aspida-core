library;

abi BondsRegistry {
    #[storage(read, write)]
    fn initialize(owner: Address, pida: ContractId);

    #[storage(read, write)]
    fn add_teller(teller: Identity);

    #[storage(read, write)]
    fn remove_teller(teller: Identity) -> bool;

    #[storage(read)]
    fn pull_pida(amount: u64);
}