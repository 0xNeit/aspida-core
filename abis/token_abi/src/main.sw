library;

abi PIDA {
    // Initialize contract
    #[storage(read, write)]
    fn initialize(config: TokenInitializeConfig, owner: Address);

    // mint tokens to self
    #[storage(read, write)]
    fn mint(amount: u64);

    // mint tokens to specified address
    #[storage(read, write)]
    fn mint_to(account: Address, amount: u64);

    // burn tokens
    #[storage(read)]
    fn burn(amount: u64);

    #[storage(read)]
    fn balance_of(account: Identity) -> u64;

    // add minter
    #[storage(read, write)]
    fn add_minter(minter: Address);

    // remove minter
    #[storage(read, write)]
    fn remove_minter(minter: Address) -> bool;

    // Transfer coins to a given address
    fn transfer(coins: u64, address: Address);

    #[storage(read)]
    fn total_supply() -> u64;

    #[storage(read)]
    fn decimals() -> u8;

    #[storage(read)]
    fn name() -> str[12];

    #[storage(read)]
    fn symbol() -> str[4];
}

pub struct TokenInitializeConfig {
    name: str[12],
    symbol: str[4],
    decimals: u8,
}