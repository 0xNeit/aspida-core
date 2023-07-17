library;

abi Locker {
    #[storage(read, write)]
    fn initialize(owner: Address, pida: ContractId);

    #[storage(read, write)]
    fn create_lock(
        recipient: Identity, 
        amount: u64, 
        end: u64
    ) -> u64;

    #[storage(read, write)]
    fn add_xp_lock_listener(listener: ContractId);

    #[storage(read, write)]
    fn remove_xp_lock_listener(listener: ContractId) -> bool;

    #[storage(read, write)]
    fn set_base_uri(base_uri: str[32]);
}
