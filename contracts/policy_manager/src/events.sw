library;

/// Emitted when a policy is created.
pub struct PolicyCreated {
    policy_id: u64,
}

/// Emitted when a policy is updated.
pub struct PolicyUpdated {
    policy_id: u64,
}

/// Emitted when a policy is burned.
pub struct PolicyBurned {
    policy_id: u64,
}

/// Emitted when the policy descriptor is set.
pub struct PolicyDescriptorSet {
    policy_descriptor: ContractId,
}

/// Emitted when a new product is added.
pub struct ProductAdded {
    product: ContractId,
}

/// Emitted when a new product is removed.
pub struct ProductRemoved {
    product: ContractId,
}

/// Emitted when registry is set.
pub struct RegistrySet {
    registry: ContractId
}