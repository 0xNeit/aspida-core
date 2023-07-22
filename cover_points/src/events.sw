library;

/// Emitted when the status of an ACP mover is set.
pub struct AcpMoverStatusSet {
    acp_mover: Identity,
    status: bool,
}

/// Emitted when the status of an ACP retainer is set.
pub struct AcpRetainerStatusSet {
    acp_retainer: ContractId,
    status: bool,
}
