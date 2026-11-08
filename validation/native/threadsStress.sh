#!/bin/sh
# Builds validation/native/threadsStress.c against native/src/threads with ThreadSanitizer and
# AddressSanitizer and runs both. Usage: sh validation/native/threadsStress.sh [rounds]
set -e
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
LUAJIT=${LUAJIT_PREFIX:-/usr/local}
OUT=${TMPDIR:-/tmp}/katsa-threads-stress
ROUNDS=${1:-150}
mkdir -p "$OUT"
FLAGS="-O1 -g -rdynamic -I$ROOT/native/src -I$LUAJIT/include/luajit-2.1"
LIBS="$LUAJIT/lib/libluajit-5.1.a -lm -ldl -lpthread"
SOURCES="$ROOT/validation/native/threadsStress.c $ROOT/native/src/threads/*.c"
gcc $FLAGS -fsanitize=thread $SOURCES $LIBS -o "$OUT/tsan"
gcc $FLAGS -fsanitize=address $SOURCES $LIBS -o "$OUT/asan"
# setarch -R: TSan needs a non-randomized address space on recent kernels.
TSAN_OPTIONS="halt_on_error=0 report_signal_unsafe=0" setarch -R "$OUT/tsan" "$ROUNDS" > "$OUT/tsan.log" 2>&1 || true
echo "TSan: races=$(grep -c 'WARNING: ThreadSanitizer' "$OUT/tsan.log" || true) $(grep rounds= "$OUT/tsan.log")"
"$OUT/asan" "$ROUNDS" > "$OUT/asan.log" 2>&1 || true
echo "ASan: errors=$(grep -c 'ERROR: AddressSanitizer' "$OUT/asan.log" || true) $(grep rounds= "$OUT/asan.log")"
echo "Logs: $OUT"
