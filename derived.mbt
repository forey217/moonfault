///|
pub extend FaultError with Eq::{equal, not_equal}

///|
pub extend FaultError with @debug.Debug::{to_repr}

///|
pub extend Event with Eq::{equal, not_equal}

///|
pub extend Event with @debug.Debug::{to_repr}

///|
pub extend GateKind with Eq::{equal, not_equal}

///|
pub extend GateKind with @debug.Debug::{to_repr}

///|
pub extend Gate with Eq::{equal, not_equal}

///|
pub extend Gate with @debug.Debug::{to_repr}

///|
pub extend Importance with Eq::{equal, not_equal}

///|
pub extend Importance with ToJson::{to_json}

///|
pub extend Importance with @debug.Debug::{to_repr}

///|
pub extend Analysis with Eq::{equal, not_equal}

///|
pub extend Analysis with ToJson::{to_json}

///|
pub extend Analysis with @debug.Debug::{to_repr}
