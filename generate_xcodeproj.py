#!/usr/bin/env python3
"""Generates Yuki.xcodeproj.

The app target only compiles YukiApp/ and links the StoatUI product from the local
Swift package in this directory, so new files under Sources/ never require
regenerating the project. Object IDs are derived from stable names, so running
this script again produces an identical file.
"""
import hashlib
import os

BUNDLE_ID = "chat.yuki.ios"
DEPLOYMENT_TARGET = "17.0"
MARKETING_VERSION = "1.1"
BUILD_NUMBER = "2"


def oid(name):
    return hashlib.md5(name.encode()).hexdigest()[:24].upper()


def main():
    base_dir = os.path.dirname(os.path.abspath(__file__))
    project_dir = os.path.join(base_dir, "Yuki.xcodeproj")
    os.makedirs(project_dir, exist_ok=True)

    app_sources = sorted(
        f for f in os.listdir(os.path.join(base_dir, "YukiApp")) if f.endswith(".swift")
    )

    ids = {name: oid(name) for name in [
        "project", "target", "mainGroup", "appGroup", "productsGroup", "frameworksGroup",
        "sourcesPhase", "frameworksPhase", "resourcesPhase", "product",
        "assetsRef", "assetsBuild", "infoPlistRef",
        "projectDebug", "projectRelease", "projectConfigList",
        "targetDebug", "targetRelease", "targetConfigList",
        "packageRef", "stoatUIDependency", "stoatUIBuild",
    ]}

    lines = []
    w = lines.append

    w("// !$*UTF8*$!")
    w("{")
    w("\tarchiveVersion = 1;")
    w("\tclasses = {")
    w("\t};")
    w("\tobjectVersion = 70;")
    w("\tobjects = {")
    w("")

    w("/* Begin PBXBuildFile section */")
    for source in app_sources:
        w(f"\t\t{oid('build:' + source)} /* {source} in Sources */ = {{isa = PBXBuildFile; fileRef = {oid('ref:' + source)} /* {source} */; }};")
    w(f"\t\t{ids['assetsBuild']} /* Assets.xcassets in Resources */ = {{isa = PBXBuildFile; fileRef = {ids['assetsRef']} /* Assets.xcassets */; }};")
    w(f"\t\t{ids['stoatUIBuild']} /* StoatUI in Frameworks */ = {{isa = PBXBuildFile; productRef = {ids['stoatUIDependency']} /* StoatUI */; }};")
    w("/* End PBXBuildFile section */")
    w("")

    w("/* Begin PBXFileReference section */")
    w(f"\t\t{ids['product']} /* Yuki.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Yuki.app; sourceTree = BUILT_PRODUCTS_DIR; }};")
    for source in app_sources:
        w(f"\t\t{oid('ref:' + source)} /* {source} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {source}; sourceTree = \"<group>\"; }};")
    w(f"\t\t{ids['assetsRef']} /* Assets.xcassets */ = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = \"<group>\"; }};")
    w(f"\t\t{ids['infoPlistRef']} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = \"<group>\"; }};")
    w("/* End PBXFileReference section */")
    w("")

    w("/* Begin PBXFrameworksBuildPhase section */")
    w(f"\t\t{ids['frameworksPhase']} /* Frameworks */ = {{")
    w("\t\t\tisa = PBXFrameworksBuildPhase;")
    w("\t\t\tbuildActionMask = 2147483647;")
    w("\t\t\tfiles = (")
    w(f"\t\t\t\t{ids['stoatUIBuild']} /* StoatUI in Frameworks */,")
    w("\t\t\t);")
    w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    w("\t\t};")
    w("/* End PBXFrameworksBuildPhase section */")
    w("")

    w("/* Begin PBXGroup section */")
    w(f"\t\t{ids['mainGroup']} = {{")
    w("\t\t\tisa = PBXGroup;")
    w("\t\t\tchildren = (")
    w(f"\t\t\t\t{ids['appGroup']} /* YukiApp */,")
    w(f"\t\t\t\t{ids['frameworksGroup']} /* Frameworks */,")
    w(f"\t\t\t\t{ids['productsGroup']} /* Products */,")
    w("\t\t\t);")
    w("\t\t\tsourceTree = \"<group>\";")
    w("\t\t};")
    w(f"\t\t{ids['appGroup']} /* YukiApp */ = {{")
    w("\t\t\tisa = PBXGroup;")
    w("\t\t\tchildren = (")
    for source in app_sources:
        w(f"\t\t\t\t{oid('ref:' + source)} /* {source} */,")
    w(f"\t\t\t\t{ids['assetsRef']} /* Assets.xcassets */,")
    w(f"\t\t\t\t{ids['infoPlistRef']} /* Info.plist */,")
    w("\t\t\t);")
    w("\t\t\tpath = YukiApp;")
    w("\t\t\tsourceTree = \"<group>\";")
    w("\t\t};")
    w(f"\t\t{ids['frameworksGroup']} /* Frameworks */ = {{")
    w("\t\t\tisa = PBXGroup;")
    w("\t\t\tchildren = (")
    w("\t\t\t);")
    w("\t\t\tname = Frameworks;")
    w("\t\t\tsourceTree = \"<group>\";")
    w("\t\t};")
    w(f"\t\t{ids['productsGroup']} /* Products */ = {{")
    w("\t\t\tisa = PBXGroup;")
    w("\t\t\tchildren = (")
    w(f"\t\t\t\t{ids['product']} /* Yuki.app */,")
    w("\t\t\t);")
    w("\t\t\tname = Products;")
    w("\t\t\tsourceTree = \"<group>\";")
    w("\t\t};")
    w("/* End PBXGroup section */")
    w("")

    w("/* Begin PBXNativeTarget section */")
    w(f"\t\t{ids['target']} /* Yuki */ = {{")
    w("\t\t\tisa = PBXNativeTarget;")
    w(f"\t\t\tbuildConfigurationList = {ids['targetConfigList']} /* Build configuration list for PBXNativeTarget \"Yuki\" */;")
    w("\t\t\tbuildPhases = (")
    w(f"\t\t\t\t{ids['sourcesPhase']} /* Sources */,")
    w(f"\t\t\t\t{ids['frameworksPhase']} /* Frameworks */,")
    w(f"\t\t\t\t{ids['resourcesPhase']} /* Resources */,")
    w("\t\t\t);")
    w("\t\t\tbuildRules = (")
    w("\t\t\t);")
    w("\t\t\tdependencies = (")
    w("\t\t\t);")
    w("\t\t\tname = Yuki;")
    w("\t\t\tpackageProductDependencies = (")
    w(f"\t\t\t\t{ids['stoatUIDependency']} /* StoatUI */,")
    w("\t\t\t);")
    w("\t\t\tproductName = Yuki;")
    w(f"\t\t\tproductReference = {ids['product']} /* Yuki.app */;")
    w("\t\t\tproductType = \"com.apple.product-type.application\";")
    w("\t\t};")
    w("/* End PBXNativeTarget section */")
    w("")

    w("/* Begin PBXProject section */")
    w(f"\t\t{ids['project']} /* Project object */ = {{")
    w("\t\t\tisa = PBXProject;")
    w("\t\t\tattributes = {")
    w("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
    w("\t\t\t\tLastSwiftUpdateCheck = 2600;")
    w("\t\t\t\tLastUpgradeCheck = 2600;")
    w("\t\t\t};")
    w(f"\t\t\tbuildConfigurationList = {ids['projectConfigList']} /* Build configuration list for PBXProject \"Yuki\" */;")
    w("\t\t\tdevelopmentRegion = en;")
    w("\t\t\thasScannedForEncodings = 0;")
    w("\t\t\tknownRegions = (")
    w("\t\t\t\ten,")
    w("\t\t\t\tBase,")
    w("\t\t\t);")
    w(f"\t\t\tmainGroup = {ids['mainGroup']};")
    w("\t\t\tminimizedProjectReferenceProxies = 1;")
    w("\t\t\tpackageReferences = (")
    w(f"\t\t\t\t{ids['packageRef']} /* XCLocalSwiftPackageReference \".\" */,")
    w("\t\t\t);")
    w("\t\t\tpreferredProjectObjectVersion = 70;")
    w(f"\t\t\tproductRefGroup = {ids['productsGroup']} /* Products */;")
    w("\t\t\tprojectDirPath = \"\";")
    w("\t\t\tprojectRoot = \"\";")
    w("\t\t\ttargets = (")
    w(f"\t\t\t\t{ids['target']} /* Yuki */,")
    w("\t\t\t);")
    w("\t\t};")
    w("/* End PBXProject section */")
    w("")

    w("/* Begin PBXResourcesBuildPhase section */")
    w(f"\t\t{ids['resourcesPhase']} /* Resources */ = {{")
    w("\t\t\tisa = PBXResourcesBuildPhase;")
    w("\t\t\tbuildActionMask = 2147483647;")
    w("\t\t\tfiles = (")
    w(f"\t\t\t\t{ids['assetsBuild']} /* Assets.xcassets in Resources */,")
    w("\t\t\t);")
    w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    w("\t\t};")
    w("/* End PBXResourcesBuildPhase section */")
    w("")

    w("/* Begin PBXSourcesBuildPhase section */")
    w(f"\t\t{ids['sourcesPhase']} /* Sources */ = {{")
    w("\t\t\tisa = PBXSourcesBuildPhase;")
    w("\t\t\tbuildActionMask = 2147483647;")
    w("\t\t\tfiles = (")
    for source in app_sources:
        w(f"\t\t\t\t{oid('build:' + source)} /* {source} in Sources */,")
    w("\t\t\t);")
    w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    w("\t\t};")
    w("/* End PBXSourcesBuildPhase section */")
    w("")

    common_project = [
        "ALWAYS_SEARCH_USER_PATHS = NO;",
        "CLANG_ENABLE_MODULES = YES;",
        "CLANG_ENABLE_OBJC_ARC = YES;",
        f"IPHONEOS_DEPLOYMENT_TARGET = {DEPLOYMENT_TARGET};",
        "SDKROOT = iphoneos;",
        "SWIFT_VERSION = 6.0;",
    ]
    target_settings = [
        "ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;",
        "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;",
        "CODE_SIGN_STYLE = Automatic;",
        f"CURRENT_PROJECT_VERSION = {BUILD_NUMBER};",
        "ENABLE_PREVIEWS = YES;",
        "GENERATE_INFOPLIST_FILE = YES;",
        "INFOPLIST_FILE = YukiApp/Info.plist;",
        "INFOPLIST_KEY_CFBundleDisplayName = Yuki;",
        "INFOPLIST_KEY_LSApplicationCategoryType = \"public.app-category.social-networking\";",
        "INFOPLIST_KEY_NSCameraUsageDescription = \"Yuki uses your camera when you turn it on in a call.\";",
        "INFOPLIST_KEY_NSMicrophoneUsageDescription = \"Yuki uses your microphone for voice calls and voice messages.\";",
        "INFOPLIST_KEY_NSPhotoLibraryAddUsageDescription = \"Yuki saves images you choose to your photo library.\";",
        "INFOPLIST_KEY_NSPhotoLibraryUsageDescription = \"Yuki lets you choose photos and videos to send.\";",
        "INFOPLIST_KEY_NSSpeechRecognitionUsageDescription = \"Yuki turns voice messages into text on your device when you ask it to.\";",
        "INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;",
        "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad = \"UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight\";",
        "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = \"UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight\";",
        # LiveKit's WebRTC framework is dynamic and embedded in the app's Frameworks folder.
        "LD_RUNPATH_SEARCH_PATHS = \"$(inherited) @executable_path/Frameworks\";",
        f"MARKETING_VERSION = {MARKETING_VERSION};",
        f"PRODUCT_BUNDLE_IDENTIFIER = {BUNDLE_ID};",
        "PRODUCT_NAME = \"$(TARGET_NAME)\";",
        "SUPPORTED_PLATFORMS = \"iphoneos iphonesimulator\";",
        "SUPPORTS_MACCATALYST = NO;",
        "SWIFT_EMIT_LOC_STRINGS = YES;",
        "SWIFT_VERSION = 6.0;",
        "TARGETED_DEVICE_FAMILY = \"1,2\";",
    ]

    def config(obj_id, name, settings):
        w(f"\t\t{obj_id} /* {name} */ = {{")
        w("\t\t\tisa = XCBuildConfiguration;")
        w("\t\t\tbuildSettings = {")
        for setting in settings:
            w(f"\t\t\t\t{setting}")
        w("\t\t\t};")
        w(f"\t\t\tname = {name};")
        w("\t\t};")

    w("/* Begin XCBuildConfiguration section */")
    config(ids["projectDebug"], "Debug", common_project + [
        "DEBUG_INFORMATION_FORMAT = dwarf;",
        "ENABLE_TESTABILITY = YES;",
        "ONLY_ACTIVE_ARCH = YES;",
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS = \"DEBUG $(inherited)\";",
        "SWIFT_OPTIMIZATION_LEVEL = \"-Onone\";",
    ])
    config(ids["projectRelease"], "Release", common_project + [
        "DEBUG_INFORMATION_FORMAT = \"dwarf-with-dsym\";",
        "SWIFT_COMPILATION_MODE = wholemodule;",
        "VALIDATE_PRODUCT = YES;",
    ])
    config(ids["targetDebug"], "Debug", target_settings)
    config(ids["targetRelease"], "Release", target_settings)
    w("/* End XCBuildConfiguration section */")
    w("")

    w("/* Begin XCConfigurationList section */")
    for list_id, name, debug, release in [
        (ids["projectConfigList"], "PBXProject \"Yuki\"", ids["projectDebug"], ids["projectRelease"]),
        (ids["targetConfigList"], "PBXNativeTarget \"Yuki\"", ids["targetDebug"], ids["targetRelease"]),
    ]:
        w(f"\t\t{list_id} /* Build configuration list for {name} */ = {{")
        w("\t\t\tisa = XCConfigurationList;")
        w("\t\t\tbuildConfigurations = (")
        w(f"\t\t\t\t{debug} /* Debug */,")
        w(f"\t\t\t\t{release} /* Release */,")
        w("\t\t\t);")
        w("\t\t\tdefaultConfigurationIsVisible = 0;")
        w("\t\t\tdefaultConfigurationName = Release;")
        w("\t\t};")
    w("/* End XCConfigurationList section */")
    w("")

    w("/* Begin XCLocalSwiftPackageReference section */")
    w(f"\t\t{ids['packageRef']} /* XCLocalSwiftPackageReference \".\" */ = {{")
    w("\t\t\tisa = XCLocalSwiftPackageReference;")
    w("\t\t\trelativePath = .;")
    w("\t\t};")
    w("/* End XCLocalSwiftPackageReference section */")
    w("")

    w("/* Begin XCSwiftPackageProductDependency section */")
    w(f"\t\t{ids['stoatUIDependency']} /* StoatUI */ = {{")
    w("\t\t\tisa = XCSwiftPackageProductDependency;")
    w("\t\t\tproductName = StoatUI;")
    w("\t\t};")
    w("/* End XCSwiftPackageProductDependency section */")

    w("\t};")
    w(f"\trootObject = {ids['project']} /* Project object */;")
    w("}")

    with open(os.path.join(project_dir, "project.pbxproj"), "w") as handle:
        handle.write("\n".join(lines) + "\n")

    write_scheme(project_dir, ids)
    print(f"Generated Yuki.xcodeproj with {len(app_sources)} app source file(s).")


def write_scheme(project_dir, ids):
    """Shared scheme for building and running the app. Package tests run via scripts/test.sh."""
    app_ref = (
        f'<BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{ids["target"]}" '
        'BuildableName = "Yuki.app" BlueprintName = "Yuki" ReferencedContainer = "container:Yuki.xcodeproj">'
        "</BuildableReference>"
    )

    scheme = f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "2600" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            {app_ref}
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
      </Testables>
   </TestAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         {app_ref}
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         {app_ref}
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug"></AnalyzeAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES"></ArchiveAction>
</Scheme>
"""
    scheme_dir = os.path.join(project_dir, "xcshareddata", "xcschemes")
    os.makedirs(scheme_dir, exist_ok=True)
    with open(os.path.join(scheme_dir, "Yuki.xcscheme"), "w") as handle:
        handle.write(scheme)


if __name__ == "__main__":
    main()
