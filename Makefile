TARGET = iphone:11.2:8.0
ARCHS = arm64 armv7

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = CGBA4iOS

CGBA4iOS_FILES = Tweak.xm
CGBA4iOS_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
