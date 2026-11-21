# iPhoneXAOD
Build: install Theos, `cd iPhoneXAOD && make package install THEOS_DEVICE_IP=<phone ip>`
Respring after install. Needs iOS 13-14 (checkra1n/rootful).

## Verify before trusting (private API)
The hook targets -[SBBacklightController _animateBacklightToFactor:duration:source:silently:completion:].
Check it exists on your iOS version: dump SpringBoard headers (class-dump / Theos `ios-headers`) or in Frida:
ObjC.classes.SBBacklightController.$ownMethods
If the selector differs, edit the %hook line to match.
If the phone respring-loops, boot Safe Mode or delete /Library/MobileSubstrate/DynamicLibraries/iPhoneXAOD.*
