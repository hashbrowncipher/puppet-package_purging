require 'puppetlabs_spec_helper/rake_tasks'

# try to load only required rake
if ARGV.size == 1 && File.exists?("lib/tasks/#{ARGV.first}.rake")
  import "lib/tasks/#{ARGV.first}.rake"
else
  # Break tasks out to individual rake files to prevent clutter.
  FileList['lib/tasks/*.rake'].each do |rake_file|
    import rake_file
  end
end
