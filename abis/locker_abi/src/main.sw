library;

pub struct Lock {
    amount: u64,
    end: u64,
}

abi Locker {
    #[storage(read, write)]
    fn initialize(owner: Address, pida: ContractId);

    #[storage(read)]
    fn exists(token_id: u64) -> bool;

    #[storage(read)]
    fn locks(xp_lock_id: u64) -> Lock;

    #[storage(read)]
    fn is_locked(xp_lock_id: u64) -> bool;

    #[storage(read)]
    fn time_left(xp_lock_id: u64) -> u64;

    #[storage(read)]
    fn staked_balance(account: Address) -> u64;

    #[storage(read)]
    fn get_xp_lock_listeners() -> Vec<ContractId>;

    #[storage(read, write)]
    fn create_lock(
        recipient: Identity, 
        amount: u64, 
        end: u64
    ) -> u64;

    #[storage(read, write)]
    fn increase_amount(xp_lock_id: u64, amount: u64);

    #[storage(read, write)]
    fn extend_lock(xp_lock_id: u64, end: u64);

    #[storage(read, write)]
    fn withdraw(xp_lock_id: u64, recipient: Identity);

    #[storage(read, write)]
    fn withdraw_in_part(xp_lock_id: u64, recipient: Identity, amount: u64);

    #[storage(read, write)]
    fn withdraw_many(xp_lock_ids: Vec<u64>, recipient: Identity);

    #[storage(read, write)]
    fn add_xp_lock_listener(listener: ContractId);

    #[storage(read, write)]
    fn remove_xp_lock_listener(listener: ContractId) -> bool;

    #[storage(read, write)]
    fn set_base_uri(base_uri: str[32]);
}
