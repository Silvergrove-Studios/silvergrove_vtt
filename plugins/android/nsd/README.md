# Hexmap NSD (Android)

Service discovery through Android's `NsdManager`, so a Player finds Tables
across subnets the way the system finds speakers: the OS's mDNS daemon
hears the multicast that routers reflect; an app's own socket cannot.

Build: `gradle assembleRelease` here (JDK 17, Android SDK), then copy
`build/outputs/aar/hexmap_nsd-release.aar` to
`addons/hexmap_nsd/bin/hexmap_nsd.aar`. CI does both before exporting.
The export plugin in `addons/hexmap_nsd` adds it to Gradle-based Android
exports (`gradle_build/use_gradle_build=true` in the presets).
