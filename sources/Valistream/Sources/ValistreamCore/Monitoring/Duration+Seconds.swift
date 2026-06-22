//
//  Duration+Seconds.swift
//  ValistreamCore
//
//  Created by Volodymyr Akimenko on 12/06/2026.
//

public extension Duration {
    /// The duration expressed as fractional seconds, for finding context and threshold math.
    var seconds: Double {
        let components = components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
