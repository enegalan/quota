//  PluginKit — the contract between the app and a provider plugin.
//
//  This module must remain free of any dependency on Core or Platform,
//  and must keep importing nothing from the app at all beyond Foundation. The
//  reason is that a plugin is a separate program, from a separate package, that
//  may be written by someone who has never read this app's source.
//
//  If this module could see Core, then every type crossing the boundary
//  would be one of the core's types, and a plugin would have to be compiled
//  against a particular version of a particular app to be loadable. The host
//  would stop being able to accept a plugin written to the contract and start
//  requiring one written to its internals. It is also what keeps the dependency
//  running one way: a plugin can read the protocol, and the app can never be
// reached from a plugin.
//
//  What that costs is the duplication below, and it is duplication on purpose.
//  ProviderUsage is not Quota's usage type, ProviderErrorCode is not an error the
//  core defines, and PluginRange is not the core's notion of a version. The
//  translation happens once, in the host, at the boundary, where a provider
//  sending something nonsensical becomes a ProviderError instead of a corrupted
//  record. Prefer a second wire type to a shared one: a wire type is a promise
//  about bytes, and a shared type is a promise about a build. The Package.swift
//  target graph keeps this module free of Core and Platform.
