#!/usr/bin/env python3
import plistlib
import sys
import zipfile

def verify(path):
    with zipfile.ZipFile(path) as archive:
        bad = archive.testzip()
        if bad:
            raise ValueError(f"Corrupt member: {bad}")
        prefix = "Payload/M8TPGTAMap.app/"
        plist = plistlib.loads(archive.read(prefix + "Info.plist"))
        if plist.get("CFBundleSupportedPlatforms") != ["iPhoneOS"]:
            raise ValueError("This is not an iPhoneOS app.")
        if plist.get("CFBundlePackageType") != "APPL":
            raise ValueError("Unexpected bundle type")
        executable = archive.read(prefix + plist["CFBundleExecutable"])
        # Little endian 64-bit Mach-O or universal Mach-O. Simulator check is done by vtool in build script.
        if executable[:4] not in (b"\xcf\xfa\xed\xfe", b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca"):
            raise ValueError("Executable is not a Mach-O binary")
        for resource in ["catalog.json", "demo.json", "GTAVAtlas.jpg", "GTAVCommunity.jpg", "PrivacyInfo.xcprivacy"]:
            archive.getinfo(prefix + resource)
        print(f"IPA structure verified: {plist['CFBundleIdentifier']}, iPhoneOS, {len(executable):,} executable bytes")

if __name__ == "__main__":
    verify(sys.argv[1])
