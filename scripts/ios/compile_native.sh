#!/bin/bash -e

ZIGKM_COMMON_PATH=$1
IPHONE_SDK=$2
IOS_MIN_VERSION=$3
APP_PATH=$4
LIB_PATH=$5

# Compile Objective-C code
# TODO compiling and linking the final iOS executable with Zig makes big boy Apple unhappy.
# Fails validation when uploading to TestFlight.
if [ "$IPHONE_SDK" = "iphoneos" ]; then
    target_flag="--target=aarch64-ios -mios-version-min=${IOS_MIN_VERSION}"
else
    target_flag="--target=aarch64-ios-simulator -mios-version-min=${IOS_MIN_VERSION}"
fi
xcrun -sdk $IPHONE_SDK clang++ \
    $ZIGKM_COMMON_PATH/src/app/ios/main.m $ZIGKM_COMMON_PATH/src/app/ios/AppViewController.m $ZIGKM_COMMON_PATH/src/app/ios/bindings.m \
    -Werror -Wall -Wpedantic \
    -Wno-nonnull \
    -O2 $target_flag -fno-objc-arc \
    -framework UIKit -framework Foundation -framework Metal -framework QuartzCore -framework WebKit \
    -o $APP_PATH/app -L $LIB_PATH -lapplib
echo $?
