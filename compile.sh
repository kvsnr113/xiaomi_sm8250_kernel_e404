#!/usr/bin/env bash
# E404 Kernel Compile Script

set -o pipefail

export ARCH=arm64
export SUBARCH=arm64
export TZ=Asia/Jakarta

# Directories
KERNEL_DIR="$PWD"
BASE_DIR="$PWD/.."
OUT_DIR="$KERNEL_DIR/out"
LOG_FILE="$OUT_DIR/kernel_compile.log"
CHANGELOG_FILE="$BASE_DIR/kernel_changelog.txt"

BRANCH=$(git rev-parse --abbrev-ref HEAD)

export CCACHE_EXEC=/usr/bin/ccache
export USE_CCACHE=1
if [[ "$BRANCH" == *bpf* ]]; then
    export CCACHE_DIR="$BASE_DIR/ccache/.kernel-bpf"
else
    export CCACHE_DIR="$BASE_DIR/ccache/.kernel"
fi

# Kernel parts
K_IMG="$KERNEL_DIR/out/arch/arm64/boot/Image"
K_DTBO="$KERNEL_DIR/out/arch/arm64/boot/dtbo.img"
K_DTB="$KERNEL_DIR/out/arch/arm64/boot/dtb"

AK3_DIR="$BASE_DIR/AnyKernel3"
[[ ! -d "$AK3_DIR" ]] && echo "--- ! Failed to find AnyKernel3 at $AK3_DIR ! ---" && exit 1

# Telegram API setup
TELEGRAM_CONFIG="$BASE_DIR/telegram_api"
if [[ ! -f "$TELEGRAM_CONFIG" ]]; then
    echo "--- ! Failed to find Telegram API config at $TELEGRAM_CONFIG ! ---"
    exit 1
else
    source "$TELEGRAM_CONFIG"
    if [[ -z "$BOT_TOKEN" || -z "$GROUP_ID" || -z "$CHANNEL_ID" || -z "$PRIVATE_ID" ]]; then
        echo "--- ! Failed to find Telegram required variables (BOT_TOKEN, GROUP_ID, CHANNEL_ID, PRIVATE_ID) ! ---"
        exit 1
    fi
fi

MSGTARGET="private"

for arg in "$@"; do
    case "$arg" in
        weekly) MSGTARGET="channel" ;;
        group) MSGTARGET="group" ;;
    esac
done

case "$MSGTARGET" in
    channel) ID="$CHANNEL_ID" ;;
    group)   ID="$GROUP_ID" ;;
    *)       ID="$PRIVATE_ID" ;;
esac

send_msg() {
    curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
        -d chat_id="$ID" \
        -d text="$1" \
        -d parse_mode=html >/dev/null
}

send_file() {
    curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendDocument" \
        -F chat_id="$ID" \
        -F document=@"$1" >/dev/null
}

send_changelog() {
    local FILE="$1"

    if [[ ! -f "$FILE" ]]; then
        echo "--- ! Failed to find changelog at $FILE ! ---"
        return
    fi

    # If empty, use default
    if [[ ! -s "$FILE" ]]; then
        echo "- Another weekly build" > "$FILE"
    fi

    # Proper newline → Telegram format
    local CHANGELOG
    CHANGELOG=$(sed 's/$/%0A/' "$FILE" | tr -d '\n')

    send_msg "<b>Changelog(s):</b>%0A<code>$CHANGELOG</code>"
}

# Arrays to support multi-device target
TARGETS=()
DEFCONFIGS=()
DEVICES=()
ZIPS=()

# Device map
if [[ "$*" == *gcc* ]]; then
    declare -A DEVICE_MAP=(
        ["munch"]="MUNCH:vendor/munch_gcc_defconfig"
        ["alioth"]="ALIOTH:vendor/alioth_gcc_defconfig"
        ["apollo"]="APOLLO:vendor/apollo_gcc_defconfig"
        ["pipa"]="PIPA:vendor/pipa_gcc_defconfig"
        ["lmi"]="LMI:vendor/lmi_gcc_defconfig"
        ["umi"]="UMI:vendor/umi_gcc_defconfig"
        ["cmi"]="CMI:vendor/cmi_gcc_defconfig"
        ["cas"]="CAS:vendor/cas_gcc_defconfig"
    )
else
    declare -A DEVICE_MAP=(
        ["munch"]="MUNCH:vendor/munch_defconfig"
        ["alioth"]="ALIOTH:vendor/alioth_defconfig"
        ["apollo"]="APOLLO:vendor/apollo_defconfig"
        ["pipa"]="PIPA:vendor/pipa_defconfig"
        ["lmi"]="LMI:vendor/lmi_defconfig"
        ["umi"]="UMI:vendor/umi_defconfig"
        ["cmi"]="CMI:vendor/cmi_defconfig"
        ["cas"]="CAS:vendor/cas_defconfig"
    )
fi

declare -A DEVICE_NAME_MAP=(
    ["munch"]="POCO_F4"
    ["alioth"]="POCO_F3"
    ["apollo"]="MI_10T"
    ["lmi"]="POCO_F2"
    ["pipa"]="MI_PAD6"
)

