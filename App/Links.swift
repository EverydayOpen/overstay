import Foundation

/// The website (GitHub Pages) and the repository. tools/doctor.sh checks `website` matches site/site.json's baseURL.
/// Opened only by `AppModel` and `OverstayApp`, and only on a click (BUILD_PLAN §1: no network of our own).
enum Links {
    static let website = URL(string: "https://everydayopen.github.io/overstay")!
    static let releases = URL(string: "https://github.com/EverydayOpen/overstay/releases")!
    static let falsePositive = URL(string: "https://github.com/EverydayOpen/overstay/issues/new?template=false-positive.yml")!
}
