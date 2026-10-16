//
//  LogPrivacy.swift
//  Logr
//

/// How a value interpolated into a ``LogMessage`` is stored, exported and mirrored to OSLog.
///
/// Pass it as the `privacy:` argument of an interpolation:
///
/// ```swift
/// logger.info("Signed in \(email, privacy: .private(mask: .hash)) after \(attempts) tries", category: .user)
/// ```
///
/// What ``LogR`` stores depends on ``LogrConfiguration/storesPrivateValues``, on by default in `DEBUG` builds:
///
/// | Privacy | Stored, `storesPrivateValues` on | Stored, off | OSLog mirror |
/// |---|---|---|---|
/// | ``public`` | in clear | in clear | public |
/// | ``private`` | in clear | `<private>` | private |
/// | ``private(mask:)`` | in clear | `<private:3f9a1c2e>` | private |
/// | ``sensitive`` | `<sensitive>` | `<sensitive>` | private |
///
/// Exports replace private values stored in clear with `<private>` unless asked to keep them
/// (``LogRService/exportLogs(format:includingPrivateValues:)``). Literal text is always public.
public struct LogPrivacy: Sendable {
    /// How a ``LogPrivacy/private(mask:)`` value is shown when it is not stored in clear.
    public enum Mask: Sendable {
        /// A keyed hash: `<private:3f9a1c2e>`, the same for values with the same UTF-8 bytes (`"é"`
        /// precomposed and decomposed hash differently).
        ///
        /// It lets you tell values apart, and follow one across entries, without reading it. The hash is the
        /// first 4 bytes of an HMAC-SHA256 whose key is derived from Logr's encryption key, so it cannot be
        /// reversed by hashing candidate values offline. Until ``LogR`` can read that key (meanwhile
        /// ``LogRService/persistenceStatus`` is ``PersistenceStatus/waitingForProtectedData``), hashed values
        /// render as `<private>`. ``LogR`` reads the key once
        /// per launch, so a rotated key changes the hashes from the next launch. Loggers without storage share a
        /// key made at launch: their hashes differ from one launch to the next.
        case hash
    }

    enum Option {
        case auto, `public`, `private`, hashed, sensitive
    }

    let option: Option

    /// The default: public for integers, floating-point numbers and Booleans, private for everything else, as in
    /// OSLog.
    public static let auto = LogPrivacy(option: .auto)

    /// Stored, exported and mirrored in clear.
    public static let `public` = LogPrivacy(option: .public)

    /// Stored in clear only when ``LogrConfiguration/storesPrivateValues`` is `true` (the default in `DEBUG`
    /// builds), otherwise as `<private>`.
    public static let `private` = LogPrivacy(option: .private)

    /// Like ``private``, but shown as `mask` when it is not stored in clear.
    public static func `private`(mask: Mask) -> LogPrivacy {
        switch mask {
        case .hash: LogPrivacy(option: .hashed)
        }
    }

    /// Never stored in clear, even when ``LogrConfiguration/storesPrivateValues`` is `true`: shown as
    /// `<sensitive>`. The OSLog mirror logs it as private.
    public static let sensitive = LogPrivacy(option: .sensitive)

    package static let privatePlaceholder = "<private>"
    package static let sensitivePlaceholder = "<sensitive>"
}

extension LogPrivacy {
    /// `nil` when the value is public.
    func redaction(isPublicByDefault: Bool) -> LogMessage.Redaction.Kind? {
        switch option {
        case .auto: isPublicByDefault ? nil : .private
        case .public: nil
        case .private: .private
        case .hashed: .hashed
        case .sensitive: .sensitive
        }
    }
}
