library;

abi Locker {
    #[storage(write)]
    fn initialize(owner: Address, pida: ContractId);

    #[storage(read, write)]
    fn create_lock(
        recipient: Identity, 
        amount: u64, 
        end: u64
    ) -> u64;
}
