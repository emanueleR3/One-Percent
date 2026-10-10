#!/usr/bin/env python3
"""Writes iOS/OnePercentiOS.xcodeproj: the iPhone app and its widget, on the shared OnePercentCore package.

    python3 Scripts/generate-ios-project.py

Sources are picked up from their folders (Xcode "synchronized groups"), so adding a Swift file needs
no change here. Only structure (targets, signing, the App Group, embedding the widget) lives here.
"""
import hashlib, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEAM = "YOUR_TEAM_ID"          # the free Personal Team that signs the apps
APP_ID = "com.example.onepercent"
WIDGET_ID = APP_ID + ".widget"

def oid(name):
    return hashlib.sha1(("onepercent-ios/" + name).encode()).hexdigest()[:24].upper()

I = {k: oid(k) for k in [
    "project", "main", "products", "appRef", "widgetRef",
    "appGroup", "widgetGroup", "sharedGroup",
    "appTarget", "widgetTarget",
    "appSources", "appFrameworks", "appResources", "appScript", "appEmbed",
    "widgetSources", "widgetFrameworks", "widgetResources",
    "coreBuild", "embedBuild", "coreDep", "pkgRef", "proxy", "targetDep",
    "projCfgList", "appCfgList", "widgetCfgList",
    "projDebug", "projRelease", "appDebug", "appRelease", "widgetDebug", "widgetRelease",
]}

def build_settings(d):
    lines = []
    for key in sorted(d):
        value = d[key]
        if isinstance(value, list):
            inner = "".join(f'\t\t\t\t\t"{v}",\n' for v in value)
            lines.append(f"\t\t\t\t{key} = (\n{inner}\t\t\t\t);")
        else:
            text = str(value)
            quoted = text if text.replace("_", "").replace(".", "").replace("/", "").replace("-", "").isalnum() and " " not in text and text else f'"{text}"'
            lines.append(f"\t\t\t\t{key} = {quoted};")
    return "\n".join(lines)

project_common = {
    "ALWAYS_SEARCH_USER_PATHS": "NO", "CLANG_ENABLE_MODULES": "YES", "CLANG_ENABLE_OBJC_ARC": "YES",
    "COPY_PHASE_STRIP": "NO", "ENABLE_STRICT_OBJC_MSGSEND": "YES", "IPHONEOS_DEPLOYMENT_TARGET": "17.0", "SDKROOT": "iphoneos",
}
project_debug = dict(project_common, DEBUG_INFORMATION_FORMAT="dwarf", ENABLE_TESTABILITY="YES", GCC_OPTIMIZATION_LEVEL="0",
                     MTL_ENABLE_DEBUG_INFO="INCLUDE_SOURCE", ONLY_ACTIVE_ARCH="YES",
                     SWIFT_ACTIVE_COMPILATION_CONDITIONS="DEBUG $(inherited)", SWIFT_OPTIMIZATION_LEVEL="-Onone")
project_release = dict(project_common, DEBUG_INFORMATION_FORMAT="dwarf-with-dsym", ENABLE_NS_ASSERTIONS="NO",
                       MTL_ENABLE_DEBUG_INFO="NO", SWIFT_COMPILATION_MODE="wholemodule", VALIDATE_PRODUCT="YES")

