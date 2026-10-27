#!/system/bin/sh
# r4 combo verifier. No unload, mounts, property writes or automatic stage switching.
REV=qilin-r4-20261028
TARGET=5.15.167-android13-8-o-01144-gb3f32e037fab
FAKE=5.15.167-HUAWEI-Kirin9020
FREQS='307200 441600 556800 672000 787200 902400 1017600 1113600 1228800 1344000 1459200 1555200 1670400 1785600 1900800 2016000 2188800 2323200 2457600 2592000 2707200 2803200 2918400 3000000 3187200'
DIR=$(CDPATH= cd "$(dirname "$0")" 2>/dev/null && pwd)
[ "$(id -u)" = 0 ] || { echo '请选择 ROOT 执行。'; exit 1; }
umask 077
BASE=/data/adb
[ -d "$BASE" ] && [ -w "$BASE" ] || BASE=/data/local/tmp
OUT="$BASE/qilin_r4_$(date '+%Y%m%d_%H%M%S')_$$"
mkdir -p "$OUT/pstore" || exit 1
PASS=0; FAIL=0
say() { printf '%s\n' "$*"; printf '%s\n' "$*" >> "$OUT/run.txt"; }
step() { say "STEP=$1"; printf '%s\n' "$1" > "$OUT/last_step.txt"; sync; }
finish() {
    printf 'pass=%s\nfail=%s\n' "$PASS" "$FAIL" > "$OUT/check_summary.txt"
    dmesg > "$OUT/dmesg_after.txt" 2> "$OUT/dmesg_error.txt"
    grep -iE 'cpuinfo_spoof|CFI failure|CFI check|panic|Oops|Call trace|Unable to handle' "$OUT/dmesg_after.txt" > "$OUT/kernel_hits.txt"
    sync
    if tar -czf "$OUT.tar.gz" -C "$BASE" "${OUT##*/}" 2> "$OUT/archive_error.txt"; then
        say "日志压缩包：$OUT.tar.gz"
    else say "日志目录：$OUT"; fi
}
stop() { say "$1"; finish; exit 1; }
value() { sed -n "s/^$1=//p" "$OUT/status.txt"; }
check() {
    printf '%s=%s\n' "$1" "$2" >> "$OUT/result.txt"
    if [ "$2" = "$3" ]; then PASS=$((PASS+1)); say "PASS $1=$2"
    else FAIL=$((FAIL+1)); say "FAIL $1=$2 (expected=$3)"; fi
}
read_check() {
    step "read_$1"
    ACTUAL=$(cat "$2" 2>> "$OUT/read_errors.txt")
    RC=$?
    if [ "$RC" = 0 ]; then check "$1" "$ACTUAL" "$3"
    else FAIL=$((FAIL+1)); say "FAIL read $2 rc=$RC"; fi
}
say "=== CPU r4 组合测试 $REV ==="
say "日志：$OUT"
for FILE in /sys/fs/pstore/*; do
    [ ! -f "$FILE" ] || cat "$FILE" > "$OUT/pstore/${FILE##*/}" 2>> "$OUT/read_errors.txt"
done
[ ! -r /proc/last_kmsg ] || cat /proc/last_kmsg > "$OUT/last_kmsg.txt" 2>> "$OUT/read_errors.txt"
dmesg > "$OUT/dmesg_before.txt" 2> "$OUT/dmesg_error.txt"
cat /proc/modules > "$OUT/modules.txt" 2>> "$OUT/read_errors.txt"
MODE=${1:-}
if [ -z "$MODE" ]; then
    say '1 = 只读预检（默认）；6 = 四分支组合；0 = 只收集状态'
    CHOICE=1
    if [ -t 0 ]; then
        printf '输入编号后回车，直接回车选1：'
        IFS= read -r ANSWER || ANSWER=
        [ -z "$ANSWER" ] || CHOICE=$ANSWER
    fi
    case "$CHOICE" in 1) MODE=inspect ;; 6) MODE=combo ;; 0) MODE=status ;; *) stop '编号无效。' ;; esac
fi
case "$MODE" in inspect|combo|status) : ;; *) stop '仅支持 inspect、combo、status。' ;; esac
say "选择：$MODE"
LOADED=0
if [ -d /sys/module/cpuinfo_spoof ]; then
    LOADED=1
    cat /proc/cpuinfo_spoof > "$OUT/status.txt" 2>> "$OUT/read_errors.txt"
    cat "$OUT/status.txt"
    [ "$MODE" != status ] || { finish; exit 0; }
    grep -qx "revision=$REV" "$OUT/status.txt" || stop '已有旧版模块，请重启，不自动卸载。'
    grep -qx "stage=$MODE" "$OUT/status.txt" || stop '已有其他项目，切换项目请重启。'
    say '同版本同项目已加载，本次只重复验证，不重新加载。'
