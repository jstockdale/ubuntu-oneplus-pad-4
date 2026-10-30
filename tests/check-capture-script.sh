#!/bin/bash
# Prove capture-device-data.sh end-to-end without a tablet: a mock ssh
# serves fixture partitions, and the test asserts byte-exact round-trips,
# clean skipping of absent partitions, and the archive's integrity files.
#
# This exists because the script's one real run happens at a moment that
# cannot be rehearsed — the first boot of the first installed image — so
# everything about it must be proven beforehand.
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
t=$(mktemp -d)
cleanup() { rm -rf -- "$t"; }
trap cleanup EXIT

mkdir -p "$t/fixture/by-partlabel" "$t/bin" "$t/work"
dd if=/dev/urandom of="$t/fixture/by-partlabel/persist" bs=1k count=256 status=none
dd if=/dev/urandom of="$t/fixture/by-partlabel/modemst1_a" bs=1k count=32 status=none
dd if=/dev/urandom of="$t/fixture/by-partlabel/fsg_b" bs=1k count=16 status=none
printf 'major minor  #blocks  name\n 259 0 1000000 sda\n' > "$t/fixture/proc-partitions"

cat > "$t/bin/mock-ssh" <<'EOF'
#!/bin/bash
FIX="${CAPTURE_FIXTURE:?}"
args=("$@"); cmd=""; i=0
while [ $i -lt ${#args[@]} ]; do
	a="${args[$i]}"
	case "$a" in
		-o) i=$((i+2)); continue ;;
		-O) exit 0 ;;
		-*) i=$((i+1)); continue ;;
		*) i=$((i+1)); cmd="${args[*]:$i}"; break ;;
	esac
done
cmd=$(printf '%s' "$cmd" | sed \
	-e "s|/dev/disk/by-partlabel|$FIX/by-partlabel|g" \
	-e "s|/proc/partitions|$FIX/proc-partitions|g" \
	-e 's/sudo //g')
exec bash -c "$cmd"
EOF
chmod +x "$t/bin/mock-ssh"

UBUNTU_WORKDIR="$t/work" CAPTURE_FIXTURE="$t/fixture" \
	CAPTURE_SSH="$t/bin/mock-ssh" \
	bash "$repo/scripts/capture-device-data.sh" fake@tablet unit-test >/dev/null

out=$t/work/stock/device-capture/unit-test
fail=0
for f in persist modemst1_a fsg_b; do
	a=$(gunzip -c "$out/$f.img.gz" | sha256sum | cut -d' ' -f1)
	b=$(sha256sum "$t/fixture/by-partlabel/$f" | cut -d' ' -f1)
	[ "$a" = "$b" ] || { echo "FAIL: $f round-trip differs"; fail=1; }
done
[ ! -e "$out/oplusreserve1.img.gz" ] || { echo 'FAIL: absent partition captured'; fail=1; }
[ -s "$out/SHA256SUMS" ] || { echo 'FAIL: no SHA256SUMS'; fail=1; }
[ -s "$out/by-partlabel.txt" ] || { echo 'FAIL: no inventory'; fail=1; }
grep -q 'partitions=3' "$out/CAPTURE-METADATA.txt" || { echo 'FAIL: wrong count'; fail=1; }
(cd "$out" && sha256sum -c SHA256SUMS >/dev/null) || { echo 'FAIL: SUMS verify'; fail=1; }

[ "$fail" = 0 ] && echo 'check-capture-script: PASS' || exit 1
