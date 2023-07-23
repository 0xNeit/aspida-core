library;

abi ACP {
    #[storage(read, write)]
    fn initialize(owner: Address);

    #[storage(read)]
    fn name() -> str[19];

    #[storage(read)]
    fn symbol() -> str[3];

    #[storage(read)]
    fn decimals() -> u8;

    #[storage(read)]
    fn total_supply() -> u64;

    #[storage(read)]
    fn balance_of(account: Identity) -> u64;

    #[storage(read, write)]
    fn transfer(amount: u64, address: Identity) -> bool;

    #[storage(read, write)]
    fn mint(account: Identity, amount: u64, is_refundable: bool);

    #[storage(read, write)]
    fn burn_multiple(accounts: Vec<Identity>, amounts: Vec<u64>);

    #[storage(read, write)]
    fn burn(account: Identity, amount: u64);

    #[storage(read, write)]
    fn withdraw(account: Identity, amount: u64);

    #[storage(read)]
    fn min_acp_required(account: Address) -> u64;
    
    #[storage(read)]
    fn is_acp_mover(account: Identity) -> bool;

    #[storage(read)]
    fn acp_mover_length() -> u64;

    #[storage(read)]
    fn acp_mover_list(index: u64) -> Identity;

    #[storage(read)]
    fn is_acp_retainer(account: ContractId) -> bool;

    #[storage(read)]
    fn acp_retainer_length() -> u64;

    #[storage(read)]
    fn acp_retainer_list(index: u64) -> ContractId;

    #[storage(read)]
    fn balance_of_non_refundable(account: Identity) -> u64;

    #[storage(read, write)]
    fn set_acp_mover_statuses(acp_movers: Vec<Identity>, statuses: Vec<bool>);

    #[storage(read, write)]
    fn set_acp_retainer_statuses(acp_retainers: Vec<ContractId>, statuses: Vec<bool>);
}