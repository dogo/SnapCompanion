import Foundation
import NetworkExtension

// Entry point for the NetworkExtension system extension. The provider class is
// resolved from Info.plist (NEProviderClasses).
autoreleasepool {
    NEProvider.startSystemExtensionMode()
}

dispatchMain()
