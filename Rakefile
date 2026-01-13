require 'rspec/core/rake_task'

desc 'Run all RSpec tests'
RSpec::Core::RakeTask.new(:spec) do |t|
  t.pattern = 'spec/**/*_spec.rb'
  t.rspec_opts = ['--color', '--format documentation']
end

desc 'Run tests with coverage'
task :test do
  ENV['COVERAGE'] = 'true'
  Rake::Task[:spec].invoke
end

desc 'Install dependencies'
task :install do
  sh 'bundle install'
end

desc 'Clean temporary and generated files'
task :clean do
  puts 'Cleaning temporary files...'
  FileUtils.rm_rf('tmp')
  FileUtils.rm_rf('log')
  FileUtils.rm_f(Dir.glob('data/*_cleaned.csv'))
  FileUtils.rm_f(Dir.glob('data/*_merged.csv'))
  FileUtils.rm_f('data/csvs.db') if File.exist?('data/csvs.db')
  puts 'Clean complete!'
end

desc 'Generate documentation'
task :docs do
  sh 'yard doc lib/*.rb'
end

desc 'Lint Ruby code'
task :lint do
  sh 'rubocop lib spec'
end

desc 'Run example: Clean sample data'
task :example_clean do
  require_relative 'lib/csv_processor'
  puts "\n=== Cleaning sample_students_dirty.csv ==="
  CSVProcessor.clean('data/sample_students_dirty.csv')
end

desc 'Run example: Merge sample data'
task :example_merge do
  require_relative 'lib/csv_processor'
  puts "\n=== Merging sample_employees.csv and sample_products.csv ==="
  CSVProcessor.merge('data/sample_employees.csv', 'data/sample_products.csv', 'data/example_merged.csv')
end

desc 'Run example: Data validation'
task :example_validate do
  require_relative 'lib/data_validator'
  validator = DataValidator.new
  puts "\n=== Validating sample_employees.csv ==="
  report = validator.validate('data/sample_employees.csv')
  puts "\n--- Validation Report ---"
  puts "File: #{report[:file]}"
  puts "Total Rows: #{report[:total_rows]}"
  puts "Total Columns: #{report[:total_columns]}"
  puts "Columns: #{report[:columns].join(', ')}"
  puts "\nIssues found: #{report[:issues].length}"
  report[:issues].each { |issue| puts "  - #{issue}" }
end

desc 'Run example: Data statistics'
task :example_stats do
  require_relative 'lib/data_validator'
  validator = DataValidator.new
  puts "\n=== Statistics for sample_employees.csv ==="
  stats = validator.statistics('data/sample_employees.csv')
  stats.each do |column, data|
    puts "\nColumn: #{column}"
    data.each { |key, value| puts "  #{key}: #{value}" }
  end
end

desc 'Run all examples'
task :examples => [:example_clean, :example_merge, :example_validate, :example_stats]

desc 'Setup development environment'
task :setup => [:install, :clean] do
  puts "\n✓ Development environment ready!"
  puts "Run 'rake examples' to see the tool in action"
end

task :default => :spec
