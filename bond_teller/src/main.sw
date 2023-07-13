contract;

use std::storage::*;
use std::constants::ZERO_B256;
use std::address::*;
use std::contract_id::*;

pub struct Bond {
    payout_amount: u64,                  // amount of pida to be paid in total on the bond
    payout_already_claimed: u64,         // amount of pida that has already been claimed on the bond
    principal_paid: u64,                 // amount of principal paid for this bond
    vesting_start: u64,                  // timestamp at which bond was minted
    local_vesting_term: u64              // vesting term for this bond
}

abi BondTeller {
    
}

storage {
    name: str[32] = "                                ", // name of decay NFT
    symbol: str[8] = "        ",                // symbol
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

pub enum Error {
    ZeroAddress: (),
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
    require(pida != ContractId::from(ZERO_B256), Error::ZeroAddress);
    require(xp_locker != ContractId::from(ZERO_B256), Error::ZeroAddress);
    require(pool != ContractId::from(ZERO_B256), Error::ZeroAddress);
    require(dao != Address::from(ZERO_B256) , Error::ZeroAddress);
    require(principal != ContractId::from(ZERO_B256), Error::ZeroAddress);
    require(bond_registry != ContractId::from(ZERO_B256), Error::ZeroAddress);
    storage.pida.write(pida);
    storage.xp_locker.write(xp_locker);
    storage.underwriting_pool.write(pool);
    storage.dao.write(dao);
    storage.principal.write(principal);
    storage.bond_registry.write(bond_registry);
}


impl BondTeller for Contract {
    /*#[storage(read, write)]
    fn initialize(
        name: str[32],
        owner: Address,
        pida: ContractId,
        xp_locker: ContractId,
        pool: ContractId,
        dao: ContractId,
        principal: ContractId,
        bond_registry: ContractId,
    ) {
        storage.name.write(name);
        storage.pida.write(pida);
        storage.xp_locker.write(xp_locker);
        storage.pool
    }*/
}
