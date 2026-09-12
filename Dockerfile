FROM ubuntu:24.04

ARG HOST_UID=1000
ARG HOST_GID=1000

ENV DEBIAN_FRONTEND=noninteractive \
    PATH="/usr/local/bin:/usr/lib/llvm-18/bin:/opt/ps5-payload-sdk/bin:${PATH}" \
    PS5_PAYLOAD_SDK=/opt/ps5-payload-sdk \
    KEYSTONE_PREFIX=/usr/local \
    LLVM_CONFIG=/usr/lib/llvm-18/bin/llvm-config

# ============================================================
# Packages
# ============================================================

RUN apt-get update && apt-get install -y --no-install-recommends \
      bash \
      build-essential \
      ca-certificates \
      clang-18 \
      cmake \
      curl \
      lld-18 \
      llvm-18 \
      make \
      nodejs \
      npm \
      meson \
      ninja-build \
      passwd \
      pkg-config \
      python3 \
      python3-pip \
      python3-pyelftools \
      socat \
      unzip \
      wget \
      xz-utils \
      libssl-dev \
      librsvg2-bin \
      git \
      autoconf \
      automake \
      libtool \
      m4 \
      gettext \
      perl \
    && ln -sf /usr/lib/llvm-18/bin/llvm-config /usr/local/bin/llvm-config \
    && rm -rf /var/lib/apt/lists/*

# ============================================================
# Source
# ============================================================

WORKDIR /workspace

COPY . /workspace

RUN find /workspace -type f \
      \( -name "*.sh" -o -name "*.bash" \) \
      -print0 \
    | xargs -0 -r sed -i 's/\r$//'

# ============================================================
# PS5 Payload SDK
# ============================================================

RUN git clone --depth 1 \
      https://github.com/ps5-payload-dev/sdk.git \
      /tmp/ps5-payload-sdk-src \
    && export LLVM_CONFIG=/usr/lib/llvm-18/bin/llvm-config \
    && export PATH=/usr/lib/llvm-18/bin:${PATH} \
    && make -C /tmp/ps5-payload-sdk-src \
         DESTDIR=/opt/ps5-payload-sdk \
         install \
    && cd /tmp/ps5-payload-sdk-src \
    && export LLVM_CONFIG=/usr/lib/llvm-18/bin/llvm-config \
    && ./libcxx.sh \
    && cd /workspace \
    && rm -rf /tmp/ps5-payload-sdk-src

# ============================================================
# PS5 SDK Homebrew directories
# ============================================================

RUN mkdir -p \
      /opt/ps5-payload-sdk/target/user/homebrew/include \
      /opt/ps5-payload-sdk/target/user/homebrew/lib \
      /opt/ps5-payload-sdk/target/user/homebrew/etc \
      /opt/ps5-payload-sdk/target/user/homebrew/share

# ============================================================
# PS5 libcurl
#
# IMPORTANT:
# Use the PS5 Payload SDK toolchain.
# Do NOT use Ubuntu's native libcurl.
# ============================================================

RUN set -eux; \
    cd /tmp; \
    curl -fsSL --retry 5 \
      https://curl.haxx.se/download/curl-8.18.0.tar.xz \
      -o curl.tar.xz; \
    tar -xf curl.tar.xz; \
    cd curl-8.18.0; \
    \
    export PS5_PAYLOAD_SDK=/opt/ps5-payload-sdk; \
    export PATH="${PS5_PAYLOAD_SDK}/bin:/usr/lib/llvm-18/bin:${PATH}"; \
    export LLVM_CONFIG=/usr/lib/llvm-18/bin/llvm-config; \
    \
    if [ -f src/tool_xattr.h ]; then \
      sed -i 's/define USE_XATTR/ /g' src/tool_xattr.h || true; \
    fi; \
    \
    autoreconf -fi; \
    \
    if [ -f "${PS5_PAYLOAD_SDK}/toolchain/prospero.sh" ]; then \
      . "${PS5_PAYLOAD_SDK}/toolchain/prospero.sh"; \
    else \
      echo "ERROR: prospero.sh not found"; \
      find "${PS5_PAYLOAD_SDK}" -name prospero.sh -print; \
      exit 1; \
    fi; \
    \
    ./configure \
      --prefix=/user/homebrew \
      --host=x86_64-pc-freebsd \
      --enable-static \
      --disable-shared \
      --with-openssl \
      --disable-docs; \
    \
    make -j"$(nproc)"; \
    \
    make DESTDIR=/opt/ps5-payload-sdk/target install; \
    \
    echo "===== CURL INSTALL ====="; \
    find /opt/ps5-payload-sdk/target/user/homebrew \
      -maxdepth 4 \
      -type f \
      -print; \
    \
    rm -rf /tmp/curl.tar.xz /tmp/curl-8.18.0

# ============================================================
# CA bundle
# ============================================================

RUN set -eux; \
    mkdir -p \
      /opt/ps5-payload-sdk/target/user/homebrew/etc \
      /opt/ps5-payload-sdk/target/user/homebrew/share; \
    \
    curl -fsSL --retry 5 \
      https://curl.se/ca/cacert.pem \
      -o /opt/ps5-payload-sdk/target/user/homebrew/etc/ca-bundle.crt; \
    \
    cp \
      /opt/ps5-payload-sdk/target/user/homebrew/etc/ca-bundle.crt \
      /opt/ps5-payload-sdk/target/user/homebrew/share/ca-bundle.crt; \
    \
    cp \
      /opt/ps5-payload-sdk/target/user/homebrew/etc/ca-bundle.crt \
      /opt/ps5-payload-sdk/target/user/homebrew/share/cacert.pem

# ============================================================
# Verify PS5 libcurl
# ============================================================

RUN set -eux; \
    echo "========================================"; \
    echo "       VERIFY PS5 CURL"; \
    echo "========================================"; \
    \
    test -f \
      /opt/ps5-payload-sdk/target/user/homebrew/lib/libcurl.a; \
    \
    test -d \
      /opt/ps5-payload-sdk/target/user/homebrew/include/curl; \
    \
    test -f \
      /opt/ps5-payload-sdk/target/user/homebrew/etc/ca-bundle.crt; \
    \
    test -f \
      /opt/ps5-payload-sdk/target/user/homebrew/share/ca-bundle.crt; \
    \
    echo "libcurl.a:"; \
    ls -lh \
      /opt/ps5-payload-sdk/target/user/homebrew/lib/libcurl.a; \
    \
    echo "curl headers:"; \
    ls \
      /opt/ps5-payload-sdk/target/user/homebrew/include/curl; \
    \
    echo "CA bundle:"; \
    ls -lh \
      /opt/ps5-payload-sdk/target/user/homebrew/etc/ca-bundle.crt; \
    \
    echo "===== PS5 HOMEBREW ====="; \
    find /opt/ps5-payload-sdk/target/user/homebrew \
      -maxdepth 4 \
      -type f \
      -print

# ============================================================
# Keystone
# ============================================================

RUN pip3 install \
      --break-system-packages \
      --no-cache-dir \
      keystone-engine \
    && KSO=$(python3 -c \
      'import keystone, os; print(os.path.join(os.path.dirname(keystone.__file__), "libkeystone.so"))') \
    && ln -sf "$KSO" /usr/local/lib/libkeystone.so \
    && ln -sf "$KSO" /usr/local/lib/libkeystone.so.0 \
    && ldconfig

# ============================================================
# Builder user
# ============================================================

RUN if getent group "${HOST_GID}" >/dev/null; then \
        builder_group="$(getent group "${HOST_GID}" | cut -d: -f1)"; \
    else \
        groupadd --gid "${HOST_GID}" builder; \
        builder_group=builder; \
    fi \
    && existing_user="$(getent passwd "${HOST_UID}" | cut -d: -f1 || true)" \
    && if [ -n "${existing_user}" ] && [ "${existing_user}" != "builder" ]; then \
        usermod --login builder "${existing_user}" \
        && usermod --home /home/builder --move-home builder; \
    elif ! id builder >/dev/null 2>&1; then \
        useradd \
          --uid "${HOST_UID}" \
          --gid "${HOST_GID}" \
          --create-home \
          --shell /bin/bash \
          builder; \
    fi \
    && usermod --gid "${HOST_GID}" --shell /bin/bash builder \
    && chown -R builder:"${builder_group}" /workspace

USER builder

# ============================================================
# Build onionHEN
# ============================================================

CMD ["/bin/bash", "-lc", "\
set -euo pipefail; \
rm -rf /tmp/onionhen-build; \
cp -a /workspace/. /tmp/onionhen-build; \
python3 -c \"from pathlib import Path; files=list(Path('/tmp/onionhen-build').rglob('*.sh'))+list(Path('/tmp/onionhen-build').rglob('*.bash')); [p.write_bytes(p.read_bytes().replace(bytes([13]), bytes())) for p in files]\"; \
cd /tmp/onionhen-build; \
export PS5_PAYLOAD_SDK=/opt/ps5-payload-sdk; \
export PATH=/usr/lib/llvm-18/bin:${PS5_PAYLOAD_SDK}/bin:${PATH}; \
export LLVM_CONFIG=/usr/lib/llvm-18/bin/llvm-config; \
echo '========================================'; \
echo '          onionHEN BUILD'; \
echo '========================================'; \
echo 'PS5 SDK:'; \
echo \"${PS5_PAYLOAD_SDK}\"; \
echo ''; \
echo 'Checking libcurl...'; \
test -f \"${PS5_PAYLOAD_SDK}/target/user/homebrew/lib/libcurl.a\"; \
echo 'libcurl OK'; \
echo ''; \
echo 'Checking curl headers...'; \
test -f \"${PS5_PAYLOAD_SDK}/target/user/homebrew/include/curl/curl.h\"; \
echo 'curl headers OK'; \
echo ''; \
echo 'Checking CA bundle...'; \
test -f \"${PS5_PAYLOAD_SDK}/target/user/homebrew/etc/ca-bundle.crt\"; \
echo 'CA bundle OK'; \
echo ''; \
echo 'Dependencies OK'; \
echo ''; \
./scripts/build.sh --jobs 8 --release; \
echo ''; \
echo '========================================'; \
echo '          BUILD FINISHED'; \
echo '========================================'; \
rm -rf /workspace/build; \
cp -a /tmp/onionhen-build/build /workspace/build; \
find /workspace/build/bin -maxdepth 1 -type f -print \
"]
