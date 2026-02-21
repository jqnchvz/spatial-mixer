//
//  SpatialAudioEngineError.swift
//  SpatialMixer
//
//  Created by Joaquín Chávez on 15-02-26.
//

import Foundation

/// Errors that can occur during spatial audio engine operations
enum SpatialAudioEngineError: Error, LocalizedError {
    case engineStartFailed(underlying: Error?)
    case sourceAlreadyExists(processID: pid_t)
    case sourceNotFound(processID: pid_t)
    case formatConversionFailed(from: String, to: String)
    case invalidFormat(reason: String)

    var errorDescription: String? {
        switch self {
        case .engineStartFailed(let underlying):
            if let error = underlying {
                return "Failed to start audio engine: \(error.localizedDescription)"
            }
            return "Failed to start audio engine"
        case .sourceAlreadyExists(let processID):
            return "Audio source already exists for process \(processID)"
        case .sourceNotFound(let processID):
            return "Audio source not found for process \(processID)"
        case .formatConversionFailed(let from, let to):
            return "Failed to convert audio format from \(from) to \(to)"
        case .invalidFormat(let reason):
            return "Invalid audio format: \(reason)"
        }
    }
}
