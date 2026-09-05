# PlanTapDo Advanced StoreKit setup

The authoritative StoreKit and App Store Connect setup guide is
[APP_STORE_CONNECT_IAP_CHECKLIST.md](APP_STORE_CONNECT_IAP_CHECKLIST.md).

The shipping app verifies StoreKit 2 entitlements locally. Advanced unlocks
unlimited category creation; free users are limited to two categories. Add any
future Advanced feature checks through `SubscriptionManager.hasAdvanced`.
