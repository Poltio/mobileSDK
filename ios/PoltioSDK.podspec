Pod::Spec.new do |s|
  s.name             = 'PoltioSDK'
  s.version          = '0.0.3'
  s.summary          = 'Poltio Mobile SDK for iOS'
  s.description      = 'Integrates Poltio TAG web experience and event tracking in iOS applications.'
  s.homepage         = 'https://github.com/Poltio/mobileSDK'
  s.license          = { :type => 'MIT' }
  s.author           = { 'Poltio' => 'dev@poltio.com' }
  s.source           = { :git => 'https://github.com/Poltio/mobileSDK.git', :tag => "v#{s.version}" }

  s.ios.deployment_target = '14.0'
  s.swift_version    = '5.9'

  s.source_files     = 'ios/Sources/PoltioSDK/**/*'
  s.resource_bundles = {
    'PoltioSDK_Privacy' => ['ios/Sources/PoltioSDK/Resources/PrivacyInfo.xcprivacy']
  }
  s.frameworks       = 'Foundation', 'WebKit', 'UIKit'
end
