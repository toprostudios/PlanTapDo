import Foundation
import StoreKit

@MainActor
final class SubscriptionManager: ObservableObject {
    enum AdvancedPlan: String, CaseIterable, Identifiable {
        case monthly, annual

        var id: String { rawValue }
        var productID: String {
            switch self {
            case .monthly: return "com.plantapdo.app.premium.monthly"
            case .annual: return "com.plantapdo.app.premium.annual"
            }
        }
        var fallbackPrice: String {
            switch self {
            case .monthly: return "$4.99"
            case .annual: return "$49.99"
            }
        }

        var billingDescription: String {
            switch self {
            case .monthly: return "per month, auto-renewing"
            case .annual: return "per year, auto-renewing"
            }
        }
        var title: String {
            switch self {
            case .monthly: return "Monthly"
            case .annual: return "Annual"
            }
        }
    }

    @Published private(set) var products: [String: Product] = [:]
    @Published private(set) var hasAdvanced = false
    @Published private(set) var activePlan: AdvancedPlan?
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
            let loadedProducts = try await Product.products(for: AdvancedPlan.allCases.map(\.productID))
            products = Dictionary(
                loadedProducts.map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            if products.isEmpty {
                errorMessage = "Advanced purchases are temporarily unavailable. Please try again later."
            }
        } catch {
            errorMessage = "Couldn’t load the subscription. Please check your connection and try again."
        }
    }

    func displayPrice(for plan: AdvancedPlan) -> String {
        products[plan.productID]?.displayPrice ?? plan.fallbackPrice
    }

    func isAvailable(for plan: AdvancedPlan) -> Bool {
        products[plan.productID] != nil
    }

    func purchase(_ plan: AdvancedPlan) async {
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
        var entitlementPlan: AdvancedPlan?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if let plan = AdvancedPlan.allCases.first(where: { $0.productID == transaction.productID }),
               transaction.revocationDate == nil,
               transaction.expirationDate.map({ $0 > Date() }) ?? true {
                entitlementPlan = plan
            }
        }
        activePlan = entitlementPlan
        hasAdvanced = entitlementPlan != nil
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
                      AdvancedPlan.allCases.map(\.productID).contains(transaction.productID) else {
                    errorMessage = "We couldn’t verify the purchase. Please try again."
                    break
                }
                hasAdvanced = true
                activePlan = AdvancedPlan.allCases.first { $0.productID == transaction.productID }
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
                      AdvancedPlan.allCases.map(\.productID).contains(transaction.productID)
                else { continue }
                await self?.refreshEntitlements()
                await transaction.finish()
            }
        }
    }
}
