# PlanTapDo development rules

- Debug, run, and test the iOS app only on a connected physical iPhone or iPad. Do not install, create, boot, or use Xcode Simulator runtimes or devices for this project.
- Use a physical-device destination (for example, `-destination 'platform=iOS,name=<device name>'`) for Xcode test runs. For compile-only checks, use `-sdk iphoneos -destination generic/platform=iOS`.
