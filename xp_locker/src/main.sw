contract;

mod events;

use std::constants::*;
use std::block::*;
use std::auth::msg_sender;
use std::token::*;
use std::storage::*;
use std::auth::*;

use nft::{
    mint,
    tokens_minted,
};

use nft::extensions::token_metadata::*;

use events::*;

use token_abi::PIDA;
use locker_abi::Locker;

use reentrancy::*;

pub struct Lock {
    amount: u64,
    end: u64,
}

pub enum Errors {
    ZeroAddress: (),
    ExceedMaxLock: (),
}

pub struct LockMeta {
    name: str[10],
    symbol: str[6],
}

storage {
    pida: ContractId = ContractId {
        value: ZERO_B256,
    },
    owner: Address = Address {
        value: ZERO_B256,
    },
    total_num_locks: u64 = 0,
    locks: StorageMap<u64, Lock> = StorageMap {},
}

const MAX_LOCK_DURATION: u64 = 126_144_000;

/***************************************
    HELPER FUNCTIONS
***************************************/

/**
    * @notice Creates a new lock.
    * @param recipient The user that the lock will be minted to.
    * @param amount The amount of PIDA in the lock.
    * @param end The end of the lock.
    * @param xp_lock_id The ID of the new lock.
*/
#[storage(read, write)]
fn _create_lock(
    recipient: Identity, 
    amount: u64, 
    end: u64
) -> u64 {
    let new_lock = Lock {
        amount: amount,
        end: end,
    };

    require(new_lock.end <= timestamp() + MAX_LOCK_DURATION, Errors::ExceedMaxLock);
    // accounting
    mint(amount, recipient);

    let mut xp_lock_id = tokens_minted() - amount;
    let meta = LockMeta {
        name: "xPIDA Lock",
        symbol: "xpLOCK"
    };

    while xp_lock_id < tokens_minted() {
        set_token_metadata(Option::Some(meta), xp_lock_id);
        xp_lock_id += 1;
    }
    storage.locks.insert(xp_lock_id, new_lock);
    storage.total_num_locks = xp_lock_id;

    log(
        LockCreated {
            xp_lock_id: xp_lock_id,
        }
    );
    xp_lock_id
}

pub fn get_msg_sender_address_or_panic() -> Address {
    let sender: Result<Identity, AuthError> = msg_sender();
    if let Identity::Address(address) = sender.unwrap() {
        address
    } else {
        revert(0);
    }
}

impl Locker for Contract {

    #[storage(write)]
    fn initialize(owner: Address, pida: ContractId) {
        require(pida != ContractId::from(ZERO_B256), Errors::ZeroAddress);
        storage.pida = pida;
    }

    /***************************************
    MUTATOR FUNCTIONS
    ***************************************/

    /**
     * @notice Deposit PIDA to create a new lock.
     * @dev PIDA is transferred from msg_sender().
     * @dev use end=0 to initialize as unlocked.
     * @param recipient The account that will receive the lock.
     * @param amount The amount of PIDA to deposit.
     * @param end The timestamp the lock will unlock.
     * @return xp_lock_id The ID of the newly created lock.
    */
    #[storage(read, write)]
    fn create_lock(
        recipient: Identity, 
        amount: u64, 
        end: u64
    ) -> u64 {
        reentrancy_guard();
        let sender = get_msg_sender_address_or_panic();
        // pull pida
        transfer_to_address(
            amount, 
            ContractId::from(get::<b256>(storage.pida.value).unwrap()),
            sender
        );
        // accounting
        let new_lock = _create_lock(recipient, amount, end);
        new_lock
    }  
}
