library;

abi PremiumPool {
    #[storage(read, write)]
    fn initialize(owner: Address);

    fn deposit_token(amount: u64, token: ContractId);

    fn balance(token: ContractId) -> u64;

    fn withdraw(amount: u64, token: ContractId, to: Identity);
}