# Toolchain selection
case "$*" in
    *aosp*) export PATH="$BASE_DIR/toolchains/aosp-clang/bin:$PATH"; TC="AOSP-Clang" ;;
    *neutron*) export PATH="$BASE_DIR/toolchains/neutron-clang/bin:$PATH"; TC="Neutron-Clang" ;;
    *llvm*) export PATH="$BASE_DIR/toolchains/llvm-clang/bin:$PATH"; TC="LLVM-Clang" ;;
    *lilium*) export PATH="$BASE_DIR/toolchains/lilium-clang/bin:$PATH"; TC="Lilium-Clang" ;;
    *gcc*)
        GCC64_DIR="$BASE_DIR/toolchains/gcc/gcc-14.2.0-nolibc/aarch64-linux/bin"
        GCC32_DIR="$BASE_DIR/toolchains/gcc/gcc-14.2.0-nolibc/arm-linux-gnueabi/bin"
        export PATH="$GCC64_DIR:$GCC32_DIR:$PATH"
        TC="GCC"
    ;;
    *)
        if [[ -d "$BASE_DIR/toolchains/clang" ]]; then
            export PATH="$BASE_DIR/toolchains/clang/bin:$PATH"
            TC="Clang"
        else
            echo "--- ! Failed to find toolchain at $BASE_DIR/toolchains/ ! ---" && exit 1
        fi
    ;;
esac

for arg in "$@"; do
    for device in "${!DEVICE_MAP[@]}"; do
        if [[ "$arg" == "$device" ]]; then
            IFS=':' read -r TARGET DEFCONFIG <<< "${DEVICE_MAP[$device]}"
            TARGETS+=("$TARGET")
            DEFCONFIGS+=("$DEFCONFIG")
            DEVICES+=("$device")
        fi
    done
done

compilebuild() {
    if [[ $TC == *Clang* ]]; then
        make -j$(nproc) O=out \
            CC="ccache clang" \
            CROSS_COMPILE=aarch64-linux-gnu- \
            CROSS_COMPILE_COMPAT=arm-linux-gnueabi- \
            LLVM=1 LLVM_IAS=1 \
            2>&1 | tee -a "$LOG_FILE"
    else
        make -j$(nproc) O=out \
            CC="ccache aarch64-linux-gcc" \
            CROSS_COMPILE=aarch64-linux- \
            CROSS_COMPILE_COMPAT=arm-linux-gnueabi- \
            2>&1 | tee -a "$LOG_FILE"
    fi
}

zipbuild() {
    local TARGET="$1"
    local DEVICE="$2"

    cd "$AK3_DIR"

    DEVICE_NAME="${DEVICE_NAME_MAP[$DEVICE]:-$DEVICE}"

    if [[ "$BRANCH" == *bpf* ]]; then
        ZIP_NAME="RE404-${DEVICE_NAME}-BPF-$(date "+%y%m%d-%H%M").zip"
    else
        ZIP_NAME="RE404-${DEVICE_NAME}-$(date "+%y%m%d-%H%M").zip"
    fi

    zip -r9 "$OUT_DIR/$ZIP_NAME" META-INF tools "${TARGET}"* anykernel.sh
    cd "$KERNEL_DIR"
}

build_device() {
    TARGET="$1"
    DEFCONFIG="$2"
    DEVICE="$3"

    echo "--- Building for $TARGET ---"

    sed -i "/devicename=/c\devicename=${DEVICE}" "$AK3_DIR/anykernel.sh"

    rm -rf out/arch/arm64/boot

    make O=out "$DEFCONFIG" 2>&1 | tee -a "$LOG_FILE"

    compilebuild

    [[ -f "$K_IMG" && -f "$K_DTBO" && -f "$K_DTB" ]] || return 1
    rm -f "$AK3_DIR/${TARGET}-"*
    cp "$K_IMG" "$AK3_DIR/${TARGET}-Image"
    cp "$K_DTBO" "$AK3_DIR/${TARGET}-dtbo.img"
    cp "$K_DTB" "$AK3_DIR/${TARGET}-dtb"

    zipbuild "$TARGET" "$DEVICE"
    ZIPS+=("$OUT_DIR/$ZIP_NAME")
}

# Compile
if [[ $# -gt 0 ]]; then
    [[ ${#TARGETS[@]} -eq 0 ]] && echo "--- ! Invalid devices ! ---" && exit 1

    rm -f "$LOG_FILE"
    rm -rf "$OUT_DIR"
    mkdir -p "$OUT_DIR"

    FAIL=0
    for i in "${!TARGETS[@]}"; do
        if ! build_device "${TARGETS[$i]}" "${DEFCONFIGS[$i]}" "${DEVICES[$i]}"; then
            send_msg "<b>Kernel Weekly Build $(date "+%Y-%m-%d")</b>%0A<b>Branch: </b><code>$BRANCH</code>"
            send_file "$LOG_FILE"
            send_msg "<b>! Kernel Build Failed !</b>"
            echo "--- ! Failed to build ${TARGETS[$i]} kernel ! ---"
            FAIL=1
        fi
    done

    if [[ $FAIL -eq 0 ]]; then
        echo "--- Uploading builds ---"
        send_msg "<b>Kernel Weekly Build $(date "+%Y-%m-%d")</b>%0A<b>Branch: </b><code>$BRANCH</code>"

        for zip in "${ZIPS[@]}"; do
            if ! send_file "$zip"; then
                echo "--- ! Failed to upload $zip ! ---"
            else
                echo "--- Uploaded $zip ---"
            fi
        done
        if [[ "$*" == *changelog* ]]; then
            send_changelog "$CHANGELOG_FILE"
        fi
        echo "--- All builds completed ---"
    fi

    echo "======== CCache Stats =========="
    ccache -p | grep cache_dir
    ccache -s
    echo "================================"

    exit 0
fi