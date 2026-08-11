import Foundation
import StoreKit

@MainActor
final class SubscriptionManager: ObservableObject {
    static let monthlyProductID = "com.plantapdo.app.monthly"

    @Published private(set) var monthlyProduct: Product?
    @Published private(set) var hasActiveSubscription = false
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private var transactionUpdates: Task<Void, Never>?

    init() {
        transactionUpdates = observeTransactionUpdates()
        Task {
            await loadProduct()
            await refreshEntitlements()
        }
    }

    deinit {
        transactionUpdates?.cancel()
    }

    func loadProduct() async {
        do {
            monthlyProduct = try await Product.products(for: [Self.monthlyProductID]).first
            if monthlyProduct == nil {
                errorMessage = "The subscription is temporarily unavailable. Please try again later."
            }
        } catch {
            errorMessage = "Couldn’t load the subscription. Please check your connection and try again."
        }
    }

    func startSubscription() async {
        guard let monthlyProduct else {
            await loadProduct()
            guard let monthlyProduct else { return }
            await purchase(monthlyProduct)
            return
        }
        await purchase(monthlyProduct)
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
            if transaction.productID == Self.monthlyProductID,
               transaction.revocationDate == nil,
               transaction.expirationDate.map({ $0 > Date() }) ?? true {
                hasEntitlement = true
            }
        }
        hasActiveSubscription = hasEntitlement
    }

    private func purchase(_ product: Product) async {
        isLoading = true
        errorMessage = nil
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    errorMessage = "We couldn’t verify the purchase. Please try again."
                    break
                }
                hasActiveSubscription = true
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
                guard case .verified(let transaction) = result else { continue }
                await self?.refreshEntitlements()
                await transaction.finish()
            }
        }
    }
}
