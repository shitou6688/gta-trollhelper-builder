#!/usr/bin/env python3
"""Generate OTA metadata for IPA files (META-INF + iTunesMetadata.plist)"""
import plistlib, sys, os

def generate_ota_metadata(output_dir, bundle_id, display_name, version="1"):
    """Generate META-INF and iTunesMetadata.plist in output_dir"""
    
    # META-INF directory
    meta_dir = os.path.join(output_dir, 'META-INF')
    os.makedirs(meta_dir, exist_ok=True)
    
    # META-INF/com.apple.ZipMetadata.plist
    zip_meta = {
        'StandardFilePerms': -32348,
        'Version': 2,
        'RecordCount': 100,
        'StandardDirectoryPerms': 16877,
        'CreatorToolCommandLine': '"ditto" "-c" "-k" "." "output.ipa"',
        'CreatorToolUUID': '00000000-0000-0000-0000-000000000000',
        'TotalUncompressedBytes': 50000000,
    }
    zip_meta_path = os.path.join(meta_dir, 'com.apple.ZipMetadata.plist')
    with open(zip_meta_path, 'wb') as f:
        plistlib.dump(zip_meta, f, fmt=plistlib.FMT_BINARY)
    
    # META-INF/com.apple.FixedZipMetadata.bin (fixed 23-byte header)
    # Magic: 'MdFx', version: 1, flags: 0x0010, CRC placeholder
    fixed = bytes.fromhex('4d6446780110000000000000000000000000000000000000')
    fixed_path = os.path.join(meta_dir, 'com.apple.FixedZipMetadata.bin')
    with open(fixed_path, 'wb') as f:
        f.write(fixed)
    
    # iTunesMetadata.plist
    itunes_meta = {
        'apple-id': 'ota@trollstore.local',
        'artistName': 'TrollStore',
        'bundleDisplayName': display_name,
        'bundleShortVersionString': version,
        'bundleVersion': '1',
        'copyright': 'TrollStore OTA',
        'drmVersionNumber': 0,
        'fileExtension': '.app',
        'gameCenterEnabled': False,
        'gameCenterEverEnabled': False,
        'genre': 'Utilities',
        'genreId': 6002,
        'hasOrEverHasHadIAP': False,
        'itemId': 1,
        'itemName': display_name,
        'kind': 'software',
        'playlistName': 'TrollStore',
        'product-type': 'ios-app',
        'rating': {
            'content': '',
            'label': '4+',
            'rank': 100,
            'system': 'itunes-games',
        },
        'releaseDate': '2024-01-01T00:00:00Z',
        'requiresRosetta': False,
        'runsOnAppleSilicon': True,
        'runsOnIntel': False,
        's': 0,
        'software-platform': 'ios',
        'softwareIconNeedsShine': False,
        'softwareSupportedDeviceIds': [9, 2, 4, 13],
        'softwareVersionBundleId': bundle_id,
        'softwareVersionExternalIdentifier': 1,
        'softwareVersionExternalIdentifiers': [1],
        'userName': 'ota@trollstore.local',
        'vendorId': 1,
        'versionRestrictions': 0,
        'UIRequiredDeviceCapabilities': {},
    }
    itunes_path = os.path.join(output_dir, 'iTunesMetadata.plist')
    with open(itunes_path, 'wb') as f:
        plistlib.dump(itunes_meta, f, fmt=plistlib.FMT_BINARY)
    
    print(f"Generated OTA metadata for: {bundle_id} ({display_name})")
    print(f"  {meta_dir}/")
    print(f"  {itunes_path}")

if __name__ == '__main__':
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <output_dir> <bundle_id> [display_name] [version]")
        sys.exit(1)
    output_dir = sys.argv[1]
    bundle_id = sys.argv[2]
    display_name = sys.argv[3] if len(sys.argv) > 3 else bundle_id.split('.')[-1]
    version = sys.argv[4] if len(sys.argv) > 4 else '1'
    generate_ota_metadata(output_dir, bundle_id, display_name, version)
