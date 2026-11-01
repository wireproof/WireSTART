# Viper

A personal, independent iOS Bluetooth remote for the VSM50BT SmartStart accessory. The app does not require a SmartStart account or use a cloud service. It has a dark green interface, in-app session controls and Home Screen and Lock Screen widgets that open the remote.

## Current capabilities

Lock and Unlock were physically verified by the owner in Viper 0.0.6; Trunk in 0.0.3; and Start/Stop in 0.0.6. The 0.1.0 interface and widgets require their own physical validation. Aux 1, Aux 2 and Panic are experimental and have not been physically verified. Confirmations are required for Trunk, Start/Stop and Panic. The app does not claim to know vehicle state merely because it receives an accessory acknowledgment.

Widgets open Viper; they do not send vehicle commands themselves or display live vehicle status. Disconnect closes the app's accessory session and leaves the system Bluetooth pairing in place. Connect can reopen a visible paired accessory or show Apple's Bluetooth accessory picker. Availability of a disconnected accessory in that picker depends on the accessory and iOS.

The handheld fob's Function button selects its own command levels; there is no established equivalent Bluetooth command here. Fob temperature and runtime are not currently available from observed Bluetooth responses.

## Build

Open `ios/Viper.xcodeproj` in Xcode and select an Apple development team. The main app supports iOS 16 and later; the widget extension requires iOS 17 or later. The project is reproducible from `ios/make_project.py`. Run the response parser checks with:

```sh
cd ios
swiftc ResponseFramer.swift Tests/ResponseFramerTests.swift -o /tmp/viper-tests
/tmp/viper-tests
```

The app keeps local diagnostic records of accessory events and command responses. No original SmartStart application binary, decrypted assets, device provisioning profile, or diagnostic logs are included in this repository. Viper and SmartStart are marks of their respective owners; this independent project is not affiliated with them.
