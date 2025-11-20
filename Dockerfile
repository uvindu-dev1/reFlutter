FROM ubuntu:22.04

ARG HASH_PATCH
ARG COMMIT

ENV DEPOT_TOOLS_PATH=/depot_tools
ENV TEMP_ENGINE=/engine
ENV ENGINE_PATH=/customEngine
ENV PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/depot_tools
ENV WAIT=4
ENV HASH_PATCH=$HASH_PATCH
ENV COMMIT=$COMMIT

# Suppress git version warning and other gclient warnings
ENV GCLIENT_SUPPRESS_GIT_VERSION_WARNING=1
ENV DEPOT_TOOLS_UPDATE=0

RUN apt-get update && \
  DEBIAN_FRONTEND="noninteractive" apt-get install -y \
  git wget curl unzip \
  python3-pip python3 lsb-release sudo \
  tzdata python3-pkgconfig \
  default-jre default-jdk ninja-build && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/* && \
  mkdir /t

ENTRYPOINT ["/bin/sh", "-c", "\
set -e && \
echo '=== Installing reFlutter ===' && \
cd /t && \
pip3 install wheel && \
pip3 install . && \
echo '=== Setting up depot_tools ===' && \
rm -rf ${DEPOT_TOOLS_PATH} 2>/dev/null && \
git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git ${DEPOT_TOOLS_PATH} && \
echo '=== Cloning Flutter engine template ===' && \
rm -rf ${TEMP_ENGINE} 2>/dev/null && \
git clone https://github.com/flutter/engine.git ${TEMP_ENGINE} && \
cd ${TEMP_ENGINE} && \
git config --global user.email 'reflutter@example.com' && \
git config --global user.name 'reflutter' && \
echo '=== Checking out specific commit ===' && \
git fetch origin ${COMMIT} && \
git reset --hard ${COMMIT} && \
echo '=== Applying reFlutter patches ===' && \
reflutter -b ${HASH_PATCH} -p && \
echo 'reflutter' > REFLUTTER && \
git add . && \
git commit -am 'reflutter' || true && \
echo '=== Setting up engine workspace ===' && \
rm -rf ${ENGINE_PATH} 2>/dev/null && \
mkdir -p ${ENGINE_PATH} && \
cd ${ENGINE_PATH} && \
echo 'solutions = [{\"managed\": False,\"name\": \".\",\"url\": \"'${TEMP_ENGINE}'\",\"custom_deps\": {},\"deps_file\": \"DEPS\",\"safesync_url\": \"\",},]' > .gclient && \
echo '=== Creating stub pub_get_offline.py ===' && \
mkdir -p ${TEMP_ENGINE}/tools && \
cat > ${TEMP_ENGINE}/tools/pub_get_offline.py << 'PYTHON_SCRIPT'
#!/usr/bin/env python3
import sys
print('Skipping pub_get_offline.py (stub for compatibility)')
sys.exit(0)
PYTHON_SCRIPT
chmod +x ${TEMP_ENGINE}/tools/pub_get_offline.py && \
echo '=== Running gclient sync ===' && \
gclient sync -D --no-history 2>&1 | tee /tmp/gclient.log || { \
  echo 'WARNING: gclient sync had errors, checking if critical files exist...'; \
  if [ ! -f engine/src/flutter/tools/gn ]; then \
    echo 'ERROR: Critical file engine/src/flutter/tools/gn not found!'; \
    cat /tmp/gclient.log; \
    exit 1; \
  fi; \
  echo 'Critical files present, continuing...'; \
} && \
echo '=== Applying patches to synced source ===' && \
cd engine/src/flutter && \
reflutter -b ${HASH_PATCH} -p || echo 'WARNING: Patch application had issues, continuing...' && \
cd ${ENGINE_PATH} && \
echo '=== Verifying build prerequisites ===' && \
if [ ! -f engine/src/flutter/tools/gn ]; then \
  echo 'ERROR: GN tool not found at engine/src/flutter/tools/gn'; \
  echo 'Directory contents:'; \
  ls -la engine/src/flutter/tools/ || echo 'tools/ directory does not exist'; \
  exit 1; \
fi && \
echo '✓ GN tool found' && \
if ! command -v ninja > /dev/null; then \
  echo 'ERROR: ninja build tool not found'; \
  exit 1; \
fi && \
echo '✓ Ninja found' && \
echo '=== Waiting for manual modifications (${WAIT} seconds) ===' && \
sleep ${WAIT} && \
export NINJA_SUMMARIZE_BUILD=1 && \
echo '=== Building ARM64 ===' && \
engine/src/flutter/tools/gn --no-goma --android --android-cpu=arm64 --runtime-mode=release && \
ninja -C engine/src/out/android_release_arm64 && \
cp engine/src/out/android_release_arm64/lib.stripped/libflutter.so /libflutter_arm64.so && \
echo '✓ ARM64 build complete' && \
ls -lh /libflutter_arm64.so && \
cd / && \
echo '=== Copying build artifacts ===' && \
cp /libflutter_arm64.so /t/libflutter_arm64.so && \
echo '=== Build Summary ===' && \
echo 'Snapshot Hash: ${HASH_PATCH}' && \
echo 'Engine Commit: ${COMMIT}' && \
echo 'Architecture: arm64-v8a' && \
ls -lh /t/libflutter_arm64.so"]

CMD ["bash"]
