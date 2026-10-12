//
//  LiquidGlassStyle.swift
//  Loopmural
//

import SwiftUI

/// Defines visual variants for Liquid Glass background effects.
enum LiquidGlassVariant {
    case clear
    case regular
}

extension View {
    /// Adds Liquid Glass on macOS 26 or a material background on earlier versions.
    @ViewBuilder
    func liquidGlassEffect(_ variant: LiquidGlassVariant = .clear, in shape: some Shape) -> some View {
        if #available(macOS 26.0, *) {
            if variant == .regular {
                self.glassEffect(.regular, in: shape)
            } else {
                self.glassEffect(.clear, in: shape)
            }
        } else {
            if variant == .regular {
                background(.regularMaterial, in: shape)
            } else {
                background(.ultraThinMaterial, in: shape)
            }
        }
    }

    /// Uses glass buttons on macOS 26 or bordered buttons on earlier versions.
    @ViewBuilder
    func liquidGlassButtonStyle(isProminent: Bool = false, tint: Color? = nil) -> some View {
        if #available(macOS 26.0, *) {
            if isProminent {
                self
                    .buttonStyle(.glassProminent)
                    .tint(tint)
            } else {
                self
                    .buttonStyle(.glass)
                    .tint(tint)
            }
        } else {
            if isProminent {
                buttonStyle(.borderedProminent)
                    .tint(tint)
            } else {
                buttonStyle(.bordered)
                    .tint(tint)
            }
        }
    }
}
