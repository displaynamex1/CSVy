#!/usr/bin/env ruby

require 'thor'
require 'dotenv/load'
require_relative 'lib/csv_processor'
require_relative 'lib/data_preprocessor'
require_relative 'lib/data_validator'
require_relative 'lib/dataframe_handler'
require_relative 'lib/database_manager'
require_relative 'lib/csv_diagnostics'
require_relative 'lib/time_series_features'
require_relative 'lib/csv_io_handler'

class CSVOrganizer < Thor
  desc "diagnose FILE", "Deep analysis of CSV data quality - detects mixed types, missing values, outliers, distribution issues"
  def diagnose(file)
    unless File.exist?(file)
      puts "✗ File not found: #{file}"
      exit 1
    end
    
    diagnostics = CSVDiagnostics.new(file)
    diagnostics.diagnose
  end

  desc "clean FILE", "Analyze and clean CSV data - adds _cleaned columns with transformations, preserves originals"
  def clean(file)
    puts "Cleaning CSV file: #{file}"
    if CSVProcessor.clean(file)
      puts "✓ File cleaned successfully!"
      puts "\nOriginal columns preserved - view side-by-side comparison:"
      puts "  • Missing values filled (mean for numbers, 'MISSING' for text)"
      puts "  • Outliers replaced using IQR method"
      puts "  • Cleaned columns added with '_cleaned' suffix"
    else
      puts "✗ Failed to clean file. Check the logs for details."
      exit 1
    end
  end

  desc "merge FILE1 FILE2 [OUTPUT]", "Merge two CSV files (default: concatenate)"
  option :output, aliases: :o, type: :string, default: 'merged.csv', desc: 'Output file name'
  option :type, aliases: :t, type: :string, default: 'concat', desc: 'Merge type: concat or join'
  option :key, aliases: :k, type: :string, desc: 'Key column for join operation'
  def merge(file1, file2)
    output_file = options[:output]
    puts "Merging CSV files: #{file1} and #{file2}"
    puts "Output file: #{output_file}"
    
    if CSVProcessor.merge(file1, file2, output_file)
      puts "✓ Files merged successfully!"
    else
      puts "✗ Failed to merge files. Check the logs for details."
      exit 1
    end
  end

  desc "transform FILE", "Transform CSV data with custom operations"
  def transform(file)
    puts "Transforming CSV file: #{file}"
    if CSVProcessor.transform(file)
      puts "✓ File transformed successfully!"
    else
      puts "✗ Failed to transform file. Check the logs for details."
      exit 1
    end
  end

  desc "info FILE", "Display information about a CSV file"
  def info(file)
    unless File.exist?(file)
      puts "✗ File not found: #{file}"
      exit 1
    end

    begin
      data = CSV.read(file, headers: true)
      puts "\n=== CSV File Information ==="
      puts "File: #{file}"
      puts "Rows: #{data.length}"
      puts "Columns: #{data.headers.length}"
      puts "\nColumn Names:"
      data.headers.each_with_index do |header, idx|
        puts "  #{idx + 1}. #{header}"
      end
      puts "\nFirst 3 rows:"
      data.first(3).each_with_index do |row, idx|
        puts "\nRow #{idx + 1}:"
        row.each { |key, value| puts "  #{key}: #{value}" }
      end
    rescue StandardError => e
      puts "✗ Error reading file: #{e.message}"
      exit 1
    end
  end

  desc "version", "Display version information"
  def version
    puts "CSVy Organizer v1.0.0"
    puts "Ruby CSV processing and organization tool"
  end

  desc "encode FILE COLUMN", "One-hot encode a categorical column"
  option :output, aliases: :o, type: :string, desc: 'Output file name'
  option :type, aliases: :t, type: :string, default: 'onehot', desc: 'Encoding type: onehot or label'
  def encode(file, column)
    unless File.exist?(file)
      puts "✗ File not found: #{file}"
      exit 1
    end

    begin
      data = CSV.read(file, headers: true)
      preprocessor = DataPreprocessor.new
      
      encoded = if options[:type] == 'onehot'
        preprocessor.one_hot_encode(data, column)
      else
        preprocessor.label_encode(data, column)
      end
      
      output_file = options[:output] || file.gsub('.csv', "_#{options[:type]}_encoded.csv")
      CSV.open(output_file, 'w', write_headers: true, headers: encoded.headers) do |csv|
        encoded.each { |row| csv << row }
      end
      
      puts "✓ Column '#{column}' encoded successfully!"
      puts "Output: #{output_file}"
    rescue StandardError => e
      puts "✗ Error: #{e.message}"
      exit 1
    end
  end

  desc "normalize FILE COLUMN", "Normalize a numeric column to 0-1 range"
  option :output, aliases: :o, type: :string, desc: 'Output file name'
  option :method, aliases: :m, type: :string, default: 'minmax', desc: 'Method: minmax or zscore'
  def normalize(file, column)
    unless File.exist?(file)
      puts "✗ File not found: #{file}"
      exit 1
    end

    begin
      data = CSV.read(file, headers: true)
      preprocessor = DataPreprocessor.new
      
      normalized = if options[:method] == 'minmax'
        preprocessor.normalize(data, column)
      else
        preprocessor.standardize(data, column)
      end
      
      output_file = options[:output] || file.gsub('.csv', '_normalized.csv')
      CSV.open(output_file, 'w', write_headers: true, headers: normalized.headers) do |csv|
        normalized.each { |row| csv << row }
      end
      
      puts "✓ Column '#{column}' normalized successfully!"
      puts "Output: #{output_file}"
    rescue StandardError => e
      puts "✗ Error: #{e.message}"
      exit 1
    end
  end

  desc "validate FILE", "Validate data quality and generate report"
  def validate(file)
    unless File.exist?(file)
      puts "✗ File not found: #{file}"
      exit 1
    end

    validator = DataValidator.new
    report = validator.validate(file)
    
    puts "\n=== Validation Report ==="
    puts "File: #{report[:file]}"
    puts "Rows: #{report[:total_rows]}"
    puts "Columns: #{report[:total_columns]}"
    puts "\nColumn Types:"
    report[:column_types].each { |col, type| puts "  #{col}: #{type}" }
    
    if report[:issues].empty?
      puts "\n✓ No issues found!"
    else
      puts "\n⚠ Issues Found:"
      report[:issues].each { |issue| puts "  - #{issue}" }
    end
    
    unless report[:warnings].empty?
      puts "\n⚠ Warnings:"
      report[:warnings].each { |warning| puts "  - #{warning}" }
    end
  end

  desc "stats FILE", "Generate statistics for dataset"
  def stats(file)
    unless File.exist?(file)
      puts "✗ File not found: #{file}"
      exit 1
    end

    validator = DataValidator.new
    stats = validator.statistics(file)
    
    puts "\n=== Statistics Report ==="
    stats.each do |column, data|
      puts "\n#{column}:"
      data.each { |key, value| puts "  #{key}: #{value}" }
    end
  end

  desc "profile FILE", "Generate detailed data profile"
  def profile(file)
    unless File.exist?(file)
      puts "✗ File not found: #{file}"
      exit 1
    end

    validator = DataValidator.new
    profile = validator.profile(file)
    
    puts "\n=== Data Profile ==="
    puts "File: #{profile[:file]}"
    puts "Rows: #{profile[:rows]}"
    puts "Columns: #{profile[:columns]}"
    puts "Memory: #{profile[:memory_estimate]}"
    
    puts "\n--- Column Profiles ---"
    profile[:column_profiles].each do |column, data|
      puts "\n#{column}:"
      data.each { |key, value| puts "  #{key}: #{value}" }
    end
  end

  desc "db-import FILE TABLE", "Import CSV to SQLite database"
  option :database, aliases: :d, type: :string, default: 'data/csvs.db', desc: 'Database path'
  def db_import(file, table)
    unless File.exist?(file)
      puts "✗ File not found: #{file}"
      exit 1
    end

    db = DatabaseManager.new(options[:database])
    if db.import_csv(file, table)
      puts "✓ Successfully imported #{file} to table '#{table}'"
    else
      puts "✗ Failed to import data"
      exit 1
    end
    db.disconnect
  end

  desc "db-export TABLE FILE", "Export SQLite table to CSV"
  option :database, aliases: :d, type: :string, default: 'data/csvs.db', desc: 'Database path'
  def db_export(table, file)
    db = DatabaseManager.new(options[:database])
    if db.export_to_csv(table, file)
      puts "✓ Successfully exported table '#{table}' to #{file}"
    else
      puts "✗ Failed to export data"
      exit 1
    end
    db.disconnect
  end

  desc "db-query SQL", "Execute SQL query on database"
  option :database, aliases: :d, type: :string, default: 'data/csvs.db', desc: 'Database path'
  def db_query(sql)
    db = DatabaseManager.new(options[:database])
    results = db.query(sql)
    
    if results.empty?
      puts "No results found"
    else
      puts "\n=== Query Results ==="
      results.each_with_index do |row, idx|
        puts "\nRow #{idx + 1}:"
        row.each { |key, value| puts "  #{key}: #{value}" }
      end
    end
    db.disconnect
  end

  desc "db-tables", "List all tables in database"
  option :database, aliases: :d, type: :string, default: 'data/csvs.db', desc: 'Database path'
  def db_tables
    db = DatabaseManager.new(options[:database])
    tables = db.list_tables
    
    puts "\n=== Database Tables ==="
    if tables.empty?
      puts "No tables found"
    else
      tables.each { |table| puts "  - #{table}" }
    end
    db.disconnect
  end

  # Time Series Feature Engineering Commands
  desc "rolling FILE COLUMN", "Calculate rolling window statistics (moving average, sum, etc.)"
  option :window, aliases: :w, type: :numeric, default: 10, desc: 'Window size'
  option :stat, aliases: :s, type: :string, default: 'mean', desc: 'Statistic: mean, sum, max, min, std'
  option :group, aliases: :g, type: :string, desc: 'Group by column (e.g., team_name)'
  option :output, aliases: :o, type: :string, desc: 'Output file'
  def rolling(file, column)
    data = CSV.read(file, headers: true)
    ts = TimeSeriesFeatures.new
    
    stat = options[:stat].to_sym
    result = ts.rolling_window(data, column, options[:window], stat: stat, group_by: options[:group])
    
    output = options[:output] || file.gsub('.csv', "_rolling_#{stat}_#{options[:window]}.csv")
    CSV.open(output, 'w', write_headers: true, headers: result.headers) do |csv|
      result.each { |row| csv << row }
    end
    
    puts "✓ Rolling #{stat} calculated (window=#{options[:window]})"
    puts "Output: #{output}"
  end

  desc "ewma FILE COLUMN", "Calculate exponentially weighted moving average (recent games weighted more)"
  option :span, aliases: :s, type: :numeric, default: 10, desc: 'Span for EWMA calculation'
  option :group, aliases: :g, type: :string, desc: 'Group by column (e.g., team_name)'
  option :output, aliases: :o, type: :string, desc: 'Output file'
  def ewma(file, column)
    data = CSV.read(file, headers: true)
    ts = TimeSeriesFeatures.new
    
    result = ts.ewma(data, column, options[:span], group_by: options[:group])
    
    output = options[:output] || file.gsub('.csv', "_ewma_#{options[:span]}.csv")
    CSV.open(output, 'w', write_headers: true, headers: result.headers) do |csv|
      result.each { |row| csv << row }
    end
    
    puts "✓ EWMA calculated (span=#{options[:span]})"
    puts "Output: #{output}"
  end

  desc "lag FILE COLUMN PERIODS", "Create lag features (previous game values) - PERIODS is comma-separated (e.g., 1,3,5)"
  option :group, aliases: :g, type: :string, desc: 'Group by column (e.g., team_name)'
  option :output, aliases: :o, type: :string, desc: 'Output file'
  def lag(file, column, periods)
    data = CSV.read(file, headers: true)
    ts = TimeSeriesFeatures.new
    
    period_array = periods.split(',').map(&:to_i)
    result = ts.lag_features(data, column, period_array, group_by: options[:group])
    
    output = options[:output] || file.gsub('.csv', "_lag.csv")
    CSV.open(output, 'w', write_headers: true, headers: result.headers) do |csv|
      result.each { |row| csv << row }
    end
    
    puts "✓ Lag features created (periods: #{period_array.join(', ')})"
    puts "Output: #{output}"
  end

  desc "rate FILE NUMERATOR DENOMINATOR", "Calculate rate statistics (e.g., goals per game)"
  option :output_name, aliases: :n, type: :string, desc: 'Output column name'
  option :output_file, aliases: :o, type: :string, desc: 'Output file'
  def rate(file, numerator, denominator)
    data = CSV.read(file, headers: true)
    ts = TimeSeriesFeatures.new
    
    result = ts.rate_stat(data, numerator, denominator, output_name: options[:output_name])
    
    output = options[:output_file] || file.gsub('.csv', '_rate.csv')
    CSV.open(output, 'w', write_headers: true, headers: result.headers) do |csv|
      result.each { |row| csv << row }
    end
    
    puts "✓ Rate statistic calculated: #{numerator} / #{denominator}"
    puts "Output: #{output}"
  end

  desc "streak FILE COLUMN", "Calculate win/loss streaks from result column"
  option :group, aliases: :g, type: :string, desc: 'Group by column (e.g., team_name)'
  option :output, aliases: :o, type: :string, desc: 'Output file'
  def streak(file, column)
    data = CSV.read(file, headers: true)
    ts = TimeSeriesFeatures.new
    
    result = ts.calculate_streaks(data, column, group_by: options[:group])
    
    output = options[:output] || file.gsub('.csv', '_streak.csv')
    CSV.open(output, 'w', write_headers: true, headers: result.headers) do |csv|
      result.each { |row| csv << row }
    end
    
    puts "✓ Streaks calculated"
    puts "Output: #{output}"
  end

  desc "rest FILE DATE_COLUMN", "Calculate rest days between games"
  option :group, aliases: :g, type: :string, desc: 'Group by column (e.g., team_name)'
  option :output, aliases: :o, type: :string, desc: 'Output file'
  def rest(file, date_column)
    data = CSV.read(file, headers: true)
    ts = TimeSeriesFeatures.new
    
    result = ts.days_between(data, date_column, output_name: 'rest_days', group_by: options[:group])
    
    output = options[:output] || file.gsub('.csv', '_rest.csv')
    CSV.open(output, 'w', write_headers: true, headers: result.headers) do |csv|
      result.each { |row| csv << row }
    end
    
    puts "✓ Rest days calculated"
    puts "Output: #{output}"
  end

  desc "cumulative FILE COLUMN", "Calculate cumulative statistics (running total)"
  option :stat, aliases: :s, type: :string, default: 'sum', desc: 'Statistic: sum, mean, max, min'
  option :group, aliases: :g, type: :string, desc: 'Group by column (e.g., team_name)'
  option :output, aliases: :o, type: :string, desc: 'Output file'
  def cumulative(file, column)
    data = CSV.read(file, headers: true)
    ts = TimeSeriesFeatures.new
    
    stat = options[:stat].to_sym
    result = ts.cumulative(data, column, stat: stat, group_by: options[:group])
    
    output = options[:output] || file.gsub('.csv', "_cumulative_#{stat}.csv")
    CSV.open(output, 'w', write_headers: true, headers: result.headers) do |csv|
      result.each { |row| csv << row }
    end
    
    puts "✓ Cumulative #{stat} calculated"
    puts "Output: #{output}"
  end

  desc "rank FILE COLUMN", "Rank values within dataset or groups"
  option :group, aliases: :g, type: :string, desc: 'Group by column (e.g., team_name)'
  option :ascending, aliases: :a, type: :boolean, default: false, desc: 'Rank ascending (default: descending)'
  option :output, aliases: :o, type: :string, desc: 'Output file'
  def rank(file, column)
    data = CSV.read(file, headers: true)
    ts = TimeSeriesFeatures.new
    
    result = ts.rank_column(data, column, group_by: options[:group], ascending: options[:ascending])
    
    output = options[:output] || file.gsub('.csv', '_ranked.csv')
    CSV.open(output, 'w', write_headers: true, headers: result.headers) do |csv|
      result.each { |row| csv << row }
    end
    
    puts "✓ Column ranked"
    puts "Output: #{output}"
  end

  # IO Operations
  desc "from-clipboard", "Read CSV from clipboard and display info"
  def from_clipboard
    data = CSVIOHandler.from_clipboard
    puts "\n=== CSV from Clipboard ==="
    puts "Rows: #{data.length}"
    puts "Columns: #{data.headers.length}"
    puts "Headers: #{data.headers.join(', ')}"
  rescue => e
    puts "✗ Error reading from clipboard: #{e.message}"
  end

  desc "to-clipboard FILE", "Copy CSV file to clipboard"
  def to_clipboard(file)
    data = CSV.read(file, headers: true)
    CSVIOHandler.to_clipboard(data)
    puts "✓ CSV copied to clipboard (#{data.length} rows)"
  rescue => e
    puts "✗ Error: #{e.message}"
  end
end

# Run the CLI
CSVOrganizer.start(ARGV)
