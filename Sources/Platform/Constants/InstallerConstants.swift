/// The installer's fixed values.
public enum InstallerConstants {
    /// Where staged files live before they are moved into place.
    public static let stagingDirectoryName = ".staging"

    /// Where `tar` is. Absolute so a plugin's sanitised environment, or a
    /// different `PATH`, cannot decide which program unpacks it.
    public static let tarPath = "/usr/bin/tar"
}
