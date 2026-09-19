import SwiftUI

/// Keep live view state independent of the restoration store. Previews and hosted
/// views can operate without a SwiftUI scene; real windows restore lightweight state.
private struct MoneyMapSceneRestoration<Value: Codable & Equatable>: ViewModifier {
    @Binding var value: Value
    @SceneStorage private var encoded: Data
    @State private var didRestore = false

    init(key: String, value: Binding<Value>) {
        _value = value
        _encoded = SceneStorage(wrappedValue: Data(), key)
    }

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard !didRestore else { return }
                didRestore = true
                if let restored = try? JSONDecoder().decode(Value.self, from: encoded) {
                    value = restored
                }
            }
            .onChange(of: value) { _, value in
                guard didRestore else { return }
                encoded = (try? JSONEncoder().encode(value)) ?? Data()
            }
    }
}

extension View {
    func moneyMapSceneRestoration<Value: Codable & Equatable>(key: String, value: Binding<Value>) -> some View {
        modifier(MoneyMapSceneRestoration(key: key, value: value))
    }
}
