require 'xcodeproj'
project_path = '/Users/john/git/pockterm/pockterm.xcodeproj'
project = Xcodeproj::Project.open(project_path)
app = project.targets.find { |t| t.name == 'pockterm' }
ui = project.targets.find { |t| t.name == 'pocktermUITests' }
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.add_test_target(ui)
scheme.set_launch_target(app)
scheme.save_as(project_path, 'pocktermUI', true)
puts 'OK'
