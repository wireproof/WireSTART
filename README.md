# Viper

A personal, independent iOS Bluetooth remote for the VSM50BT SmartStart accessory. The app does not require a SmartStart account or use a cloud service. It has a dark green interface, in-app session controls and interactive Home Screen and Lock Screen widgets, plus an Apple Watch companion.

Designed around the iPhone Duo on iOS 27.2, with layouts for the cover and inside displays. The project is built using Xcode 27.1 and the iOS 27.1 SDK.

## Current capabilities

Lock and Unlock were physically verified by the owner in Viper 0.0.6; Trunk in 0.0.3; and Remote Start in 0.0.6. The owner reported that tapping Lock in the 0.2.0 widget physically locked the vehicle without opening Viper. The owner also reported that a 0.3.0 single-command widget worked; the specific command was not recorded. The 0.3.1 grouped-widget layout and other widget commands require their own physical validation. Aux 1, Aux 2 and Panic are experimental and have not been physically verified. Confirmations are required for Trunk, Remote Start and Panic. The app does not claim to know vehicle state merely because it receives an accessory acknowledgment.

Widgets attempt to send commands directly through their own accessory session without opening the app. The Viper Remote widget groups controls together. Add the configurable Viper Command widget multiple times to create separate small Lock, Unlock, Trunk, Remote Start, Panic, Aux 1 or Aux 2 controls. Trunk, Remote Start and Panic require a second tap within 20 seconds. Lock Screen widgets provide Lock and Unlock. The owner physically verified widget Lock in 0.2.0; other widget commands remain unverified and communication may be limited by iOS or an unavailable accessory session. An acknowledgment is not proof of vehicle state; the widget does not display live telemetry. Disconnect closes the app's accessory session and leaves the system Bluetooth pairing in place. Connect can reopen a visible paired accessory or show Apple's Bluetooth accessory picker. Availability of a disconnected accessory in that picker depends on the accessory and iOS.

The Apple Watch companion requests commands through its paired iPhone over Watch Connectivity; it does not connect directly to the accessory. The iPhone must be reachable and the SmartStart session available. Lock and Unlock send immediately; Trunk, Remote Start and Panic require confirmation. The Watch reports “Command sent” only after the iPhone writes the complete command to the accessory stream; that does not establish whether the vehicle acted. The owner reported that the 0.4.0 Watch app worked while Viper was on the iPhone screen, but not while it was backgrounded. The owner reported a 0.4.1 Watch command worked with Viper backgrounded; later requests were intermittent. The 0.4.3 build adds a configurable Viper session hold and requires further background and widget testing. The relay rejects requests that arrive after their short validity window.

The clock in Viper selects how long the app attempts to retain its accessory session after leaving the screen or processing a Watch request. The default releases immediately; the available choices are 5 and 30 minutes, and 1, 3, 6, or 12 hours. This is an app-session setting, not a demonstrated change to the module’s firmware timer. iOS may suspend the app or the Bluetooth link may disconnect, and holding a session could prevent widgets from opening their own session.

Incomplete accessory replies are shown as partial data after a short wait instead of indefinitely displaying “Receiving a response.” Isolated owner tests in valet mode produced `ERR` about 6–7 seconds after both Lock and Unlock; the owner reported Unlock physically operated. Normal mode produced `LOCK OK` and `UNLOCK OK`. Viper labels an exact `ERR` as “Valet Mode On?” and asks the user to check the vehicle; `ERR` is not proof of valet mode or physical vehicle state.

The handheld fob's Function button selects its own command levels; there is no established equivalent Bluetooth command here. Fob temperature and runtime are not currently available from observed Bluetooth responses.

## Build

Open `ios/Viper.xcodeproj` in Xcode and select an Apple development team. The main app supports iOS 16 and later; the widget extension requires iOS 17 or later and the Watch app requires watchOS 10 or later. The project is reproducible from `ios/make_project.py`. Run the response parser checks with:

```sh
cd ios
swiftc AccessoryReply.swift Tests/AccessoryReplyTests.swift -o /tmp/viper-reply-tests
/tmp/viper-reply-tests
swiftc ResponseFramer.swift Tests/ResponseFramerTests.swift -o /tmp/viper-tests
/tmp/viper-tests
swiftc WidgetConfirmation.swift Tests/WidgetConfirmationTests.swift -o /tmp/viper-widget-tests
/tmp/viper-widget-tests
```

The app keeps local diagnostic records of accessory events and command responses. No original SmartStart application binary, decrypted assets, device provisioning profile, or diagnostic logs are included in this repository. Viper and SmartStart are marks of their respective owners; this independent project is not affiliated with them.
