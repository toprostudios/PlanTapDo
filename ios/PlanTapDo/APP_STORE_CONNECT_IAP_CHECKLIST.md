# PlanTapDo in-app purchases

The app, product identifiers, StoreKit 2 purchase handling, restore handling,
and local StoreKit testing catalog are ready. App Store Connect is the source
of truth for production products; do not change an identifier after creating it.

## Status

**App Store Connect setup completed by the product owner on August 31, 2026.**
The subscription group, both products, pricing, metadata, availability, and
App Store Connect submission information are complete. Do not repeat those
setup steps or change either product ID.

## Configured production products

Use bundle ID `com.plantapdo.app` and these exact product IDs:

| Reference name | Product ID | Type | US price | Customer-facing description |
| --- | --- | --- | --- | --- |
| PlanTapDo Advanced Monthly | `com.plantapdo.app.premium.monthly` | Auto-Renewable Subscription | $4.99/month | Unlock unlimited categories in PlanTapDo. |
| PlanTapDo Advanced Annual | `com.plantapdo.app.premium.annual` | Auto-Renewable Subscription | $49.99/year | Unlock unlimited categories in PlanTapDo. |

Place the Monthly and Annual products in one subscription group named
**PlanTapDo Advanced** and rank them at the same subscription level: they grant
the same unlimited-categories entitlement, so changes between their different
durations are crossgrades.

## App Store Connect record

The completed App Store Connect record uses these live HTTPS pages:

- Privacy Policy URL: `https://toproindustry.site/plantapdo/privacy`
- Support URL: `https://toproindustry.site/plantapdo/support`
- Terms of Use URL: `https://toproindustry.site/plantapdo/terms`

The review screenshot shows the Advanced paywall. Its review note explains:
“Advanced unlocks unlimited categories and category customization; free users
can create two categories. Restore Purchases is on the paywall.”

## 1.1 build verification

The production products are already established. When testing a 1.1 build on a
physical iPhone or iPad, exercise the changed Advanced paywall, category limit,
and Restore Purchases path. This is app regression testing, not a request to
recreate or re-verify the App Store Connect product configuration.

Retain these exact live HTTPS pages in the app record:
   - Privacy Policy URL: `https://toproindustry.site/plantapdo/privacy`
   - Support URL: `https://toproindustry.site/plantapdo/support`
   - Terms of Use URL: `https://toproindustry.site/plantapdo/terms`

The current shipping app is local-only and does not send task data to a
PlanTapDo server or analytics provider. Apple processes purchase data.

The local StoreKit configuration is only for development and tests. It is not
shipped and cannot make products active in App Store Connect.