fi
[ "$MODE" != status ] || { say '当前未加载模块。'; finish; exit 0; }
if [ "$LOADED" = 0 ]; then
    KO="$DIR/cpuinfo_spoof.ko"; REPORT="$DIR/build_report.json"
    [ -f "$KO" ] && [ -f "$REPORT" ] || stop '请把本SH、新KO、build_report.json一起放到同一个目录。'
    command -v strings >/dev/null 2>&1 || stop '缺少 strings。'
    command -v sha256sum >/dev/null 2>&1 || stop '缺少 sha256sum。'
    strings "$KO" > "$OUT/module_strings.txt"
    grep -qx "version=$REV" "$OUT/module_strings.txt" || stop 'KO不是r4。'
    grep -qx 'name=cpuinfo_spoof' "$OUT/module_strings.txt" || stop '模块名不符。'
    grep -q "^vermagic=$TARGET " "$OUT/module_strings.txt" || stop 'vermagic不符。'
    HASH=$(sha256sum "$KO" | awk '{print $1}')
    EXPECTED=$(awk -F '"' '/"sha256"/ {print $4; exit}' "$REPORT")
    [ -n "$EXPECTED" ] && [ "$HASH" = "$EXPECTED" ] || stop 'KO与构建报告哈希不一致。'
    [ "$(uname -r)" = "$TARGET" ] || stop '当前release与目标不一致。'
    cp "$REPORT" "$OUT/build_report.json"
    printf '%s  %s\n' "$HASH" "$KO" > "$OUT/module_sha256.txt"
    FLAGS="stage=$MODE"
    [ "$MODE" != combo ] || FLAGS="$FLAGS pointer_tests=1"
    say "参数：$FLAGS"
    step "before_insmod_$MODE"
    insmod "$KO" $FLAGS > "$OUT/insmod.txt" 2>&1
    RC=$?
    cat "$OUT/insmod.txt"
    say "insmod_exit=$RC"
    [ "$RC" = 0 ] || stop '加载返回错误，保存日志后停止。'
    step "after_insmod_$MODE"
    cat /proc/cpuinfo_spoof > "$OUT/status.txt" 2>> "$OUT/read_errors.txt"
    cat "$OUT/status.txt"
fi
grep -qx "revision=$REV" "$OUT/status.txt" || stop '已加载版本不符。'
if [ "$MODE" = inspect ]; then
    grep -qx 'state=inspect_only' "$OUT/status.txt" || stop '预检状态不符。'
    grep -qx 'applied=0' "$OUT/status.txt" || stop '预检修改数不应大于0。'
    for ITEM in uts cpus topology cpufreq; do
        check "preflight_$ITEM" "$(value preflight_$ITEM)" 0
    done
    say '只读预检结束；未启用伪装。'
    finish
    [ "$FAIL" = 0 ]
    exit $?
fi
grep -qx 'state=active' "$OUT/status.txt" || stop '不是完整active实例，不继续读取。'
grep -qx 'last_error=0' "$OUT/status.txt" || stop '内核报告错误。'
check planned "$(value planned)" 9
check applied "$(value applied)" 9
check pointer_applied "$(value pointer_applied)" 8
check uts_applied "$(value uts_applied)" 1
[ "$FAIL" = 0 ] || stop '修改计数未达标。'
ROUND=1
while [ "$ROUND" -le 3 ]; do
    say "=== 读取轮次 $ROUND/3 ==="
    step "before_round_$ROUND"
    check uname_release "$(uname -r)" "$FAKE"
    step read_proc_version
    VERSION=$(cat /proc/version 2>> "$OUT/read_errors.txt")
    printf 'proc_version=%s\n' "$VERSION" >> "$OUT/result.txt"
    case "$VERSION" in "Linux version $FAKE "*) check proc_version_release match match ;;
        *) check proc_version_release mismatch match ;; esac
    for KEY in online possible present; do
        read_check "cpus_$KEY" "/sys/devices/system/cpu/$KEY" '0-11'
    done
    for CPU in 0 1 2 3 4 5 6 7; do
        if [ "$CPU" -lt 4 ]; then CORE=$CPU; PACKAGE=0
        else CORE=$((CPU-4)); PACKAGE=1; fi
        read_check "cpu${CPU}_core_id" "/sys/devices/system/cpu/cpu$CPU/topology/core_id" "$CORE"
        read_check "cpu${CPU}_package" "/sys/devices/system/cpu/cpu$CPU/topology/physical_package_id" "$PACKAGE"
        read_check "cpu${CPU}_die" "/sys/devices/system/cpu/cpu$CPU/topology/die_id" '-1'
    done
    read_check available_frequencies /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_frequencies "$FREQS"
    read_check boost_frequencies /sys/devices/system/cpu/cpu0/cpufreq/scaling_boost_frequencies '3187200'
    step "after_round_$ROUND"
    [ "$FAIL" = 0 ] || break
    ROUND=$((ROUND+1))
    [ "$ROUND" -gt 3 ] || sleep 2
done
say "PASS=$PASS FAIL=$FAIL（有限读取测试，不代表长期稳定）"
say '本轮不改cpuinfo、不生成cpu8-11、不联动GPU、不启用nproc。'
finish
[ "$FAIL" = 0 ]
