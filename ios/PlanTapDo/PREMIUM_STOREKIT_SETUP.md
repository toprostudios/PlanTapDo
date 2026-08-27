# Premium StoreKit setup

Create these in-app purchases in App Store Connect for bundle ID `com.plantapdo.app`:

| Product ID | Type | Price |
| --- | --- | --- |
| `com.plantapdo.app.premium.monthly` | Auto-Renewable Subscription | US$4.99/month |
| `com.plantapdo.app.premium.annual` | Auto-Renewable Subscription | US$49.99/year |
| `com.plantapdo.app.premium.lifetime` | Non-Consumable | US$99.99 |

The app verifies those StoreKit entitlements locally. Premium currently unlocks unlimited category creation; free accounts are limited to two categories. Add future Premium feature checks to `SubscriptionManager.hasPremium`.
