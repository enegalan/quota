import Foundation

/// The numbers the plugin host depends on.
public enum PluginHostConstants {
    /// How often a waiting call looks for its answer.
    ///
    /// Short enough that a prompt plugin is not made to wait on the poll, long
    /// enough that a few hundred calls in a refresh cycle do not turn into a spin
    /// loop. Polling rather than blocking on a read, because a blocking read on a
    /// pipe that never produces a line cannot also notice that the process died.
    public static let pollIntervalMilliseconds = 10

    /// How often a shutting-down process is checked to see whether it has gone.
    public static let terminatePollMilliseconds = 20
}
