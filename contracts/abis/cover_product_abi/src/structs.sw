library;

pub struct Hourly {
    value: u64,
}

impl core::ops::Eq for Hourly {
    fn eq(self, other: Self) -> bool {
        self.value == other.value
    }
}

pub struct Daily {
    value: u64,
}

impl core::ops::Eq for Daily {
    fn eq(self, other: Self) -> bool {
        self.value == other.value
    }
}

pub struct Weekly {
    value: u64,
}

impl core::ops::Eq for Weekly {
    fn eq(self, other: Self) -> bool {
        self.value == other.value
    }
}

impl Weekly {
    pub fn new() -> Self {
        Self {
            value: 604800,
        }
    }
}

pub struct Monthly {
    value: u64,
}

impl core::ops::Eq for Monthly {
    fn eq(self, other: Self) -> bool {
        self.value == other.value
    }
}

pub struct Annually {
    value: u64,
}

impl core::ops::Eq for Annually {
    fn eq(self, other: Self) -> bool {
        self.value == other.value
    }
}



