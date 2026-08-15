#!/usr/bin/env ruby
# Adds a TEMPORARY pocktermUITests target whose sources are the driver tests
# in this directory's uitests/. Revert pockterm.xcodeproj (and delete the
# pocktermUI scheme) when verification is done — the target is not meant to
# be committed into the project file.
require 'xcodeproj'

project_path = File.expand_path('../../../pockterm.xcodeproj', __dir__)
src_dir = File.expand_path('uitests', __dir__)
project = Xcodeproj::Project.open(project_path)
app = project.targets.find { |t| t.name == 'pockterm' }
raise 'app target missing' unless app

target = project.targets.find { |t| t.name == 'pocktermUITests' }
unless target
  target = project.new_target(:ui_test_bundle, 'pocktermUITests', :ios, '26.0')
  target.add_dependency(app)
end
target.build_configurations.each do |c|
  c.build_settings['PRODUCT_NAME'] = 'pocktermUITests'
  c.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'John-Hancock.pocktermUITests'
  c.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  c.build_settings['TEST_TARGET_NAME'] = 'pockterm'
  c.build_settings['SWIFT_VERSION'] = '5.0'
  c.build_settings['DEVELOPMENT_TEAM'] = '5H22F8M69N'
  c.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '26.5'
end

group = project.main_group['pocktermUITests'] || project.main_group.new_group('pocktermUITests')
src_phase = target.source_build_phase
existing = src_phase.files.map { |f| f.file_ref&.real_path&.to_s }.compact
Dir.glob(File.join(src_dir, '*.swift')).sort.each do |path|
  next if existing.include?(path)
  ref = group.new_reference(path)
  src_phase.add_file_reference(ref, true)
end

project.save
puts 'OK'
