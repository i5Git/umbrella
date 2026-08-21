ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME = rootless
FINALPACKAGE = 1

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ZZReticaCrashFix
ZZReticaCrashFix_FILES = Tweak.m
ZZReticaCrashFix_CFLAGS = -fobjc-arc
ZZReticaCrashFix_FRAMEWORKS = UIKit

include $(THEOS_MAKE_PATH)/tweak.mk
