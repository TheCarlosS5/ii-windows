"""crash-locate: where in an exe WITHOUT a PDB did a crash happen?

Finds the function (via the x64 .pdata exception table) that contains an RVA of a PE64, disassembles it
with llvm-objdump (the one in VS Build Tools' LLVM), and annotates calls through the import table with
their names and rip-relative references with the strings they point to. Used on 2026-10-31 to place the
0.6.0 crash (quickshell.exe+0x19ed74) in mpris.cpp; see ../01-fallo-principal.md.

usage: python -I crash-locate.py <exe> <rva-hex>      e.g.  python -I crash-locate.py quickshell.exe 19ed74
The offset is the "Desplazamiento con errores" of Event Viewer's Application Error (event 1000).
Proposed home once adopted: tools/dev/crash-locate.py.
"""
import re
import struct
import subprocess
import sys

LLVM = r"C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Tools\Llvm\x64\bin"


def load(path):
    data = open(path, "rb").read()
    pe = struct.unpack_from("<I", data, 0x3C)[0]
    nsec = struct.unpack_from("<H", data, pe + 6)[0]
    optsize = struct.unpack_from("<H", data, pe + 20)[0]
    opt = pe + 24
    image_base = struct.unpack_from("<Q", data, opt + 24)[0]
    ndirs = struct.unpack_from("<I", data, opt + 108)[0]
    dirs = [struct.unpack_from("<II", data, opt + 112 + 8 * i) for i in range(ndirs)]
    secs = []
    sh = opt + optsize
    for i in range(nsec):
        name = data[sh + 40 * i: sh + 40 * i + 8].rstrip(b"\0").decode()
        vsize, va, rsize, rptr = struct.unpack_from("<IIII", data, sh + 40 * i + 8)
        secs.append((name, va, vsize, rptr, rsize))
    return data, image_base, dirs, secs


def rva2off(secs, rva):
    for name, va, vsize, rptr, rsize in secs:
        if va <= rva < va + max(vsize, rsize):
            return rptr + (rva - va)
    return None


def imports(data, dirs, secs):
    """IAT rva -> 'dll!name'"""
    out = {}
    rva, size = dirs[1]
    off = rva2off(secs, rva)
    while True:
        oft, _, _, name_rva, ft = struct.unpack_from("<IIIII", data, off)
        if oft == 0 and ft == 0:
            break
        dll = data[rva2off(secs, name_rva):].split(b"\0", 1)[0].decode()
        thunk = oft or ft
        i = 0
        while True:
            entry = struct.unpack_from("<Q", data, rva2off(secs, thunk) + 8 * i)[0]
            if entry == 0:
                break
            if entry & (1 << 63):
                nm = f"#{entry & 0xFFFF}"
            else:
                nm = data[rva2off(secs, entry & 0x7FFFFFFF) + 2:].split(b"\0", 1)[0].decode()
            out[ft + 8 * i] = f"{dll}!{nm}"
            i += 1
        off += 20
    return out


def pdata(data, dirs, secs):
    rva, size = dirs[3]
    off = rva2off(secs, rva)
    funcs = []
    for i in range(size // 12):
        b, e, u = struct.unpack_from("<III", data, off + 12 * i)
        funcs.append((b, e, u))
    return funcs


def string_at(data, secs, rva):
    off = rva2off(secs, rva)
    if off is None:
        return None
    raw = data[off: off + 200]
    # utf-16?
    if len(raw) > 4 and raw[1] == 0 and raw[3] == 0 and 32 <= raw[0] < 127:
        s = raw.decode("utf-16-le", "ignore").split("\0", 1)[0]
        if len(s) >= 3:
            return 'u"' + s + '"'
    s = raw.split(b"\0", 1)[0]
    if len(s) >= 4 and all(32 <= c < 127 or c in (9, 10) for c in s):
        return '"' + s.decode() + '"'
    return None


def main():
    exe = sys.argv[1]
    target = int(sys.argv[2], 16)
    data, base, dirs, secs = load(exe)
    iat = imports(data, dirs, secs)
    funcs = pdata(data, dirs, secs)
    hit = [f for f in funcs if f[0] <= target < f[1]]
    if not hit:
        print("no pdata entry contains", hex(target))
        return
    b, e, u = hit[0]
    # chained unwind info: walk back to the primary function start
    print(f"pdata: begin {b:#x} end {e:#x} unwind {u:#x}  (crash at +{target - b:#x})")
    # gather all pdata chunks belonging to the same function (chained entries) - just print neighbours
    idx = funcs.index(hit[0])
    for f in funcs[max(0, idx - 2): idx + 3]:
        print(f"   chunk {f[0]:#x}-{f[1]:#x} unwind {f[2]:#x}")
    out = subprocess.run([LLVM + r"\llvm-objdump.exe", "-d", "--no-show-raw-insn", f"--start-address={base + b:#x}",
                          f"--stop-address={base + e:#x}", exe], capture_output=True, text=True).stdout
    for line in out.splitlines():
        m = re.match(r"\s*([0-9a-f]+):\s+(.*)", line)
        if not m:
            continue
        addr = int(m.group(1), 16)
        ins = m.group(2)
        note = ""
        # Intel syntax "[rip + 0x..] # 0x..." or AT&T syntax "0x..(%rip) # 0x..": the comment is the absolute target.
        r = re.search(r"(?:\[rip \+ 0x[0-9a-f]+\]|\(%rip\))[^#]*#\s*0x([0-9a-f]+)", ins)
        if r:
            ref = int(r.group(1), 16) - base
            if ref in iat:
                note = "  ; " + iat[ref]
            else:
                s = string_at(data, secs, ref)
                if s:
                    note = "  ; " + s[:120]
        r2 = re.search(r"call\s+0x([0-9a-f]+)", ins)
        if r2:
            tgt = int(r2.group(1), 16) - base
            # call to a thunk "jmp [rip+X]" ?
            off = rva2off(secs, tgt)
            if off is not None and data[off:off + 2] == b"\xff\x25":
                disp = struct.unpack_from("<i", data, off + 2)[0]
                ref = tgt + 6 + disp
                if ref in iat:
                    note = "  ; thunk " + iat[ref]
            else:
                note = f"  ; fn rva {tgt:#x}"
        mark = "  <<<<<<<< CRASH" if addr - base == target else ""
        print(f"{addr - base:08x}: {ins}{note}{mark}")


if __name__ == "__main__":
    main()
