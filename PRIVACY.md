# Privacy Policy

**Effective date:** May 10, 2026

This privacy policy applies to the BatteryScope iOS app ("the App"), developed and distributed by Ben Wyrosdick ("we," "us," or "our"). This policy explains what data the App handles and how.

## Summary

**BatteryScope does not collect, transmit, store on remote servers, or share any personal data.** Everything the App reads stays on your iPhone or iPad. No account is required. No analytics, telemetry, advertising identifiers, or tracking of any kind are used.

## What data the App handles

The App stores the following on your device, and only on your device, in iOS's standard local app storage (SwiftData / file system / UserDefaults):

- **Battery records you save**: a display name you choose, the Bluetooth peripheral identifier reported by iOS (a per-device UUID), and an optional nominal capacity figure.
- **Group records you create**: a display name, a configuration (series or parallel), and references to the batteries you placed in the group.
- **App preferences**: settings such as whether developer tools are enabled.

Live readings from your battery management systems (voltage, current, state of charge, cell voltages, temperatures, cycle count, manufacturer info, etc.) are read over Bluetooth Low Energy in real time. They are **displayed but not persisted**, with the exception of an in-memory debug log that exists only while the App is running.

## Bluetooth

The App uses Bluetooth Low Energy solely to communicate with battery management systems (BMS) on lithium batteries that you choose to monitor. iOS will prompt you to grant Bluetooth permission the first time the App starts; you can revoke this permission at any time in **Settings → BatteryScope → Bluetooth**.

The App does not advertise itself, does not act as a peripheral, and does not transmit data over Bluetooth to anything other than the BMS devices you have explicitly added.

## Third parties

The App makes no network requests. It does not communicate with any server operated by us or by any third party. There are no third-party SDKs, advertising networks, analytics services, crash reporters, or telemetry systems integrated into the App.

If a future version introduces any such integration, this privacy policy will be updated and you will be notified through the App Store update notes before that version is released.

## Data sharing

Because the App does not collect personal data, there is nothing to share. We do not sell, rent, lease, or otherwise transfer any user information, because we do not receive any.

## Children's privacy

The App is not directed to children under 13 and does not knowingly collect any information from anyone, including children.

## Your control over data

All data stored by the App lives on your device. To remove it, delete the App or remove individual entries from within the App. Deleting the App from your device removes all associated local storage.

## Changes to this policy

If this policy changes, an updated version will replace this file and the effective date at the top will be updated. Material changes will be noted in the App's release notes.

## Contact

Questions about this policy can be sent to:

**ben.wyrosdick@gmail.com**
