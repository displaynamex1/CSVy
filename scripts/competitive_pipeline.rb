#!/usr/bin/env ruby
# Advanced preprocessing pipeline for competitive hockey prediction

require_relative '../lib/csv_cleaner'
require_relative '../lib/data_preprocessor'
require_relative '../lib/time_series_features'
require_relative '../lib/advanced_features'
require_relative '../lib/model_validator'

class CompetitivePreprocessor
  def initialize(input_file, output_dir = 'data/processed')
    @input_file = input_file
    @output_dir = output_dir
    @logger = Logger.new(STDOUT)
    
    # Initialize all processors
    @cleaner = CSVCleaner.new(@logger)
    @preprocessor = DataPreprocessor.new(@logger)
    @ts_features = TimeSeriesFeatures.new(@logger)
    @advanced = AdvancedFeatures.new(@logger)
    @validator = ModelValidator.new(@logger)
    
    FileUtils.mkdir_p(@output_dir)
  end

  def run_full_pipeline
    @logger.info "=" * 60
    @logger.info "COMPETITIVE PREPROCESSING PIPELINE"
    @logger.info "=" * 60
    
    # Step 1: Load and clean data
    @logger.info "\n[1/6] Loading and cleaning data..."
    data = CSV.read(@input_file, headers: true)
    
    # Remove duplicates
    data = @cleaner.remove_duplicates(data.to_a)
    
    # Fill missing values
    data = @cleaner.fill_missing_values(data, method: :mean, columns: ['GF', 'GA', 'PTS'])
    
    # Step 2: Basic preprocessing
    @logger.info "\n[2/6] Basic preprocessing..."
    
    # Normalize numeric columns
    data = @preprocessor.normalize_column(data, 'PTS', method: :minmax)
    data = @preprocessor.normalize_column(data, 'GF', method: :minmax)
    data = @preprocessor.normalize_column(data, 'GA', method: :minmax)
    
    # Calculate win percentage
    data.each do |row|
      games = row['GP'].to_f
      wins = row['W'].to_f
      row['win_pct'] = games > 0 ? (wins / games).round(4) : 0
    end
    
    # Step 3: Time series features
    @logger.info "\n[3/6] Engineering time series features..."
    
    if data.first.key?('date')
      # Rolling averages
      data = @ts_features.calculate_rolling_average(data, 'Team', 'PTS', window: 5)
      data = @ts_features.calculate_rolling_average(data, 'Team', 'GF', window: 5)
      data = @ts_features.calculate_rolling_average(data, 'Team', 'GA', window: 5)
      
      # Exponential weighted moving average
      data = @ts_features.calculate_ewma(data, 'Team', 'win_pct', alpha: 0.3)
      
      # Lag features
      data = @ts_features.create_lag_features(data, 'Team', 'PTS', lags: [1, 3, 5])
    end
    
    # Step 4: Advanced domain features
    @logger.info "\n[4/6] Creating advanced features..."
    
    # Team strength index
    data = @advanced.calculate_team_strength_index(data, 'Team', 'W', 'L', 'DIFF')
    
    # Pythagorean expectation
    data = @advanced.calculate_pythagorean_wins(data, 'GF', 'GA', 'GP')
    
    # Interaction features
    data = @advanced.create_interaction_features(data, 'GF', 'win_pct', 'offense_efficiency')
    data = @advanced.create_interaction_features(data, 'GA', 'win_pct', 'defense_efficiency')
    
    # Polynomial features for non-linear relationships
    data = @advanced.create_polynomial_features(data, 'DIFF', degree: 2)
    data = @advanced.create_polynomial_features(data, 'PTS', degree: 2)
    
    # Home/away splits
    if data.first.key?('HOME') && data.first.key?('AWAY')
      data.each do |row|
        home_record = row['HOME'].split('-').first.to_f rescue 0
        away_record = row['AWAY'].split('-').first.to_f rescue 0
        total_home = row['HOME'].split('-').sum { |x| x.to_i } rescue 1
        total_away = row['AWAY'].split('-').sum { |x| x.to_i } rescue 1
        
        row['home_win_rate'] = total_home > 0 ? (home_record / total_home).round(3) : 0.5
        row['away_win_rate'] = total_away > 0 ? (away_record / total_away).round(3) : 0.5
        row['home_away_diff'] = (row['home_win_rate'].to_f - row['away_win_rate'].to_f).round(3)
      end
    end
    
    # Step 5: Feature engineering summary
    @logger.info "\n[5/6] Feature engineering summary..."
    @logger.info "Total features: #{data.first.keys.size}"
    @logger.info "Sample count: #{data.size}"
    
    numeric_features = data.first.keys.select do |col|
      data.first[col].to_s.match?(/^-?\d+\.?\d*$/)
    end
    
    @logger.info "Numeric features: #{numeric_features.size}"
    @logger.info "  #{numeric_features.join(', ')}"
    
    # Step 6: Export processed data
    @logger.info "\n[6/6] Exporting processed data..."
    
    output_file = File.join(@output_dir, 'competitive_features.csv')
    CSV.open(output_file, 'w') do |csv|
      csv << data.first.keys
      data.each { |row| csv << data.first.keys.map { |k| row[k] } }
    end
    
    @logger.info "Exported to: #{output_file}"
    
    # Create train/test splits
    if data.size > 100
      @logger.info "\nCreating train/test splits..."
      
      if data.first.key?('date')
        # Time series split
        splits = @validator.time_series_cv_split(data, 'date', n_splits: 5)
        splits.each_with_index do |split, idx|
          @logger.info "Fold #{idx + 1}: Train=#{split[:train_size]}, Test=#{split[:test_size]}"
        end
      else
        # Stratified split
        if data.first.key?('playoff_status')
          split = @validator.stratified_split(data, 'playoff_status', test_size: 0.2)
          
          train_file = File.join(@output_dir, 'train.csv')
          test_file = File.join(@output_dir, 'test.csv')
          
          CSV.open(train_file, 'w') do |csv|
            csv << split[:train].first.keys
            split[:train].each { |row| csv << split[:train].first.keys.map { |k| row[k] } }
          end
          
          CSV.open(test_file, 'w') do |csv|
            csv << split[:test].first.keys
            split[:test].each { |row| csv << split[:test].first.keys.map { |k| row[k] } }
          end
          
          @logger.info "Train: #{train_file} (#{split[:train].size} samples)"
          @logger.info "Test: #{test_file} (#{split[:test].size} samples)"
        end
      end
    end
    
    @logger.info "\n" + "=" * 60
    @logger.info "PIPELINE COMPLETE - READY TO WIN!"
    @logger.info "=" * 60
    
    output_file
  end
end

# Run if called directly
if __FILE__ == $0
  if ARGV.empty?
    puts "Usage: ruby scripts/competitive_pipeline.rb <input_csv>"
    puts "Example: ruby scripts/competitive_pipeline.rb data/nhl_data.csv"
    exit 1
  end
  
  preprocessor = CompetitivePreprocessor.new(ARGV[0])
  preprocessor.run_full_pipeline
end
