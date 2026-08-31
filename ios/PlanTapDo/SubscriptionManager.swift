import Foundation
import StoreKit

@MainActor
final class SubscriptionManager: ObservableObject {
    enum PremiumPlan: String, CaseIterable, Identifiable {
        case monthly, annual, lifetime

        var id: String { rawValue }
        var productID: String {
            switch self {
            case .monthly: return "com.plantapdo.app.premium.monthly"
            case .annual: return "com.plantapdo.app.premium.annual"
            case .lifetime: return "com.plantapdo.app.premium.lifetime"
            }
        }
        var fallbackPrice: String {
            switch self {
            case .monthly: return "$4.99 / month"
            case .annual: return "$49.99 / year"
            case .lifetime: return "$99.99 once"
            }
        }

        var appStoreProductType: String {
            switch self {
            case .monthly, .annual: return "Auto-Renewable Subscription"
            case .lifetime: return "Non-Consumable"
            }
        }
        var title: String {
            switch self {
            case .monthly: return "Monthly"
            case .annual: return "Annual"
            case .lifetime: return "Lifetime"
            }
        }
    }

    @Published private(set) var products: [String: Product] = [:]
    @Published private(set) var hasPremium = false
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private var transactionUpdates: Task<Void, Never>?

    init() {
        transactionUpdates = observeTransactionUpdates()
        Task {
            await loadProducts()
            await refreshEntitlements()
        }
    }

    deinit {
        transactionUpdates?.cancel()
    }

    func loadProducts() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let loadedProducts = try await Product.products(for: PremiumPlan.allCases.map(\.productID))
            products = Dictionary(
                loadedProducts.map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            if products.isEmpty {
                errorMessage = "Premium purchases are temporarily unavailable. Please try again later."
            }
        } catch {
            errorMessage = "Couldn’t load the subscription. Please check your connection and try again."
        }
    }

    func displayPrice(for plan: PremiumPlan) -> String? {
        products[plan.productID]?.displayPrice
    }

    func purchase(_ plan: PremiumPlan) async {
        guard let product = products[plan.productID] else {
            await loadProducts()
            guard let product = products[plan.productID] else { return }
            await purchase(product)
            return
        }
        await purchase(product)
    }

    func restorePurchases() async {
        isLoading = true
        errorMessage = nil
        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch {
            errorMessage = "Couldn’t restore purchases. Please try again."
        }
        isLoading = false
    }

    func refreshEntitlements() async {
        var hasEntitlement = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if PremiumPlan.allCases.map(\.productID).contains(transaction.productID),
               transaction.revocationDate == nil,
               transaction.expirationDate.map({ $0 > Date() }) ?? true {
                hasEntitlement = true
            }
        }
        hasPremium = hasEntitlement
    }

    private func purchase(_ product: Product) async {
        isLoading = true
        errorMessage = nil
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification,
                      transaction.productID == product.id,
                      PremiumPlan.allCases.map(\.productID).contains(transaction.productID) else {
                    errorMessage = "We couldn’t verify the purchase. Please try again."
                    break
                }
                hasPremium = true
                await transaction.finish()
            case .pending:
                errorMessage = "Your purchase is pending approval."
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            errorMessage = "The purchase couldn’t be completed. Please try again."
        }
        isLoading = false
    }

    private func observeTransactionUpdates() -> Task<Void, Never> {
        Task { [weak self] in
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result,
                      PremiumPlan.allCases.map(\.productID).contains(transaction.productID)
                else { continue }
                await self?.refreshEntitlements()
                await transaction.finish()
            }
        }
    }
}
