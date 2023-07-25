library;

abi CoverProduct {
    #[storage(read)]
    fn min_acp_required(policy_holder: Address) -> u64;

    #[storage(read)]
    fn update_active_cover_limit(current_cover_limit: u64, new_cover_limit: u64);
}
