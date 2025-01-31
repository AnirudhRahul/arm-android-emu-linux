# -------------------------------------------------------
# ARM-based Android Emulator Docker Image
# -------------------------------------------------------

FROM --platform=linux/arm64 ubuntu:22.04

###############################################################################
# 1. Environment setup
###############################################################################
ENV DEBIAN_FRONTEND=noninteractive
ENV ANDROID_HOME=/usr/local/android-sdk-linux
ENV PATH=$PATH:$ANDROID_HOME/cmdline-tools/tools/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator
ENV ANDROID_SDK_ROOT=$ANDROID_HOME

# Core dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    openjdk-17-jdk \
    wget \
    unzip \
    qemu-system-arm \
    qemu-utils \
    ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# Set Java home
ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk-arm64
ENV PATH=$PATH:$JAVA_HOME/bin

###############################################################################
# 2. Android SDK & Emulator Setup
###############################################################################
# Clone mirrored Android SDK components
RUN git clone https://github.com/AnirudhRahul/arm-android-emu-linux /tmp/android-repo && \
    # Command line tools (original URL: https://dl.google.com/android/repository/commandlinetools-linux-8512546_latest.zip)
    mkdir -p $ANDROID_HOME/cmdline-tools/tools && \
    cp -r /tmp/android-repo/cmdline-tools/* $ANDROID_HOME/cmdline-tools/tools/ && \
    # Emulator binary (original URL: https://ci.android.com/builds/submitted/11382468/emulator-linux_aarch64/latest/sdk-repo-linux_aarch64-emulator-11382468.zip)
    cp -r /tmp/android-repo/emulator/* $ANDROID_HOME/ && \
    rm -rf /tmp/android-repo

# SDK packages
RUN { echo "y"; yes; } | sdkmanager --sdk_root=$ANDROID_HOME --licenses && \
    sdkmanager --sdk_root=$ANDROID_HOME \
    "platform-tools" \
    "platforms;android-30" \
    "system-images;android-30;aosp_atd;arm64-v8a"

# AVD configuration
RUN mkdir -p /root/.android && \
    echo "Vulkan = off" >> /root/.android/advancedFeatures.ini && \
    mkdir -p /root/.android/avd/arm64_api_30.avd

RUN avdmanager create avd \
    --force \
    --name "arm64_api_30" \
    --package "system-images;android-30;aosp_atd;arm64-v8a" \
    --abi "arm64-v8a" \
    --device "pixel"

RUN echo "hw.gpu.enabled=yes" >> /root/.android/avd/arm64_api_30.avd/config.ini && \
    echo "hw.gpu.mode=swiftshader" >> /root/.android/avd/arm64_api_30.avd/config.ini && \
    echo "hw.cpu.ncore=\${EMULATOR_CORES}" >> /root/.android/avd/arm64_api_30.avd/config.ini

###############################################################################
# 3. Startup Script
###############################################################################
RUN cat <<'EOF' > /root/start-emulator.sh
#!/usr/bin/env bash
set -e

adb kill-server || true
adb start-server

export ANDROID_EMU_HEADLESS=1
export ANDROID_EMU_DISABLE_VULKAN=1

echo "hw.cpu.ncore=$EMULATOR_CORES" >> /root/.android/avd/arm64_api_30.avd/config.ini

emulator -avd arm64_api_30 \
  -no-window \
  -no-audio \
  -ports 5554,5555 \
  -skip-adb-auth \
  -no-boot-anim \
  -gpu swiftshader \
  -accel on \
  -memory ${EMULATOR_MEMORY} \
  -cores ${EMULATOR_CORES} \
  -wipe-data \
  -qemu -cpu host -machine virt,gic-version=2 &

while [ -z "$(adb devices | grep -v List)" ]; do
  sleep 2
done

echo "Emulator started. Checking status..."
adb shell getprop init.svc.bootanim

# Gracefully end all processes
adb emu kill || true
adb kill-server || true

EOF

RUN chmod +x /root/start-emulator.sh

ENTRYPOINT ["/root/start-emulator.sh"]