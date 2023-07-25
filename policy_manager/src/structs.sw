library;

pub struct PolicyMeta {
    name: str[13],
    symbol: str[3],
}

impl PolicyMeta {
    pub fn new() -> Self {
        Self {
            name: "Aspida Policy",
            symbol: "APT",
        }
    }
}