from pathlib import Path
import plistlib
r=Path(__file__).resolve().parent
o={}; n=0
def add(isa,**kw):
 global n
 n+=1;k=f'{n:024X}';o[k]={'isa':isa,**kw};return k
bridge=add('PBXFileReference',lastKnownFileType='sourcecode.swift',path='PhoneWatchBridge.swift',sourceTree='<group>')
watchsrc=add('PBXFileReference',lastKnownFileType='sourcecode.swift',path='WireSTARTWatch.swift',sourceTree='<group>')
watchassets=add('PBXFileReference',lastKnownFileType='folder.assetcatalog',path='WatchAssets.xcassets',sourceTree='<group>')
watchinfo=add('PBXFileReference',lastKnownFileType='text.plist.xml',path='Watch-Info.plist',sourceTree='<group>')
watchproduct=add('PBXFileReference',explicitFileType='wrapper.application',includeInIndex=0,path='WireSTARTWatch.app',sourceTree='BUILT_PRODUCTS_DIR')
src=add('PBXFileReference',lastKnownFileType='sourcecode.swift',path='WireSTART.swift',sourceTree='<group>')
reply=add('PBXFileReference',lastKnownFileType='sourcecode.swift',path='AccessoryReply.swift',sourceTree='<group>')
vehicleNames=add('PBXFileReference',lastKnownFileType='sourcecode.swift',path='VehicleNames.swift',sourceTree='<group>')
framer=add('PBXFileReference',lastKnownFileType='sourcecode.swift',path='ResponseFramer.swift',sourceTree='<group>')
assets=add('PBXFileReference',lastKnownFileType='folder.assetcatalog',path='Assets.xcassets',sourceTree='<group>')
info=add('PBXFileReference',lastKnownFileType='text.plist.xml',path='Info.plist',sourceTree='<group>')
product=add('PBXFileReference',explicitFileType='wrapper.application',includeInIndex=0,path='WireSTART.app',sourceTree='BUILT_PRODUCTS_DIR')
widgetsrc=add('PBXFileReference',lastKnownFileType='sourcecode.swift',path='WireSTARTWidget.swift',sourceTree='<group>')
widgetconfirmation=add('PBXFileReference',lastKnownFileType='sourcecode.swift',path='WidgetConfirmation.swift',sourceTree='<group>')
widgetinfo=add('PBXFileReference',lastKnownFileType='text.plist.xml',path='Widget-Info.plist',sourceTree='<group>')
widgetproduct=add('PBXFileReference',explicitFileType='wrapper.app-extension',includeInIndex=0,path='WireSTARTWidget.appex',sourceTree='BUILT_PRODUCTS_DIR')
products=add('PBXGroup',children=[product,widgetproduct,watchproduct],name='Products',sourceTree='<group>')
group=add('PBXGroup',children=[src,framer,reply,vehicleNames,bridge,assets,info,widgetsrc,widgetconfirmation,widgetinfo,watchsrc,watchinfo,watchassets,products],sourceTree='<group>')
sources=add('PBXSourcesBuildPhase',buildActionMask=2147483647,files=[add('PBXBuildFile',fileRef=src),add('PBXBuildFile',fileRef=framer),add('PBXBuildFile',fileRef=reply),add('PBXBuildFile',fileRef=vehicleNames),add('PBXBuildFile',fileRef=bridge)],runOnlyForDeploymentPostprocessing=0)
frameworks=add('PBXFrameworksBuildPhase',buildActionMask=2147483647,files=[],runOnlyForDeploymentPostprocessing=0)
resources=add('PBXResourcesBuildPhase',buildActionMask=2147483647,files=[add('PBXBuildFile',fileRef=assets)],runOnlyForDeploymentPostprocessing=0)
def configs(target=False):
 ids=[]
 for name in ['Debug','Release']:
  s={'SDKROOT':'iphoneos','IPHONEOS_DEPLOYMENT_TARGET':'16.0','SWIFT_VERSION':'5.0','CLANG_ENABLE_MODULES':'YES'}
  if target:s.update({'CODE_SIGN_ENTITLEMENTS':'WireSTART.entitlements','PRODUCT_NAME':'WireSTART','PRODUCT_BUNDLE_IDENTIFIER':'com.wireproof.wirestart','DEVELOPMENT_TEAM':'KTV9W3H439','CODE_SIGN_STYLE':'Automatic','INFOPLIST_FILE':'Info.plist','GENERATE_INFOPLIST_FILE':'NO','TARGETED_DEVICE_FAMILY':'1','ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon','ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS':'YES','LD_RUNPATH_SEARCH_PATHS':['$(inherited)','@executable_path/Frameworks']})
  ids.append(add('XCBuildConfiguration',name=name,buildSettings=s))
 return add('XCConfigurationList',buildConfigurations=ids,defaultConfigurationIsVisible=0,defaultConfigurationName='Debug')
