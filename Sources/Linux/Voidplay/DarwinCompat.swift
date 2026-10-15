import Glibc

/// Darwin's spelling of `sigaction`'s handler union, for upstream's projectM crash handler
/// (ProjectMWrapper). glibc names the same union `__sigaction_handler.sa_handler`.
struct DarwinSigactionUnion {
    var __sa_handler: __sighandler_t?
}

extension sigaction {
    var __sigaction_u: DarwinSigactionUnion {
        get { DarwinSigactionUnion(__sa_handler: __sigaction_handler.sa_handler) }
        set { __sigaction_handler.sa_handler = newValue.__sa_handler }
    }
}
