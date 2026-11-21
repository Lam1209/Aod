# SimpleAOD - build with:  make package
# iPhone X = A11 = arm64, so only that slice is built.
export TARGET := iphone:clang:latest:12.0
export ARCHS = arm64
export FINALPACKAGE = 1

# ROOTLESS jailbreaks (palera1n rootless, Dopamine, ...):
# uncomment the next line before building.
# export THEOS_PACKAGE_SCHEME = rootless

INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = SimpleAOD
SimpleAOD_FILES = Tweak.x
SimpleAOD_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
SimpleAOD_FRAMEWORKS = UIKit Foundation

include $(THEOS_MAKE_PATH)/tweak.mk
