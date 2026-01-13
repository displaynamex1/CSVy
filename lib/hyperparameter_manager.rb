require 'csv'
require 'yaml'
require 'logger'

class HyperparameterManager
  attr_reader :logger

  def initialize
    @logger = Logger.new(STDOUT)
    @logger.level = Logger::INFO
  end

  # Generate hyperparameter grid from configuration
  def generate_grid(config_file, output_file = nil, sample_size: nil)
    config = YAML.load_file(config_file)
    model_name = config['model_name']
    params = config['hyperparameters']
    
    @logger.info "Generating hyperparameter grid for #{model_name}"
    
    # Generate all combinations
    param_names = params.keys
    param_values = params.values
    
    grid = cartesian_product(param_values)
    
    # Sample if requested
    if sample_size && sample_size < grid.length
      @logger.info "Sampling #{sample_size} configurations from #{grid.length} total"
      grid = grid.sample(sample_size)
    end
    
    @logger.info "Generated #{grid.length} hyperparameter configurations"
    
    # Create CSV with grid
    output_file ||= "#{model_name}_grid.csv"
    
    CSV.open(output_file, 'w') do |csv|
      # Header: param names + experiment tracking columns
      headers = param_names + ['experiment_id', 'rmse', 'mae', 'r2', 'notes', 'timestamp']
      csv << headers
      
      # Write each configuration
      grid.each_with_index do |combo, idx|
        row = combo + [idx + 1, nil, nil, nil, nil, nil]
        csv << row
      end
    end
    
    @logger.info "Grid saved to #{output_file}"
    output_file
  end

  # Add experiment result to tracking file
  def add_result(tracking_file, experiment_id, metrics = {}, notes: nil)
    data = CSV.read(tracking_file, headers: true)
    
    # Find row with matching experiment_id
    row = data.find { |r| r['experiment_id'].to_i == experiment_id.to_i }
    
    unless row
      @logger.error "Experiment ID #{experiment_id} not found"
      return false
    end
    
    # Update metrics
    metrics.each do |metric, value|
      row[metric.to_s] = value.to_s if data.headers.include?(metric.to_s)
    end
    
    row['notes'] = notes if notes
    row['timestamp'] = Time.now.strftime("%Y-%m-%d %H:%M:%S")
    
    # Save back
    CSV.open(tracking_file, 'w', write_headers: true, headers: data.headers) do |csv|
      data.each { |r| csv << r }
    end
    
    @logger.info "Updated experiment #{experiment_id} with results"
    true
  end

  # Find best hyperparameters based on metric
  def find_best(tracking_file, metric: 'rmse', ascending: true)
    data = CSV.read(tracking_file, headers: true)
    
    # Filter out rows without this metric
    completed = data.select { |row| row[metric] && !row[metric].to_s.strip.empty? }
    
    if completed.empty?
      @logger.warn "No completed experiments found with metric '#{metric}'"
      return nil
    end
    
    # Sort by metric
    sorted = completed.sort_by { |row| row[metric].to_f }
    sorted.reverse! unless ascending
    
    best = sorted.first
    
    @logger.info "Best #{metric}: #{best[metric]} (Experiment #{best['experiment_id']})"
    
    # Extract hyperparameters (exclude tracking columns)
    tracking_cols = ['experiment_id', 'rmse', 'mae', 'r2', 'notes', 'timestamp']
    hyperparam_cols = data.headers - tracking_cols
    
    best_params = {}
    hyperparam_cols.each { |col| best_params[col] = best[col] }
    
    best_params
  end

  # Export hyperparameters in different formats
  def export_params(config_file, format: :python, output_file: nil)
    config = YAML.load_file(config_file)
    model_name = config['model_name']
    defaults = config['defaults'] || {}
    
    output = case format.to_sym
    when :python
      export_python(defaults, model_name)
    when :json
      require 'json'
      JSON.pretty_generate(defaults)
    when :yaml
      YAML.dump(defaults)
    when :ruby
      export_ruby(defaults, model_name)
    else
      raise ArgumentError, "Unknown format: #{format}"
    end
    
    if output_file
      File.write(output_file, output)
      @logger.info "Exported to #{output_file}"
    else
      puts output
    end
    
    output
  end

  # Generate random search sample
  def random_search(config_file, n_samples, output_file = nil)
    config = YAML.load_file(config_file)
    model_name = config['model_name']
    params = config['hyperparameters']
    
    @logger.info "Generating #{n_samples} random configurations for #{model_name}"
    
    samples = []
    n_samples.times do |i|
      sample = {}
      params.each do |name, values|
        sample[name] = values.sample
      end
      samples << sample
    end
    
    # Write to CSV
    output_file ||= "#{model_name}_random_search.csv"
    
    CSV.open(output_file, 'w') do |csv|
      headers = params.keys + ['experiment_id', 'rmse', 'mae', 'r2', 'notes', 'timestamp']
      csv << headers
      
      samples.each_with_index do |sample, idx|
        row = sample.values + [idx + 1, nil, nil, nil, nil, nil]
        csv << row
      end
    end
    
    @logger.info "Random search configurations saved to #{output_file}"
    output_file
  end

  # Compare multiple experiments
  def compare_experiments(tracking_file, experiment_ids)
    data = CSV.read(tracking_file, headers: true)
    
    experiments = experiment_ids.map do |id|
      data.find { |row| row['experiment_id'].to_i == id.to_i }
    end.compact
    
    if experiments.empty?
      @logger.error "No experiments found with provided IDs"
      return
    end
    
    # Display comparison table
    puts "\n=== Experiment Comparison ==="
    puts "ID\tRMSE\tMAE\tR2\tNotes"
    puts "-" * 60
    
    experiments.each do |exp|
      puts "#{exp['experiment_id']}\t#{exp['rmse']}\t#{exp['mae']}\t#{exp['r2']}\t#{exp['notes']}"
    end
    
    experiments
  end

  private

  def cartesian_product(arrays)
    return [[]] if arrays.empty?
    
    first = arrays[0]
    rest = cartesian_product(arrays[1..-1])
    
    result = []
    first.each do |elem|
      rest.each do |combo|
        result << [elem] + combo
      end
    end
    result
  end

  def export_python(params, model_name)
    lines = ["# Hyperparameters for #{model_name}", ""]
    lines << "params = {"
    params.each do |key, value|
      formatted_value = value.is_a?(String) ? "'#{value}'" : value
      lines << "    '#{key}': #{formatted_value},"
    end
    lines << "}"
    lines.join("\n")
  end

  def export_ruby(params, model_name)
    lines = ["# Hyperparameters for #{model_name}", ""]
    lines << "params = {"
    params.each do |key, value|
      formatted_value = value.is_a?(String) ? "'#{value}'" : value
      lines << "  '#{key}' => #{formatted_value},"
    end
    lines << "}"
    lines.join("\n")
  end
end