app_settings = {
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon", "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
    "CODE_SIGN_ENTITLEMENTS": "Config/OnePercentiOS.entitlements", "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": "1", "DEVELOPMENT_TEAM": TEAM, "ENABLE_PREVIEWS": "YES", "ENABLE_USER_SCRIPT_SANDBOXING": "NO",
    "GENERATE_INFOPLIST_FILE": "YES", "INFOPLIST_FILE": "Config/OnePercentiOS-Info.plist",
    "INFOPLIST_KEY_CFBundleDisplayName": "One Percent", "INFOPLIST_KEY_NSSupportsLiveActivities": "YES",
    "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "YES", "INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents": "YES",
    "INFOPLIST_KEY_UILaunchScreen_Generation": "YES", "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone": "UIInterfaceOrientationPortrait",
    "INFOPLIST_KEY_UIUserInterfaceStyle": "Dark", "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"],
    "MARKETING_VERSION": "0.1.2", "PRODUCT_BUNDLE_IDENTIFIER": APP_ID, "PRODUCT_NAME": "$(TARGET_NAME)",
    "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator", "SUPPORTS_MACCATALYST": "NO", "SWIFT_EMIT_LOC_STRINGS": "YES",
    "SWIFT_VERSION": "5.0", "TARGETED_DEVICE_FAMILY": "1",
}
widget_settings = {
    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor", "ASSETCATALOG_COMPILER_WIDGET_BACKGROUND_COLOR_NAME": "WidgetBackground",
    "CODE_SIGN_ENTITLEMENTS": "Config/OnePercentWidget.entitlements", "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": "1", "DEVELOPMENT_TEAM": TEAM, "GENERATE_INFOPLIST_FILE": "YES",
    "INFOPLIST_FILE": "Config/OnePercentWidget-Info.plist", "INFOPLIST_KEY_CFBundleDisplayName": "One Percent",
    "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks", "@executable_path/../../Frameworks"],
    "MARKETING_VERSION": "0.1.2", "PRODUCT_BUNDLE_IDENTIFIER": WIDGET_ID, "PRODUCT_NAME": "$(TARGET_NAME)",
    "SKIP_INSTALL": "YES", "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator", "SWIFT_EMIT_LOC_STRINGS": "YES",
    "SWIFT_VERSION": "5.0", "TARGETED_DEVICE_FAMILY": "1",
}

def cfg(key, name, settings):
    return f"\t\t{I[key]} /* {name} */ = {{\n\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = {{\n{build_settings(settings)}\n\t\t\t}};\n\t\t\tname = {name};\n\t\t}};\n"

script = ("# The shared Localizer reads <code>.lproj/Localizable.strings from the app bundle.\n"
          "for pack in \"$SRCROOT\"/../Resources/*.lproj; do\n"
          "  rm -rf \"$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/$(basename \"$pack\")\"\n"
          "  cp -R \"$pack\" \"$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/\"\n"
          "done\n").replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")

def sync_group(key, path):
    return f"\t\t{I[key]} /* {path} */ = {{\n\t\t\tisa = PBXFileSystemSynchronizedRootGroup;\n\t\t\tpath = {path};\n\t\t\tsourceTree = \"<group>\";\n\t\t}};\n"

def phase(kind, key, name, files=""):
    return (f"\t\t{I[key]} /* {name} */ = {{\n\t\t\tisa = {kind};\n\t\t\tbuildActionMask = 2147483647;\n"
            f"\t\t\tfiles = (\n{files}\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};\n")

