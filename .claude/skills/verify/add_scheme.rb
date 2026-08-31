require 'xcodeproj'
# Derived, not hardcoded: a hardcoded path silently writes the scheme into the
# main checkout when this runs from a git worktree, and the build then fails
# with "does not contain a scheme named pocktermUI" in the worktree.
project_path = File.expand_path('../../../pockterm.xcodeproj', __dir__)
project = Xcodeproj::Project.open(project_path)
app = project.targets.find { |t| t.name == 'pockterm' }
ui = project.targets.find { |t| t.name == 'pocktermUITests' }
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.add_test_target(ui)
scheme.set_launch_target(app)
scheme.save_as(project_path, 'pocktermUI', true)
puts 'OK'