t=add('PBXNativeTarget',buildConfigurationList=configs(True),buildPhases=[sources,frameworks,resources],buildRules=[],dependencies=[],name='WireSTART',productName='WireSTART',productReference=product,productType='com.apple.product-type.application')
widget_sources=add('PBXSourcesBuildPhase',buildActionMask=2147483647,files=[add('PBXBuildFile',fileRef=widgetsrc),add('PBXBuildFile',fileRef=widgetconfirmation)],runOnlyForDeploymentPostprocessing=0)
widget_frameworks=add('PBXFrameworksBuildPhase',buildActionMask=2147483647,files=[],runOnlyForDeploymentPostprocessing=0)
widget_resources=add('PBXResourcesBuildPhase',buildActionMask=2147483647,files=[],runOnlyForDeploymentPostprocessing=0)
widget_configs=[]
for name in ['Debug','Release']:
 widget_configs.append(add('XCBuildConfiguration',name=name,buildSettings={'SDKROOT':'iphoneos','IPHONEOS_DEPLOYMENT_TARGET':'17.0','SWIFT_VERSION':'5.0','CLANG_ENABLE_MODULES':'YES','CODE_SIGN_ENTITLEMENTS':'WireSTART.entitlements','PRODUCT_NAME':'WireSTARTWidget','PRODUCT_BUNDLE_IDENTIFIER':'com.wireproof.wirestart.widget','DEVELOPMENT_TEAM':'KTV9W3H439','CODE_SIGN_STYLE':'Automatic','INFOPLIST_FILE':'Widget-Info.plist','GENERATE_INFOPLIST_FILE':'NO','TARGETED_DEVICE_FAMILY':'1','SKIP_INSTALL':'YES','APPLICATION_EXTENSION_API_ONLY':'YES','LD_RUNPATH_SEARCH_PATHS':['$(inherited)','@executable_path/Frameworks','@executable_path/../../Frameworks']}))
widget_config_list=add('XCConfigurationList',buildConfigurations=widget_configs,defaultConfigurationIsVisible=0,defaultConfigurationName='Debug')
widget=add('PBXNativeTarget',buildConfigurationList=widget_config_list,buildPhases=[widget_sources,widget_frameworks,widget_resources],buildRules=[],dependencies=[],name='WireSTARTWidget',productName='WireSTARTWidget',productReference=widgetproduct,productType='com.apple.product-type.app-extension')
embed=add('PBXCopyFilesBuildPhase',buildActionMask=2147483647,dstPath='',dstSubfolderSpec=13,files=[add('PBXBuildFile',fileRef=widgetproduct,settings={'ATTRIBUTES':['RemoveHeadersOnCopy']})],name='Embed App Extensions',runOnlyForDeploymentPostprocessing=0)
o[t]['buildPhases'].append(embed)
proxy=add('PBXContainerItemProxy',containerPortal='PROJECT_PLACEHOLDER',proxyType=1,remoteGlobalIDString=widget,remoteInfo='WireSTARTWidget')
o[t]['dependencies'].append(add('PBXTargetDependency',target=widget,targetProxy=proxy))
watch_sources=add('PBXSourcesBuildPhase',buildActionMask=2147483647,files=[add('PBXBuildFile',fileRef=watchsrc)],runOnlyForDeploymentPostprocessing=0)
watch_frameworks=add('PBXFrameworksBuildPhase',buildActionMask=2147483647,files=[],runOnlyForDeploymentPostprocessing=0)
watch_resources=add('PBXResourcesBuildPhase',buildActionMask=2147483647,files=[add('PBXBuildFile',fileRef=watchassets)],runOnlyForDeploymentPostprocessing=0)
watch_configs=[]
for name in ['Debug','Release']:
 watch_configs.append(add('XCBuildConfiguration',name=name,buildSettings={'SDKROOT':'watchos','SUPPORTED_PLATFORMS':'watchos watchsimulator','WATCHOS_DEPLOYMENT_TARGET':'10.0','SWIFT_VERSION':'5.0','CLANG_ENABLE_MODULES':'YES','PRODUCT_NAME':'WireSTARTWatch','PRODUCT_BUNDLE_IDENTIFIER':'com.wireproof.wirestart.watchkitapp','DEVELOPMENT_TEAM':'KTV9W3H439','CODE_SIGN_STYLE':'Automatic','INFOPLIST_FILE':'Watch-Info.plist','GENERATE_INFOPLIST_FILE':'NO','TARGETED_DEVICE_FAMILY':'4','ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon','SKIP_INSTALL':'YES'}))
watch_config_list=add('XCConfigurationList',buildConfigurations=watch_configs,defaultConfigurationIsVisible=0,defaultConfigurationName='Debug')
watch=add('PBXNativeTarget',buildConfigurationList=watch_config_list,buildPhases=[watch_sources,watch_frameworks,watch_resources],buildRules=[],dependencies=[],name='WireSTARTWatch',productName='WireSTARTWatch',productReference=watchproduct,productType='com.apple.product-type.application')
watch_embed=add('PBXCopyFilesBuildPhase',buildActionMask=2147483647,dstPath='$(CONTENTS_FOLDER_PATH)/Watch',dstSubfolderSpec=16,files=[add('PBXBuildFile',fileRef=watchproduct,settings={'ATTRIBUTES':['RemoveHeadersOnCopy']})],name='Embed Watch Content',runOnlyForDeploymentPostprocessing=0)
o[t]['buildPhases'].append(watch_embed)
watch_proxy=add('PBXContainerItemProxy',containerPortal='PROJECT_PLACEHOLDER',proxyType=1,remoteGlobalIDString=watch,remoteInfo='WireSTARTWatch')
o[t]['dependencies'].append(add('PBXTargetDependency',target=watch,targetProxy=watch_proxy))
p=add('PBXProject',attributes={'LastUpgradeCheck':'2710','TargetAttributes':{t:{'CreatedOnToolsVersion':'27.1','DevelopmentTeam':'KTV9W3H439','ProvisioningStyle':'Automatic'}}},buildConfigurationList=configs(),compatibilityVersion='Xcode 14.0',developmentRegion='en',hasScannedForEncodings=0,knownRegions=['en','Base'],mainGroup=group,productRefGroup=products,projectDirPath='',projectRoot='',targets=[t,widget,watch])
o[proxy]['containerPortal']=p
o[watch_proxy]['containerPortal']=p
d=r/'WireSTART.xcodeproj';d.mkdir(exist_ok=True);(d/'project.pbxproj').write_bytes(plistlib.dumps({'archiveVersion':'1','classes':{},'objectVersion':'56','objects':o,'rootObject':p},sort_keys=False))