pbx = f"""// !$*UTF8*$!
{{
	archiveVersion = 1;
	classes = {{
	}};
	objectVersion = 77;
	objects = {{

/* Begin PBXBuildFile section */
		{I["coreBuild"]} /* OnePercentCore in Frameworks */ = {{isa = PBXBuildFile; productRef = {I["coreDep"]} /* OnePercentCore */; }};
		{I["embedBuild"]} /* OnePercentWidget.appex in Embed Foundation Extensions */ = {{isa = PBXBuildFile; fileRef = {I["widgetRef"]} /* OnePercentWidget.appex */; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};
/* End PBXBuildFile section */

/* Begin PBXContainerItemProxy section */
		{I["proxy"]} /* PBXContainerItemProxy */ = {{
			isa = PBXContainerItemProxy;
			containerPortal = {I["project"]} /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = {I["widgetTarget"]};
			remoteInfo = OnePercentWidget;
		}};
/* End PBXContainerItemProxy section */

/* Begin PBXCopyFilesBuildPhase section */
		{I["appEmbed"]} /* Embed Foundation Extensions */ = {{
			isa = PBXCopyFilesBuildPhase;
			buildActionMask = 2147483647;
			dstPath = "";
			dstSubfolderSpec = 13;
			files = (
				{I["embedBuild"]} /* OnePercentWidget.appex in Embed Foundation Extensions */,
			);
			name = "Embed Foundation Extensions";
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXCopyFilesBuildPhase section */

/* Begin PBXFileReference section */
		{I["appRef"]} /* OnePercentiOS.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = OnePercentiOS.app; sourceTree = BUILT_PRODUCTS_DIR; }};
		{I["widgetRef"]} /* OnePercentWidget.appex */ = {{isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; includeInIndex = 0; path = OnePercentWidget.appex; sourceTree = BUILT_PRODUCTS_DIR; }};
/* End PBXFileReference section */

/* Begin PBXFileSystemSynchronizedRootGroup section */
{sync_group("appGroup", "OnePercentiOS")}{sync_group("widgetGroup", "OnePercentWidget")}{sync_group("sharedGroup", "Shared")}/* End PBXFileSystemSynchronizedRootGroup section */

/* Begin PBXFrameworksBuildPhase section */
{phase("PBXFrameworksBuildPhase", "appFrameworks", "Frameworks", f'				{I["coreBuild"]} /* OnePercentCore in Frameworks */,\n')}{phase("PBXFrameworksBuildPhase", "widgetFrameworks", "Frameworks")}/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		{I["main"]} = {{
			isa = PBXGroup;
			children = (
				{I["appGroup"]} /* OnePercentiOS */,
				{I["widgetGroup"]} /* OnePercentWidget */,
				{I["sharedGroup"]} /* Shared */,
				{I["products"]} /* Products */,
			);
			sourceTree = "<group>";
		}};
		{I["products"]} /* Products */ = {{
			isa = PBXGroup;
			children = (
				{I["appRef"]} /* OnePercentiOS.app */,
				{I["widgetRef"]} /* OnePercentWidget.appex */,
			);
			name = Products;
			sourceTree = "<group>";
		}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		{I["appTarget"]} /* OnePercentiOS */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {I["appCfgList"]} /* Build configuration list for PBXNativeTarget "OnePercentiOS" */;
			buildPhases = (
				{I["appSources"]} /* Sources */,
				{I["appFrameworks"]} /* Frameworks */,
				{I["appResources"]} /* Resources */,
				{I["appScript"]} /* Copy language packs */,
				{I["appEmbed"]} /* Embed Foundation Extensions */,
			);
			buildRules = (
			);
			dependencies = (
				{I["targetDep"]} /* PBXTargetDependency */,
			);
			fileSystemSynchronizedGroups = (
				{I["appGroup"]} /* OnePercentiOS */,
				{I["sharedGroup"]} /* Shared */,
			);
			name = OnePercentiOS;
			packageProductDependencies = (
				{I["coreDep"]} /* OnePercentCore */,
			);
			productName = OnePercentiOS;
			productReference = {I["appRef"]} /* OnePercentiOS.app */;
			productType = "com.apple.product-type.application";
		}};
		{I["widgetTarget"]} /* OnePercentWidget */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {I["widgetCfgList"]} /* Build configuration list for PBXNativeTarget "OnePercentWidget" */;
			buildPhases = (
				{I["widgetSources"]} /* Sources */,
				{I["widgetFrameworks"]} /* Frameworks */,
				{I["widgetResources"]} /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			fileSystemSynchronizedGroups = (
				{I["widgetGroup"]} /* OnePercentWidget */,
				{I["sharedGroup"]} /* Shared */,
			);
			name = OnePercentWidget;
			productName = OnePercentWidget;
			productReference = {I["widgetRef"]} /* OnePercentWidget.appex */;
			productType = "com.apple.product-type.app-extension";
		}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		{I["project"]} /* Project object */ = {{
			isa = PBXProject;
			attributes = {{
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 2700;
				LastUpgradeCheck = 2700;
				TargetAttributes = {{
					{I["appTarget"]} = {{
						CreatedOnToolsVersion = 27.0;
					}};
					{I["widgetTarget"]} = {{
						CreatedOnToolsVersion = 27.0;
					}};
				}};
			}};
			buildConfigurationList = {I["projCfgList"]} /* Build configuration list for PBXProject "OnePercentiOS" */;
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				Base,
				it,
			);
			mainGroup = {I["main"]};
			minimizedProjectReferenceProxies = 1;
			packageReferences = (
				{I["pkgRef"]} /* XCLocalSwiftPackageReference ".." */,
			);
			preferredProjectObjectVersion = 77;
			productRefGroup = {I["products"]} /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				{I["appTarget"]} /* OnePercentiOS */,
				{I["widgetTarget"]} /* OnePercentWidget */,
			);
		}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
{phase("PBXResourcesBuildPhase", "appResources", "Resources")}{phase("PBXResourcesBuildPhase", "widgetResources", "Resources")}/* End PBXResourcesBuildPhase section */

/* Begin PBXShellScriptBuildPhase section */
		{I["appScript"]} /* Copy language packs */ = {{
			isa = PBXShellScriptBuildPhase;
			alwaysOutOfDate = 1;
			buildActionMask = 2147483647;
			files = (
			);
			inputFileListPaths = (
			);
			inputPaths = (
			);
			name = "Copy language packs";
			outputFileListPaths = (
			);
			outputPaths = (
			);
			runOnlyForDeploymentPostprocessing = 0;
			shellPath = /bin/sh;
			shellScript = "{script}";
		}};
/* End PBXShellScriptBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
{phase("PBXSourcesBuildPhase", "appSources", "Sources")}{phase("PBXSourcesBuildPhase", "widgetSources", "Sources")}/* End PBXSourcesBuildPhase section */

/* Begin PBXTargetDependency section */
		{I["targetDep"]} /* PBXTargetDependency */ = {{
			isa = PBXTargetDependency;
			target = {I["widgetTarget"]} /* OnePercentWidget */;
			targetProxy = {I["proxy"]} /* PBXContainerItemProxy */;
		}};
/* End PBXTargetDependency section */

/* Begin XCBuildConfiguration section */
{cfg("projDebug", "Debug", project_debug)}{cfg("projRelease", "Release", project_release)}{cfg("appDebug", "Debug", app_settings)}{cfg("appRelease", "Release", app_settings)}{cfg("widgetDebug", "Debug", widget_settings)}{cfg("widgetRelease", "Release", widget_settings)}/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		{I["projCfgList"]} /* Build configuration list for PBXProject "OnePercentiOS" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{I["projDebug"]} /* Debug */,
				{I["projRelease"]} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
		{I["appCfgList"]} /* Build configuration list for PBXNativeTarget "OnePercentiOS" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{I["appDebug"]} /* Debug */,
				{I["appRelease"]} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
		{I["widgetCfgList"]} /* Build configuration list for PBXNativeTarget "OnePercentWidget" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{I["widgetDebug"]} /* Debug */,
				{I["widgetRelease"]} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
/* End XCConfigurationList section */

/* Begin XCLocalSwiftPackageReference section */
		{I["pkgRef"]} /* XCLocalSwiftPackageReference ".." */ = {{
			isa = XCLocalSwiftPackageReference;
			relativePath = "..";
		}};
/* End XCLocalSwiftPackageReference section */

/* Begin XCSwiftPackageProductDependency section */
		{I["coreDep"]} /* OnePercentCore */ = {{
			isa = XCSwiftPackageProductDependency;
			package = {I["pkgRef"]} /* XCLocalSwiftPackageReference ".." */;
			productName = OnePercentCore;
		}};
/* End XCSwiftPackageProductDependency section */
	}};
	rootObject = {I["project"]} /* Project object */;
}}
"""

target = os.path.join(ROOT, "iOS", "OnePercentiOS.xcodeproj", "project.pbxproj")
os.makedirs(os.path.dirname(target), exist_ok=True)
open(target, "w").write(pbx)

# The shared scheme builds and runs the app; the widget comes along as its dependency.
scheme_dir = os.path.join(ROOT, "iOS", "OnePercentiOS.xcodeproj", "xcshareddata", "xcschemes")
os.makedirs(scheme_dir, exist_ok=True)
ref = (f'BuildableIdentifier = "primary" BlueprintIdentifier = "{I["appTarget"]}" BuildableName = "OnePercentiOS.app" '
       'BlueprintName = "OnePercentiOS" ReferencedContainer = "container:OnePercentiOS.xcodeproj"')
def r(indent):
    pad = " " * indent
    parts = ref.replace('" ', '"\n').split("\n")
    return "\n".join(pad + p for p in parts)
open(os.path.join(scheme_dir, "OnePercentiOS.xcscheme"), "w").write(f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "2700" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES" buildArchitectures = "Automatic">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            <BuildableReference
{r(15)}>
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES" shouldAutocreateTestPlan = "YES">
   </TestAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference
{r(12)}>
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference
{r(12)}>
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
""")
print("wrote", target)
