import SwiftUI
import VPhoneWSCore

@main
struct VPhoneWSApp: App {
    var body: some Scene {
        WindowGroup("vPhone Workstation") {
            RootView()
                .frame(minWidth: 940, minHeight: 640)
        }
        .windowStyle(.hiddenTitleBar)
    }
}

struct RootView: View {
    @State private var services = AppEnvironment.makeServices()

    var body: some View {
        Group {
            if let services {
                LibraryView(services: services)
            } else {
                notFound
            }
        }
        .background(Theme.bg)
    }

    private var notFound: some View {
        ZStack {
            Theme.bg
            VStack(spacing: 14) {
                Image(systemName: "terminal")
                    .font(.system(size: 40))
                    .foregroundStyle(Theme.faint)
                Text("vphone-cli not found")
                    .font(.ws(18, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text("Install vphone-cli (e.g. brew install zqxwce/tap/vphone-cli) or set its path in Preferences.")
                    .font(.ws(13))
                    .foregroundStyle(Theme.dim)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 360)
            }
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
