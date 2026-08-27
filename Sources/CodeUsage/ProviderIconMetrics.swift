import CoreGraphics

enum ProviderIconMetrics {
    static func visualScale(for provider: ProviderKind) -> CGFloat {
        provider == .qoder ? 1.2 : 1
    }
}
