contract;

mod events;
mod structs;

use std::storage::*;
use std::constants::ZERO_B256;
use std::address::*;
use std::contract_id::*;
use std::auth::{AuthError, msg_sender};
use std::block::*;

use events::*;

use structs::*;

pub enum Errors {
    ZeroAddress: (),
    CannotReinitialize: (),
    NotInitialized: (),
    NotOwner: (),
    InvalidPrice: (),
    InvalidDenom: (),
    InvalidDate: (),
    InvalidHalfLife: (),
    InvalidFee: (),
}

pub enum State {
    Initialized: (),
    Uninitialized: (),
}

impl core::ops::Eq for State {
    fn eq(self, other: Self) -> bool {
        match (self, other) {
            (State::Initialized, State::Initialized) => true,
            (State::Uninitialized, State::Uninitialized) => true,
            _ => false,
        }
    }
}

abi BondTeller {
    #[storage(read, write)]
    fn initialize(
        owner: Address,
        pida: ContractId,
        xp_locker: ContractId,
        pool: ContractId,
        dao: Address,
        principal: ContractId,
        bond_registry: ContractId,
    );

    #[storage(read, write)]
    fn pause();

    #[storage(read, write)]
    fn unpause();

    #[storage(write)]
    fn set_terms(terms: Terms);

    #[storage(read, write)]
    fn set_fees(protocol_fee: u64);
}



storage {
    state: State = State::Uninitialized,
    owner: Address = Address {
        value: ZERO_B256,
    },
    // prices
    capacity: u64 = 0,                          // capacity remaining for all bonds
    next_price: u64 = 0,                        // the price of the next bond before decay
    minimum_price: u64 = 0,                     // price floor measured in principal per 1 pida
    price_adj_num: u64 = 0,                     // factor that increases price after purchase
    price_adj_denom: u64 = 0,                   // factor that increases price after purchase
    half_life: u64 = 0,                         // factor for price decay
    last_price_update: u64 = 0,                 // last timestamp price was updated
    max_payout: u64 = 0,                        // max payout in a single bond measured in principal
    protocol_fee_bps: u64 = 0,                  // portion of principal that is sent to the dao, the rest to the pool
    terms_set: bool = false,                    // have terms been set
    capacity_is_payout: bool = false,           // capacity limit is for payout vs principal
    paused: bool = false,                       // pauses deposits

    // times
    start_time: u64 = 0,                   // timestamp bonds start
    end_time: u64 = 0,                     // timestamp bonds no longer offered
    global_vesting_term: u64 = 0,          // duration in seconds (fixed-term)

    // bonds
    num_bonds: u64 = 0,                   // total number of bonds that have been created

    bonds: StorageMap<u64, Bond> = StorageMap{},        // mapping of bondID to Bond object

    // addresses and contracts
    pida: ContractId = ContractId {
        value: ZERO_B256,
    },                                          // pida native token
    xp_locker: ContractId = ContractId {
        value: ZERO_B256,
    },                                          // xpLocker staking contract
    principal: ContractId = ContractId {
        value: ZERO_B256,
    },                                          // token to accept as payment 
    underwriting_pool: ContractId = ContractId {
        value: ZERO_B256,
    },                                          // the underwriting pool to back risks
    dao: Address = Address {
        value: ZERO_B256,
    },                                          // the dao
    bond_registry: ContractId = ContractId {
        value: ZERO_B256,
    },                                          // the bond registry
}



const MAX_BPS: u64 = 10000; // 10k basis points (100%)

/**
    * @notice Sets the addresses to call out in storage.
    * Can only be called by the current Owner.
    * @param pida The PIDA token ContractId.
    * @param xp_locker The xpLocker ContractId.
    * @param pool The underwriting pool.
    * @param dao The DAO wallet.
    * @param principal The token that users deposit.
    * @param bond_registry The bond registry.
    */
