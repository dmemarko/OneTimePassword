//
//  Generator.swift
//  OneTimePassword
//
//  Created by Matt Rubin on 7/8/14.
//  Copyright (c) 2014 Matt Rubin. All rights reserved.
//

import Foundation
import CommonCrypto

/// A `Generator` contains all of the parameters needed to generate a one-time password.
public struct Generator: Equatable {

    /// The moving factor, either timer- or counter-based.
    public let factor: Factor

    /// The secret shared between the client and server.
    public let secret: NSData

    /// The cryptographic hash function used to generate the password.
    public let algorithm: Algorithm

    /// The number of digits in the password.
    public let digits: Int

    /**
    Initializes a new password generator with the given parameters.

    - parameter factor:      The moving factor
    - parameter secret:      The shared secret
    - parameter algorithm:   The cryptographic hash function
    - parameter digits:      The number of digits in the password

    - returns: A new password generator with the given parameters.
    */
    public init?(factor: Factor, secret: NSData, algorithm: Algorithm, digits: Int) {
        guard Generator.validateFactor(factor) && Generator.validateDigits(digits) else {
            return nil
        }
        self.factor = factor
        self.secret = secret
        self.algorithm = algorithm
        self.digits = digits
    }

    // MARK: Validation

    @warn_unused_result
    internal static func validateDigits(digits: Int) -> Bool {
        // https://tools.ietf.org/html/rfc4226#section-5.3 states "Implementations MUST extract a
        // 6-digit code at a minimum and possibly 7 and 8-digit codes."
        let acceptableDigits = 6...8
        return acceptableDigits.contains(digits)
    }

    @warn_unused_result
    internal static func validateFactor(factor: Generator.Factor) -> Bool {
        switch factor {
        case .Counter:
            return true
        case .Timer(let period):
            return validatePeriod(period)
        }
    }

    @warn_unused_result
    internal static func validatePeriod(period: NSTimeInterval) -> Bool {
        // The period must be positive and non-zero to produce a valid counter value.
        return (period > 0)
    }

    @warn_unused_result
    internal static func validateTime(timeInterval: NSTimeInterval) -> Bool {
        // The time interval must be positive to produce a valid counter value.
        return (timeInterval >= 0)
    }

    // MARK: Password Generation

    /// Generates the password for the given point in time.
    /// - parameter timeInterval: The target time, as seconds since the Unix epoch.
    /// - throws: A `Generator.Error` if a valid password cannot be generated.
    /// - returns: The generated password, or throws an error if a password could not be generated.
    @warn_unused_result
    public func passwordAtTimeIntervalSince1970(timeInterval: NSTimeInterval) throws -> String {
        let counter = try Generator.counterWithFactor(factor, atTimeIntervalSince1970: timeInterval)
        let password = try generatePassword(algorithm: algorithm, digits: digits, secret: secret, counter: counter)
        return password
    }

    /// From a moving factor, calculates the counter value needed to generate the password for the
    /// target time.
    /// - parameter factor:         A generator's moving factor.
    /// - parameter timeInterval:   The target time, as seconds since the Unix epoch.
    /// - throws: A `Generator.Error` if a valid counter cannot be calculated.
    /// - returns: The counter value needed to generate the password for the target time.
    @warn_unused_result
    internal static func counterWithFactor(factor: Factor, atTimeIntervalSince1970 timeInterval: NSTimeInterval) throws -> UInt64 {
        switch factor {
        case .Counter(let counter):
            return counter
        case .Timer(let period):
            guard validateTime(timeInterval) else {
                throw Error.InvalidTime
            }
            guard validatePeriod(period) else {
                throw Error.InvalidPeriod
            }
            return UInt64(timeInterval / period)
        }
    }

    /// Given a `Generator.Algorithm`, returns the corresponding CommonCrypto hash algorithm and
    /// length.
    /// - parameter algorithm:  A generator's algorithm.
    /// - returns: A tuple of a CommonCrypto hash algorithm and the corresponding hash length.
    @warn_unused_result
    internal static func hashInfoForAlgorithm(algorithm: Algorithm) -> (algorithm: CCHmacAlgorithm, length: Int) {
        switch algorithm {
        case .SHA1:
            return (CCHmacAlgorithm(kCCHmacAlgSHA1), Int(CC_SHA1_DIGEST_LENGTH))
        case .SHA256:
            return (CCHmacAlgorithm(kCCHmacAlgSHA256), Int(CC_SHA256_DIGEST_LENGTH))
        case .SHA512:
            return (CCHmacAlgorithm(kCCHmacAlgSHA512), Int(CC_SHA512_DIGEST_LENGTH))
        }
    }

    // MARK: Update

    /// Returns a `Generator` configured to generate the *next* password, which follows the password
    /// generated by `self`.
    ///
    /// - Requires: The next generator is valid.
    @warn_unused_result
    public func successor() -> Generator {
        switch factor {
        case .Counter(let counter):
            // Update a counter-based generator by incrementing the counter. Force-unwrapping should
            // be safe here, since any valid generator should have a valid successor.
            let nextGenerator = Generator(
                factor: .Counter(counter.successor()),
                secret: secret,
                algorithm: algorithm,
                digits: digits
            )
            return nextGenerator!
        case .Timer:
            // A timer-based generator does not need to be updated.
            return self
        }
    }

    // MARK: Nested Types

    /// A moving factor with which a generator produces different one-time passwords over time.
    /// The possible values are `Counter` and `Timer`, with associated values for each.
    public enum Factor: Equatable {
        /// Indicates a HOTP, with an associated 8-byte counter value for the moving factor. After
        /// each use of the password generator, the counter should be incremented to stay in sync
        /// with the server.
        case Counter(UInt64)
        /// Indicates a TOTP, with an associated time interval for calculating the time-based moving
        /// factor. This period value remains constant, and is used as a divisor for the number of
        /// seconds since the Unix epoch.
        case Timer(period: NSTimeInterval)
    }

    /// A cryptographic hash function used to calculate the HMAC from which a password is derived.
    /// The supported algorithms are SHA-1, SHA-256, and SHA-512
    public enum Algorithm: Equatable {
        /// The SHA-1 hash function
        case SHA1
        /// The SHA-256 hash function
        case SHA256
        /// The SHA-512 hash function
        case SHA512
    }

    /// An error type enum representing the various errors a `Generator` can throw when computing a
    /// password.
    public enum Error: ErrorType {
        /// The requested time is before the epoch date.
        case InvalidTime
        /// The requested period is not a positive number of seconds
        case InvalidPeriod
        /// The number of digits is either too short to be secure, or too long to compute.
        case InvalidDigits
    }
}

/// Compares two `Generator`s for equality.
public func == (lhs: Generator, rhs: Generator) -> Bool {
    return (lhs.factor == rhs.factor)
        && (lhs.algorithm == rhs.algorithm)
        && (lhs.secret == rhs.secret)
        && (lhs.digits == rhs.digits)
}

/// Compares two `Factor`s for equality.
public func == (lhs: Generator.Factor, rhs: Generator.Factor) -> Bool {
    switch (lhs, rhs) {
    case let (.Counter(l), .Counter(r)):
        return l == r
    case let (.Timer(l), .Timer(r)):
        return l == r
    default:
        return false
    }
}
