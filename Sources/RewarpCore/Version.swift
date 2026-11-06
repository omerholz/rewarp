/// The one place the version is set. `scripts/version.sh` reads it from here, so
/// that the app bundle and the packages always agree with what the app reports.
/// Only change it when the project's owner asks for or approves a new version.
public enum RewarpVersion {
    public static let string = "0.0.1"
}