#[storage(write)]
fn set_addresses(
    pida: ContractId,
    xp_locker: ContractId,
    pool: ContractId,
    dao: Address,
    principal: ContractId,
    bond_registry: ContractId
) {
    require(pida != ContractId::from(ZERO_B256), Errors::ZeroAddress);
    require(xp_locker != ContractId::from(ZERO_B256), Errors::ZeroAddress);
    require(pool != ContractId::from(ZERO_B256), Errors::ZeroAddress);
    require(dao != Address::from(ZERO_B256) , Errors::ZeroAddress);
    require(principal != ContractId::from(ZERO_B256), Errors::ZeroAddress);
    require(bond_registry != ContractId::from(ZERO_B256), Errors::ZeroAddress);
    storage.pida = pida;
    storage.xp_locker = xp_locker;
    storage.underwriting_pool = pool;
    storage.dao = dao;
    storage.principal = principal;
    storage.bond_registry = bond_registry;
}

pub fn get_msg_sender_address_or_panic() -> Address {
    let sender: Result<Identity, AuthError> = msg_sender();
    if let Identity::Address(address) = sender.unwrap() {
        address
    } else {
        revert(0);
    }
}

#[storage(read)]
fn validate_owner() {
    let sender = get_msg_sender_address_or_panic();
    require(storage.owner == sender, Errors::NotOwner);
}


impl BondTeller for Contract {
    /**
     * @notice Initializes the teller.
     * @param owner The address of the owner.
     * @param pida The PIDA token.
     * @param xp_locker The xpLocker contract.
     * @param pool The underwriting pool.
     * @param dao The DAO.
     * @param principal The token that users deposit.
     * @param bond_registry The bond depository.
    */
    #[storage(read, write)]
    fn initialize(
        owner: Address,
        pida: ContractId,
        xp_locker: ContractId,
        pool: ContractId,
        dao: Address,
        principal: ContractId,
        bond_registry: ContractId,
    ) {
        require(storage.state == State::Uninitialized, Errors::CannotReinitialize);
        set_addresses(pida, xp_locker, pool, dao, principal, bond_registry);
        storage.state = State::Initialized;
        storage.owner = owner;
    }

    /***************************************
    VIEW FUNCTIONS
    ***************************************/

    /***************************************
    GOVERNANCE FUNCTIONS
    ***************************************/

    /**
     * @notice Pauses deposits.
     * Can only be called by the current owner.
    */
    #[storage(read, write)]
    fn pause() {
        validate_owner();
        storage.paused = true;
        log (
            Paused {}
        );
    }

    /**
     * @notice Unpauses deposits.
     * Can only be called by the current owner.
    */
    #[storage(read, write)]
    fn unpause() {
        validate_owner();
        storage.paused = false;
        log(
            Unpaused {}
        );
    }

    /**
     * @notice Sets the bond terms.
     * Can only be called by the current owner.
     * @param terms The terms of the bond.
    */
    #[storage(write)]
    fn set_terms(terms: Terms) {
        require(terms.start_price > 0, Errors::InvalidPrice);
        storage.next_price = terms.start_price;
        storage.minimum_price = terms.minimum_price;
        storage.max_payout = terms.max_payout;

        require(terms.price_adj_denom != 0, Errors::InvalidDenom);
        storage.price_adj_num = terms.price_adj_num;
        storage.price_adj_denom = terms.price_adj_denom;
        storage.capacity = terms.capacity;
        storage.capacity_is_payout = terms.capacity_is_payout;

        require(terms.start_time <= terms.end_time, Errors::InvalidDate);
        storage.start_time = terms.start_time;
        storage.end_time = terms.end_time;
        storage.global_vesting_term = terms.global_vesting_term;

        require(terms.half_life > 0, Errors::InvalidHalfLife);
        storage.half_life = terms.half_life;
        storage.terms_set = true;
        storage.last_price_update = timestamp();

        log (
            TermsSet {}
        );
    }

    /**
     * @notice Sets the bond fees.
     * @param protocolFee The fraction of `principal` that will be sent to the dao measured in BPS.
    */
    #[storage(read, write)]
    fn set_fees(protocol_fee: u64) {
        validate_owner();
        require(protocol_fee <= MAX_BPS, Errors::InvalidFee);
        storage.protocol_fee_bps = protocol_fee;

        log(
            FeesSet {}
        );
    }
}
