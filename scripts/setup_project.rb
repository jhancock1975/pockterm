#!/usr/bin/env ruby
# Idempotent project mutation: adds SPM package deps to the app target and a
# unit-test target. The app target uses a PBXFileSystemSynchronizedRootGroup,
# so app sources under pockterm/ are picked up automatically — we do not add
# per-file references for the app. Test files are referenced explicitly.
require 'xcodeproj'

project_path = File.expand_path('../pockterm.xcodeproj', __dir__)
project = Xcodeproj::Project.open(project_path)
app = project.targets.find { |t| t.name == 'pockterm' }
raise 'app target missing' unless app

def add_pkg(project, app, url, requirement, product)
  ref = project.root_object.package_references.find { |r| r.respond_to?(:repositoryURL) && r.repositoryURL == url }
  unless ref
    ref = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
    ref.repositoryURL = url
    ref.requirement = requirement
    project.root_object.package_references << ref
  end
  return if app.package_product_dependencies.any? { |d| d.product_name == product }
  dep = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
  dep.package = ref
  dep.product_name = product
  app.package_product_dependencies << dep
  bf = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  bf.product_ref = dep
  app.frameworks_build_phase.files << bf
end

add_pkg(project, app, 'https://github.com/migueldeicaza/SwiftTerm.git',
        { kind: 'upToNextMajorVersion', minimumVersion: '1.2.0' }, 'SwiftTerm')
add_pkg(project, app, 'https://github.com/orlandos-nl/Citadel.git',
        { kind: 'upToNextMajorVersion', minimumVersion: '0.8.0' }, 'Citadel')
# swift-crypto is pulled in transitively by Citadel, but SSHEngine needs to
# construct Citadel's `Curve25519.Signing.PrivateKey` (swift-crypto's type, not
# CryptoKit's) from a raw seed, so it must be a direct product dependency.
add_pkg(project, app, 'https://github.com/apple/swift-crypto.git',
        { kind: 'upToNextMajorVersion', minimumVersion: '3.0.0' }, 'Crypto')

# Unit-test target
test_target = project.targets.find { |t| t.name == 'pocktermTests' }
unless test_target
  test_target = project.new_target(:unit_test_bundle, 'pocktermTests', :ios, '26.0')
  test_target.add_dependency(app)
end
test_target.build_configurations.each do |c|
  c.build_settings['PRODUCT_NAME'] = 'pocktermTests'
  c.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'John-Hancock.pocktermTests'
  c.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  c.build_settings['TEST_HOST'] = '$(BUILT_PRODUCTS_DIR)/pockterm.app/pockterm'
  c.build_settings['BUNDLE_LOADER'] = '$(TEST_HOST)'
  # Must match the app target. This script has to be re-run whenever a test
  # file is added, so a stale value here silently reverts the language mode —
  # it downgraded the tests to Swift 5 the first time a file was added after
  # the Swift 6 move in #81.
  c.build_settings['SWIFT_VERSION'] = '6.0'
  c.build_settings['DEVELOPMENT_TEAM'] = '5H22F8M69N'
  c.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '26.5'
end

# Test group + (idempotent) explicit source references for every test file on disk.
test_group = project.main_group['pocktermTests'] || project.main_group.new_group('pocktermTests', 'pocktermTests')
src_phase = test_target.source_build_phase
existing = src_phase.files.map { |f| f.file_ref&.real_path&.to_s }.compact
Dir.glob(File.expand_path('../pocktermTests/**/*.swift', __dir__)).sort.each do |path|
  next if existing.include?(path)
  rel = path.sub(File.expand_path('../pocktermTests/', __dir__) + '/', '')
  ref = test_group.find_file_by_path(rel) || test_group.new_reference(path)
  src_phase.add_file_reference(ref, true)
end

# Prune references to test files that were removed from disk.
src_phase.files.dup.each do |bf|
  ref = bf.file_ref
  path = ref&.real_path&.to_s
  next unless path && !File.exist?(path)
  bf.remove_from_project
  ref.remove_from_project
end

project.save
puts 'OK'
