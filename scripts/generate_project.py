#!/usr/bin/env python3
"""Generate the checked-in Xcode project; no XcodeGen or package dependencies."""
import hashlib
import json
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "M8TPGTAMap.xcodeproj"

def identifier(name):
    return hashlib.sha256(name.encode()).hexdigest()[:24].upper()

def render(value, depth=0):
    indent = "\t" * depth
    if isinstance(value, dict):
        return "{\n" + "".join("\t" * (depth + 1) + json.dumps(str(k)) + " = " + render(v, depth + 1) + ";\n" for k, v in value.items()) + indent + "}"
    if isinstance(value, list):
        return "(\n" + "".join("\t" * (depth + 1) + render(v, depth + 1) + ",\n" for v in value) + indent + ")"
    if isinstance(value, int): return str(value)
    return json.dumps(value)

def main():
    objects = {}
    def add(key, **fields):
        ref = identifier(key); objects[ref] = fields; return ref
    sources = sorted((ROOT / "M8TPGTAMap/Sources").glob("*.swift"))
    resources = [ROOT / "M8TPGTAMap/Resources" / name for name in
                 ["Assets.xcassets", "GTAVAtlas.jpg", "GTAVCommunity.jpg", "MapLicense.txt", "catalog.json", "legacy-catalog.json", "demo.json", "PrivacyInfo.xcprivacy"]]
    source_refs, source_builds = [], []
    resource_refs, resource_builds = [], []
    for file in sources + resources:
        type_name = {".swift":"sourcecode.swift", ".xcassets":"folder.assetcatalog", ".jpg":"image.jpeg",
                     ".txt":"text", ".json":"text.json", ".xcprivacy":"text.xml"}[file.suffix]
        ref = add("file:" + file.name, isa="PBXFileReference", lastKnownFileType=type_name,
                  path=file.name, sourceTree="<group>")
        build = add("build:" + file.name, isa="PBXBuildFile", fileRef=ref)
        (source_refs if file in sources else resource_refs).append(ref)
        (source_builds if file in sources else resource_builds).append(build)
    source_group = add("sources", isa="PBXGroup", children=source_refs, path="Sources", sourceTree="<group>")
    resource_group = add("resources", isa="PBXGroup", children=resource_refs, path="Resources", sourceTree="<group>")
    info = add("info", isa="PBXFileReference", lastKnownFileType="text.plist.xml", path="Info.plist", sourceTree="<group>")
    app_group = add("app-group", isa="PBXGroup", children=[source_group, resource_group, info], path="M8TPGTAMap", sourceTree="<group>")
    product = add("product", isa="PBXFileReference", explicitFileType="wrapper.application", includeInIndex=0,
                  path="M8TPGTAMap.app", sourceTree="BUILT_PRODUCTS_DIR")
    products = add("products", isa="PBXGroup", children=[product], name="Products", sourceTree="<group>")
    main_group = add("main-group", isa="PBXGroup", children=[app_group, products], sourceTree="<group>")
    source_phase = add("sources-phase", isa="PBXSourcesBuildPhase", buildActionMask=2147483647, files=source_builds, runOnlyForDeploymentPostprocessing=0)
    resource_phase = add("resources-phase", isa="PBXResourcesBuildPhase", buildActionMask=2147483647, files=resource_builds, runOnlyForDeploymentPostprocessing=0)
    frameworks_phase = add("frameworks-phase", isa="PBXFrameworksBuildPhase", buildActionMask=2147483647, files=[], runOnlyForDeploymentPostprocessing=0)
    project_configs, target_configs = [], []
    for config in ["Debug", "Release"]:
        project_settings = {"ALWAYS_SEARCH_USER_PATHS":"NO", "CLANG_ENABLE_MODULES":"YES", "CLANG_ENABLE_OBJC_ARC":"YES",
                            "IPHONEOS_DEPLOYMENT_TARGET":"17.0", "SDKROOT":"iphoneos", "SWIFT_VERSION":"5.0",
                            "ENABLE_USER_SCRIPT_SANDBOXING":"YES", "DEBUG_INFORMATION_FORMAT":"dwarf" if config == "Debug" else "dwarf-with-dsym"}
        target_settings = {"ASSETCATALOG_COMPILER_APPICON_NAME":"AppIcon", "CODE_SIGN_STYLE":"Automatic",
                           "CURRENT_PROJECT_VERSION":"2", "MARKETING_VERSION":"2.0", "GENERATE_INFOPLIST_FILE":"NO",
                           "INFOPLIST_FILE":"M8TPGTAMap/Info.plist", "PRODUCT_BUNDLE_IDENTIFIER":"com.m8tp.gtamap",
                           "PRODUCT_NAME":"$(TARGET_NAME)", "SUPPORTED_PLATFORMS":"iphoneos iphonesimulator",
                           "TARGETED_DEVICE_FAMILY":"1,2", "SUPPORTS_MACCATALYST":"NO",
                           "LD_RUNPATH_SEARCH_PATHS":["$(inherited)","@executable_path/Frameworks"],
                           "SWIFT_OPTIMIZATION_LEVEL":"-Onone" if config == "Debug" else "-O"}
        if config == "Debug": target_settings["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = "DEBUG $(inherited)"
        project_configs.append(add("project-config-" + config, isa="XCBuildConfiguration", buildSettings=project_settings, name=config))
        target_configs.append(add("target-config-" + config, isa="XCBuildConfiguration", buildSettings=target_settings, name=config))
    project_list = add("project-config-list", isa="XCConfigurationList", buildConfigurations=project_configs,
                       defaultConfigurationIsVisible=0, defaultConfigurationName="Release")
    target_list = add("target-config-list", isa="XCConfigurationList", buildConfigurations=target_configs,
                      defaultConfigurationIsVisible=0, defaultConfigurationName="Release")
    target = add("target", isa="PBXNativeTarget", buildConfigurationList=target_list,
                 buildPhases=[source_phase, frameworks_phase, resource_phase], buildRules=[], dependencies=[],
                 name="M8TPGTAMap", productName="M8TPGTAMap", productReference=product, productType="com.apple.product-type.application")
    project = add("project", isa="PBXProject", attributes={"LastUpgradeCheck":"1600", "LastSwiftUpdateCheck":"1600",
                  "TargetAttributes":{target:{"CreatedOnToolsVersion":"16.0"}}}, buildConfigurationList=project_list,
                  compatibilityVersion="Xcode 14.0", developmentRegion="en", hasScannedForEncodings=0,
                  knownRegions=["en", "Base"], mainGroup=main_group, productRefGroup=products, projectDirPath="", projectRoot="", targets=[target])
    PROJECT.mkdir(exist_ok=True)
    document = {"archiveVersion":1, "classes":{}, "objectVersion":56, "objects":objects, "rootObject":project}
    (PROJECT / "project.pbxproj").write_text("// !$*UTF8*$!\n" + render(document) + "\n")
    scheme = ET.Element("Scheme", LastUpgradeVersion="1600", version="1.3")
    build_action = ET.SubElement(scheme, "BuildAction", parallelizeBuildables="YES", buildImplicitDependencies="YES")
    entries = ET.SubElement(build_action, "BuildActionEntries")
    entry = ET.SubElement(entries, "BuildActionEntry", buildForTesting="YES", buildForRunning="YES", buildForProfiling="YES", buildForArchiving="YES", buildForAnalyzing="YES")
    def reference(parent):
        ET.SubElement(parent,"BuildableReference", BuildableIdentifier="primary", BlueprintIdentifier=target,
                      BuildableName="M8TPGTAMap.app", BlueprintName="M8TPGTAMap", ReferencedContainer="container:M8TPGTAMap.xcodeproj")
    reference(entry)
    ET.SubElement(scheme,"TestAction", buildConfiguration="Debug", selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB", selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB", shouldUseLaunchSchemeArgsEnv="YES")
    launch = ET.SubElement(scheme,"LaunchAction", buildConfiguration="Debug", selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB", selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB", launchStyle="0", useCustomWorkingDirectory="NO", ignoresPersistentStateOnLaunch="NO", debugDocumentVersioning="YES", allowLocationSimulation="NO")
    reference(ET.SubElement(launch,"BuildableProductRunnable", runnableDebuggingMode="0"))
    profile = ET.SubElement(scheme,"ProfileAction", buildConfiguration="Release", shouldUseLaunchSchemeArgsEnv="YES", savedToolIdentifier="", useCustomWorkingDirectory="NO", debugDocumentVersioning="YES")
    reference(ET.SubElement(profile,"BuildableProductRunnable", runnableDebuggingMode="0"))
    ET.SubElement(scheme,"AnalyzeAction",buildConfiguration="Debug")
    ET.SubElement(scheme,"ArchiveAction",buildConfiguration="Release",revealArchiveInOrganizer="YES")
    schemes = PROJECT / "xcshareddata/xcschemes"; schemes.mkdir(parents=True,exist_ok=True)
    ET.indent(scheme)
    ET.ElementTree(scheme).write(schemes / "M8TPGTAMap.xcscheme",encoding="UTF-8",xml_declaration=True)
    workspace = PROJECT / "project.xcworkspace"; workspace.mkdir(exist_ok=True)
    (workspace / "contents.xcworkspacedata").write_text('<?xml version="1.0" encoding="UTF-8"?>\n<Workspace version="1.0"><FileRef location="self:"/></Workspace>\n')
    print(f"Xcode project generated: {len(sources)} Swift files, {len(resources)} resource entries.")

if __name__ == "__main__": main()
