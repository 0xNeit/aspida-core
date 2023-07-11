contract;

use std::address::Address;
use std::constants::ZERO_B256;
use std::token::mint_to_address;
use std::bytes::Bytes;

configurable {
    DECIMALS: u8 = 9,
    NAME: str[12] =  "Aspida Token",
    SYMBOL: str[4] =  "PIDA",
    OWNER: Address = Address::from(ZERO_B256),
    MINT_AMOUNT: u64 = 0, 
}

storage {
    total_supply: u64 = 0u64,
}

abi PIDA {
    #[storage(read)]
    fn total_supply() -> u64;
    fn decimals() -> u8;
    fn name() -> str[12];
    fn symbol() -> str[4];
    
    #[storage(read, write)]
    fn _mint(amount: u64, recipient: Address);
}

impl PIDA for Contract {
    #[storage(read)]
    fn total_supply() -> u64 {
        storage.total_supply.read()
    }
    fn decimals() -> u8 {
        DECIMALS
    }
    fn name() -> str[12] {
        NAME
    }
    fn symbol() -> str[4] {
        SYMBOL
    }

    #[storage(read, write)]
    fn _mint(amount: u64, recipient: Address){
        assert(msg_sender().unwrap() == Identity::Address(OWNER));
        storage.total_supply.write(storage.total_supply.try_read().unwrap_or(0) + 1);
        mint_to_address(amount, recipient);
    }
}
