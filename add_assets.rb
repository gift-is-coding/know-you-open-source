require 'xcodeproj'

project_path = 'KnowYou.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Let's find the main target "KnowYou"
target = project.targets.find { |t| t.name == 'KnowYou' }
raise "Target not found" unless target

# Find the main group (KnowYou) to put the reference, or just root
group = project.main_group.groups.find { |g| g.name == 'KnowYou' } || project.main_group

# Check if Assets.xcassets is already there
unless group.files.find { |f| f.path == 'KnowYou/Assets.xcassets' || f.name == 'Assets.xcassets' || f.path == 'Assets.xcassets' }
  file_ref = group.new_reference('KnowYou/Assets.xcassets')
  # Add to resources build phase
  resources_build_phase = target.resources_build_phase
  resources_build_phase.add_file_reference(file_ref)
  project.save
  puts "Assets.xcassets added"
else
  puts "Assets.xcassets already exists in project"
end

# Make sure ASSETCATALOG_COMPILER_APPICON_NAME is set
target.build_configurations.each do |config|
  config.build_settings['ASSETCATALOG_COMPILER_APPICON_NAME'] = 'AppIcon'
  config.build_settings['ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME'] = 'AccentColor'
end

project.save
puts "Build settings updated"
