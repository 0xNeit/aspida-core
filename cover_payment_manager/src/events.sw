library;

/// Emitted when a token is deposited.
pub struct TokenDeposited {
    token: ContractId, 
    depositor: Identity, 
    receiver: Identity, 
    amount: u64,
}

/// Emitted when a token is withdrawn.
pub struct TokenWithdrawn {
    depositor: Identity, 
    receiver: Identity, 
    amount: u64,
}

/// Emitted when registry is set.
pub struct RegistrySet {
    registry: ContractId,
}

/// Emitted when a token is set.
pub struct TokenInfoSet {
    token: ContractId, 
    accepted: bool, 
    permittable: bool, 
    refundable: bool, 
    stable: bool,
}

/// Emitted when paused is set.
pub struct PauseSet {
    paused: bool,
}

/// Emitted when product is added.
pub struct ProductAdded {
    product: ContractId,
}

/// Emitted when product is removed.
pub struct ProductRemoved {
    product: ContractId,
}