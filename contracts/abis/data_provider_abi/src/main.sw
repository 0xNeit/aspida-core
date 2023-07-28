library;

abi DataProvider {
    #[storage(read, write)]
    fn initialize(owner: Address);

    #[storage(read, write)]
    fn set(uwp_names: Vec<str[20]>, amounts: Vec<u64>);

    #[storage(read, write)]
    fn remove(uwp_names: Vec<str[20]>);

    #[storage(read)]
    fn max_cover() -> u64;

    #[storage(read)]
    fn balance_of(uwp_name: str[20]) -> u64;

    #[storage(read)]
    fn pool_of(index: u64) -> str[20];

    #[storage(read)]
    fn is_updater(updater: Identity) -> bool;

    #[storage(read)]
    fn updater_at(index: u64) -> Identity;

    #[storage(read)]
    fn nums_of_updater() -> u64;

    #[storage(read, write)]
    fn add_updater(updater: Identity);

    #[storage(read, write)]
    fn remove_updater(updater: Identity);
}