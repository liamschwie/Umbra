TARGET := iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = MobileSMS
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Umbra

Umbra_FILES = src/Tweak.x src/UmbraStore.m
Umbra_CFLAGS = -fobjc-arc -Isrc
Umbra_FRAMEWORKS = UIKit LocalAuthentication

include $(THEOS_MAKE_PATH)/tweak.mk
