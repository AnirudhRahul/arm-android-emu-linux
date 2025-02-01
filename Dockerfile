# -------------------------------------------------------
# ARM-based Android Emulator Docker Image
# -------------------------------------------------------

FROM --platform=linux/arm64 ubuntu:22.04

# ------------------------------------------------------------------------------
# 1. Environment Setup
# ------------------------------------------------------------------------------
ENV DEBIAN_FRONTEND=noninteractive \
    ANDROID_HOME=/usr/local/android-sdk-linux \
    ANDROID_SDK_ROOT=/usr/local/android-sdk-linux

ENV PATH=$PATH:$ANDROID_HOME/cmdline-tools/tools/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator

# Install core dependencies & ADB in a single layer
RUN apt-get update && apt-get install -y --no-install-recommends \
    openjdk-17-jdk \
    wget \
    unzip \
    qemu-system-arm \
    qemu-utils \
    ca-certificates \
    curl \
    android-sdk-platform-tools-common \
    adb \
 && rm -rf /var/lib/apt/lists/*

# Set Java home
ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk-arm64
ENV PATH=$PATH:$JAVA_HOME/bin

# ------------------------------------------------------------------------------
# 2. Android SDK & Emulator Setup
# ------------------------------------------------------------------------------
# Copy local cmdline-tools 
# Original source: https://dl.google.com/android/repository/commandlinetools-linux-8512546_latest.zip
COPY ./cmdline-tools/ $ANDROID_HOME/cmdline-tools/tools/

# Copy local emulator
# Original source: https://ci.android.com/builds/submitted/11382468/emulator-linux_aarch64/latest/sdk-repo-linux_aarch64-emulator-11382468.zip
COPY ./emulator/ $ANDROID_HOME/emulator/

# Create and populate package.xml properly
RUN cd $ANDROID_HOME/emulator && \
    curl -s "https://chromium.googlesource.com/android_tools/+/refs/heads/main/sdk/emulator/package.xml?format=TEXT" | base64 --decode > package.xml && \
    MAJOR_VERSION=$(grep 'Pkg.Revision' source.properties | cut -d'=' -f2 | cut -d'.' -f1) && \
    MINOR_VERSION=$(grep 'Pkg.Revision' source.properties | cut -d'=' -f2 | cut -d'.' -f2) && \
    MICRO_VERSION=$(grep 'Pkg.Revision' source.properties | cut -d'=' -f2 | cut -d'.' -f3) && \
    sed -i "s|<major>[0-9]\+</major>|<major>${MAJOR_VERSION}</major>|g" package.xml && \
    sed -i "s|<minor>[0-9]\+</minor>|<minor>${MINOR_VERSION}</minor>|g" package.xml && \
    sed -i "s|<micro>[0-9]\+</micro>|<micro>${MICRO_VERSION}</micro>|g" package.xml

# Create required directories
RUN mkdir -p $ANDROID_HOME/platforms $ANDROID_HOME/platform-tools

# Accept licenses and install required SDK packages
RUN yes | sdkmanager --sdk_root=$ANDROID_HOME --licenses && \
    sdkmanager --sdk_root=$ANDROID_HOME \
      "platform-tools" \
      "platforms;android-30" \
      "system-images;android-30;aosp_atd;arm64-v8a"

# ------------------------------------------------------------------------------
# 3. AVD Setup
# ------------------------------------------------------------------------------
RUN mkdir -p /root/.android && \
    echo "Vulkan = off" >> /root/.android/advancedFeatures.ini && \
    echo "GLDirectMem = off" >> /root/.android/advancedFeatures.ini && \
    echo "metrics.allow-host = off" >> /root/.android/advancedFeatures.ini && \
    mkdir -p /root/.android/avd/arm_pixel.avd && \
    avdmanager create avd \
      --force \
      --name "arm_pixel" \
      --package "system-images;android-30;aosp_atd;arm64-v8a" \
      --abi "arm64-v8a" \
      --device "pixel"
# ------------------------------------------------------------------------------
# 4. Startup Script
# ------------------------------------------------------------------------------
RUN cat <<'EOF' > /root/start-emulator.sh
#!/usr/bin/env bash
set -e
# Restart ADB server
adb kill-server || true
adb start-server

# Configure headless emulator environment
export ANDROID_EMU_HEADLESS=1
export ANDROID_EMU_DISABLE_VULKAN=1

# Clean up any existing AVD locks
rm -f /root/.android/avd/arm_pixel.avd/*.lock

# Launch the emulator in the background
emulator -avd arm_pixel \
  -no-window \
  -no-audio \
  -ports 5554,5555 \
  -skip-adb-auth \
  -no-boot-anim \
  -gpu swiftshader \
  -accel on \
  -memory 2048 \
  -cores 4 \
  -wipe-data \
  -qemu -cpu host -machine virt,gic-version=2 &

# Wait until the device appears
while [ -z "$(adb devices | grep -v List)" ]; do
  sleep 2
done
EOF

RUN chmod +x /root/start-emulator.sh

# Set the entrypoint to run the startup script
ENTRYPOINT ["/root/start-emulator.sh"]