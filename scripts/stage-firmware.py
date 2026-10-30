#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Stage the proprietary firmware for iceland and record its provenance.

A manifest under configs/firmware/ declares every staged file: where it lands
under /lib/firmware, where it comes from inside the owner's stock partition
images, and its SHA-256.  This tool extracts the sources (fsck.erofs for the
EROFS vendor/odm images), verifies every hash, and writes the overlay tree
plus a PROVENANCE.json that the image and the release manifest stamp in.

Modeled on stage-firmware.py of the ubuntu-galaxy-tab-s9-ultra port, smaller
because this device's sources are uniform: everything comes out of the OTA's
vendor/odm EROFS images that stage-stock-images.sh already dumped.

    stage-firmware.py stage  --manifest M --stock DIR --out DIR
    stage-firmware.py record --manifest M --stock DIR [--write M2]

`stage` refuses any byte that does not match the manifest, and refuses a
manifest entry that has no hash: run `record` first, review its diff, commit
it.  `record` fills in hashes measured from the owner's package and reports
entries whose declared source does not exist — the expected state of the
template manifest until the first real package has been opened.  No blob ever
enters Git and nothing is flashed.
"""
import argparse
import hashlib
import json
import shutil
import subprocess
import sys
import tempfile
import tomllib
from datetime import datetime, timezone
from pathlib import Path

TOOL = "stage-firmware.py/1"


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def load_manifest(path: Path) -> dict:
    with path.open("rb") as f:
        manifest = tomllib.load(f)
    seen = set()
    for entry in manifest.get("file", []):
        for key in ("dest", "image", "source"):
            if key not in entry:
                sys.exit(f"manifest entry missing '{key}': {entry}")
        if entry["dest"] in seen:
            sys.exit(f"duplicate dest in manifest: {entry['dest']}")
        seen.add(entry["dest"])
    return manifest


def extract_images(manifest: dict, stock: Path, scratch: Path) -> dict:
    """Extract each partition image the manifest references, once.

    vendor/odm are EROFS; modem/bluetooth/dsp are vfat (the NON-HLOS
    style), detected by magic rather than by name so a wrong staging fails
    loudly instead of extracting garbage.
    """
    trees = {}
    for image in sorted({e["image"] for e in manifest.get("file", [])}):
        img = stock / f"{image}.img"
        if not img.is_file():
            sys.exit(f"missing partition image: {img} "
                     "(run stage-stock-images.sh with it in STOCK_PARTITIONS)")
        tree = scratch / image
        tree.mkdir()
        with img.open("rb") as f:
            f.seek(1024)
            erofs = f.read(4) == b"\xe2\xe1\xf5\xe0"
        if erofs:
            res = subprocess.run(
                ["fsck.erofs", f"--extract={tree}", str(img)],
                capture_output=True, text=True)
            if res.returncode != 0:
                sys.exit(f"fsck.erofs failed on {img}:\n{res.stderr}")
        else:
            # mtools needs no root and no loop devices.  -s recurse,
            # -p preserve attributes, -n overwrite silently, -Q quit on
            # the first error so a truncated image cannot half-stage.
            res = subprocess.run(
                ["mcopy", "-i", str(img), "-spnQ", "::", str(tree)],
                capture_output=True, text=True)
            if res.returncode != 0:
                sys.exit(f"mcopy failed on {img} (is mtools installed, and "
                         f"is this really a vfat image?):\n{res.stderr}")
        trees[image] = tree
    return trees


def pil_join(mdt: Path) -> bytes:
    """Join Qualcomm split firmware (.mdt + .bNN) into one ELF, as
    pil-squasher does: the mdt supplies the ELF and program headers, and
    each program header's file content comes from its .bNN sibling when
    one exists.  The manifest hash of the joined output is the oracle
    that this reimplementation stays byte-exact."""
    data = mdt.read_bytes()
    if data[:4] != b"\x7fELF":
        sys.exit(f"{mdt}: not an ELF")
    is64 = data[4] == 2
    if is64:
        phoff = int.from_bytes(data[0x20:0x28], "little")
        phentsize = int.from_bytes(data[0x36:0x38], "little")
        phnum = int.from_bytes(data[0x38:0x3A], "little")
    else:
        phoff = int.from_bytes(data[0x1C:0x20], "little")
        phentsize = int.from_bytes(data[0x2A:0x2C], "little")
        phnum = int.from_bytes(data[0x2C:0x2E], "little")
    out = bytearray(data)
    base = str(mdt)[:-len(".mdt")]
    for i in range(phnum):
        ph = data[phoff + i * phentsize:][:phentsize]
        if is64:
            p_offset = int.from_bytes(ph[8:16], "little")
            p_filesz = int.from_bytes(ph[0x20:0x28], "little")
        else:
            p_offset = int.from_bytes(ph[4:8], "little")
            p_filesz = int.from_bytes(ph[16:20], "little")
        if p_filesz == 0:
            continue
        seg = Path(f"{base}.b{i:02d}")
        if not seg.is_file():
            continue
        content = seg.read_bytes()
        end = p_offset + len(content)
        if end > len(out):
            out.extend(b"\0" * (end - len(out)))
        out[p_offset:end] = content
    return bytes(out)


def build_output(entry: dict, tree: Path) -> bytes:
    """Produce the destination bytes for one manifest entry: the source
    file with its declared transform applied."""
    src = tree / entry["source"]
    if not src.is_file():
        sys.exit(f"{entry['dest']}: source missing: "
                 f"{entry['image']}:{entry['source']}")
    transform = entry.get("transform")
    if transform is None:
        return src.read_bytes()
    if transform == "fwup-strip-80-128":
        data = src.read_bytes()
        if len(data) <= 208:
            sys.exit(f"{entry['dest']}: too small for fwup-strip-80-128")
        return data[80:-128]
    if transform == "pil-join":
        return pil_join(src)
    sys.exit(f"{entry['dest']}: unknown transform '{transform}'")


def cmd_record(args):
    manifest_path = Path(args.manifest)
    manifest = load_manifest(manifest_path)
    with tempfile.TemporaryDirectory(prefix="fw-record.") as scratch:
        trees = extract_images(manifest, Path(args.stock), Path(scratch))
        missing = []
        for entry in manifest.get("file", []):
            src = trees[entry["image"]] / entry["source"]
            if src.is_file():
                data = build_output(entry, trees[entry["image"]])
                entry["sha256"] = hashlib.sha256(data).hexdigest()
                print(f"measured {entry['dest']}: {entry['sha256']}")
            else:
                missing.append(entry)
                print(f"NOT FOUND {entry['dest']}: "
                      f"{entry['image']}:{entry['source']}", file=sys.stderr)
    out = Path(args.write) if args.write else manifest_path
    # tomllib has no writer; emit the subset we use, deterministically.
    lines = [f"# recorded by {TOOL} on "
             f"{datetime.now(timezone.utc).isoformat(timespec='seconds')}",
             f"# from stock staging: {args.stock}", ""]
    for entry in manifest.get("file", []):
        lines.append("[[file]]")
        for key in ("dest", "image", "source", "sha256", "note"):
            if key in entry:
                lines.append(f'{key} = "{entry[key]}"')
        lines.append("")
    out.write_text("\n".join(lines))
    print(f"wrote {out}")
    if missing:
        print(f"{len(missing)} entry/entries had no source in this package;",
              "fix their 'source' paths (find the real ones with e.g.",
              "`find <tree> -name '*.mbn'`) and record again.",
              file=sys.stderr)
        sys.exit(1)


def cmd_stage(args):
    manifest = load_manifest(Path(args.manifest))
    out = Path(args.out)
    if out.exists():
        shutil.rmtree(out)
    staged = []
    with tempfile.TemporaryDirectory(prefix="fw-stage.") as scratch:
        trees = extract_images(manifest, Path(args.stock), Path(scratch))
        for entry in manifest.get("file", []):
            if "sha256" not in entry:
                sys.exit(f"{entry['dest']}: no pinned hash in the manifest; "
                         "run `record` first and commit the result")
            data = build_output(entry, trees[entry["image"]])
            measured = hashlib.sha256(data).hexdigest()
            if measured != entry["sha256"]:
                sys.exit(f"{entry['dest']}: hash mismatch after "
                         f"'{entry.get('transform', 'byte copy')}'\n"
                         f"  manifest {entry['sha256']}\n"
                         f"  built    {measured}\n"
                         "either a different firmware build (re-record "
                         "deliberately / stage the matching OTA) or a "
                         "transform defect — nothing is staged either way")
            dest = out / "lib/firmware" / entry["dest"]
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(data)
            dest.chmod(0o644)
            staged.append({"dest": entry["dest"], "sha256": measured})
            print(f"staged {entry['dest']}")

    provenance_src = Path(args.stock) / "PROVENANCE.json"
    stock_prov = (json.loads(provenance_src.read_text())
                  if provenance_src.is_file() else {})
    (out / "PROVENANCE.json").write_text(json.dumps({
        "tool": TOOL,
        "manifest": str(args.manifest),
        "stock_post_build": stock_prov.get("post_build"),
        "stock_product": stock_prov.get("product"),
        "staged": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "files": staged,
    }, indent=2) + "\n")
    print(f"=== {len(staged)} files staged into {out} ===")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("stage", help="verify and copy into an overlay tree")
    p.add_argument("--manifest", required=True)
    p.add_argument("--stock", required=True,
                   help="a stage-stock-images.sh output directory")
    p.add_argument("--out", required=True)
    p.set_defaults(func=cmd_stage)
    p = sub.add_parser("record", help="measure hashes from a stock package")
    p.add_argument("--manifest", required=True)
    p.add_argument("--stock", required=True)
    p.add_argument("--write", help="write to this file instead of in place")
    p.set_defaults(func=cmd_record)
    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
