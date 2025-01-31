# arm-android-emu-linux
Self contained Dockerfile to run a ARM based android emulator on a ARM based Linux instance(tested on AWS Graviton processors)

# ARM-based Android Emulator Docker Image

This project uses locally mirrored Android SDK components to ensure build reliability. The official Android repository URLs can be intermittent, especially in CI/CD environments. The following components are mirrored in this repository:

- Command Line Tools (original source: https://dl.google.com/android/repository/commandlinetools-linux-8512546_latest.zip)
- ARM64 Emulator (original source: https://ci.android.com/builds/submitted/11382468/emulator-linux_aarch64/latest/sdk-repo-linux_aarch64-emulator-11382468.zip)

All components are mirrored in the [AnirudhRahul/arm-android-emu-linux](https://github.com/AnirudhRahul/arm-android-emu-linux) repository.
