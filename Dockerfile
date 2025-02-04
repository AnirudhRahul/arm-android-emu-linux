FROM ubuntu:22.04
# Environment setup 
ENV DEBIAN_FRONTEND=noninteractive
ENV ANDROID_HOME=/opt/android-sdk
ENV ANDROID_SDK_ROOT=$ANDROID_HOME
ENV ADB_VENDOR_KEYS=/root/.android
ENV USE_EMULATOR_X86=0

# Install core dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
   openjdk-17-jdk \
   wget \
   unzip \
   python3 \
   python3-pip \
   qemu-system-arm \
   qemu-utils \
   libgl1 \
   libgl1-mesa-dri \
   libglx-mesa0 \
   mesa-common-dev \
   libx11-dev \
   libxcb-util-dev \
   libgl1-mesa-glx \
   curl \
   git \
   build-essential \
   android-tools-adb \
   android-tools-fastboot \
&& rm -rf /var/lib/apt/lists/*

# Set Java home
ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk-arm64

# Copy Android SDK (excluding system-images)
COPY android-sdk/cmdline-tools ${ANDROID_HOME}/cmdline-tools
COPY android-sdk/emulator ${ANDROID_HOME}/emulator
COPY android-sdk/licenses ${ANDROID_HOME}/licenses
COPY android-sdk/platform-tools ${ANDROID_HOME}/platform-tools
COPY android-sdk/platforms ${ANDROID_HOME}/platforms

# Set permissions
RUN echo "Setting permissions for Android tools" && \
   chmod +x ${ANDROID_HOME}/cmdline-tools/tools/bin/* && \
   chmod +x ${ANDROID_HOME}/emulator/*

# Set correct PATH for Android tools
ENV PATH=${ANDROID_HOME}/cmdline-tools/tools/bin:${ANDROID_HOME}/emulator:${JAVA_HOME}/bin:${PATH}

# Accept licenses and install system image
RUN yes | sdkmanager --licenses && \
   sdkmanager "system-images;android-30;aosp_atd;arm64-v8a"

# Create AVD with snapshot disabled
RUN yes | avdmanager create avd \
    -n arm64_api_30 \
    -k "system-images;android-30;aosp_atd;arm64-v8a" \
    --device "pixel" \
    --force && \
    echo "snapshot.present=false" >> /root/.android/avd/arm64_api_30.avd/config.ini

# Configure advanced features
RUN mkdir -p /root/.android && \
   echo "Vulkan = off" >> /root/.android/advancedFeatures.ini && \
   echo "GLDirectMem = off" >> /root/.android/advancedFeatures.ini

# Add OpenCalc download earlier in the Dockerfile
RUN wget https://github.com/Darkempire78/OpenCalc/releases/download/v3.1.4/OpenCalc.v3.1.4.apk -O /root/OpenCalc.apk

# Add start script
RUN cat <<'EOF' > /root/start-emulator.sh
#!/usr/bin/env bash
set -e
# Clean up any previous lock files
rm -f /root/.android/avd/arm64_api_30.avd/*.lock

# Configure environment for headless ARM emulator
export ANDROID_EMU_HEADLESS=1
export ANDROID_EMU_DISABLE_VULKAN=1
export ANDROID_OPENGLES_ANGLE=1
export ANDROID_EMU_DEBUG=1
export ANDROID_OPENGLES_ANGLE_DEBUG=1
export LIBGL_DEBUG=verbose
export LIBGL_ALWAYS_SOFTWARE=1
export SWIFTSHADER_USE_CPU=1
export ANDROID_EMU_DISABLE_GPU=1
# Start ADB
/usr/bin/adb start-server
# Launch the emulator with explicit snapshot control
${ANDROID_HOME}/emulator/emulator @arm64_api_30 \
 -no-snapshot \
 -no-snapshot-save \
 -no-snapshot-load \
 -wipe-data \
 -no-window \
 -no-audio \
 -ports 5554,5555 \
 -skip-adb-auth \
 -no-boot-anim \
 -gpu swiftshader_indirect \
 -memory ${EMULATOR_MEMORY} \
 -cores ${EMULATOR_CORES} \
 -accel on \
 -qemu -cpu host -machine virt,gic-version=2 &
# Wait for device and boot completion
echo "Waiting for emulator..."
/usr/bin/adb wait-for-device
while [ "$(/usr/bin/adb shell getprop sys.boot_completed 2>/dev/null)" != "1" ]; do
   sleep 2
done
echo "Device ready!"
/usr/bin/adb devices

# Wait for UI to be fully loaded
sleep 30

# Wake up device and unlock screen
/usr/bin/adb shell input keyevent KEYCODE_WAKEUP
/usr/bin/adb shell input keyevent KEYCODE_MENU
/usr/bin/adb shell input touchscreen swipe 500 1500 500 0

# Install OpenCalc APK
echo "Installing OpenCalc..."
/usr/bin/adb install /root/OpenCalc.apk

# Launch OpenCalc (corrected package and activity name based on manifest)
echo "Launching OpenCalc..."
/usr/bin/adb shell am start -n com.darkempire78.opencalculator/.activities.MainActivity

sleep 5  # Wait for app to open

# Take screenshot
echo "Taking screenshot..."
/usr/bin/adb shell screencap -p /sdcard/screenshot.png
/usr/bin/adb pull /sdcard/screenshot.png /output/screenshot.png

# Verify screenshot size
if [ -f "/output/screenshot.png" ]; then
   echo "Screenshot saved: $(ls -l /output/screenshot.png)"
else
   echo "Screenshot failed!"
fi

# Shutdown emulator and ADB gracefully
echo "Shutting down..."
/usr/bin/adb emu kill
/usr/bin/adb kill-server
exit 0
EOF
RUN chmod +x /root/start-emulator.sh

# Create output directory for volume mount
VOLUME ["/output"]

ENTRYPOINT ["/root/start-emulator.sh"]
