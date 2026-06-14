import Foundation
import Combine

final class PricingStore: ObservableObject {
    private let defaults = UserDefaults.standard
    private let key = "modelPricing"

    /// [模型名: 单价]
    @Published var pricing: [String: ModelPricing] {
        didSet { persist() }
    }

    init() {
        if let data = defaults.data(forKey: key),
           let map = try? JSONDecoder().decode([String: ModelPricing].self, from: data) {
            self.pricing = map
        } else {
            self.pricing = [:]
        }
    }

    func pricing(for model: String) -> ModelPricing {
        pricing[model] ?? ModelPricing()
    }

    func setPricing(_ p: ModelPricing, for model: String) {
        pricing[model] = p
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(pricing) {
            defaults.set(data, forKey: key)
        }
    }
}
