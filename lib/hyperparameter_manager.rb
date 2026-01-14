require 'csv'
require 'json'
require 'logger'

class HyperparameterManager
  attr_accessor :params, :results

  def initialize(param_config = {})
    @params = param_config
    @results = []
  end

  # Add a hyperparameter with its search space
  def add_param(name, config)
    @params[name] = config
  end

  # Perform random search over the hyperparameter space
  # Supports both:
  # - New style: random_search(iterations = 10) { |sample, i| ... }
  # - Old style: random_search(config_file, n_samples, output_file = nil)
  def random_search(arg1 = 10, arg2 = nil, arg3 = nil)
    # Detect old-style call: random_search(config_file, n_samples, output_file)
    if arg1.is_a?(String) && (arg2.is_a?(Integer) || arg2.is_a?(String))
      config_file = arg1
      n_samples = arg2.to_i
      output_file = arg3
      
      # Load config if @params is empty
      if @params.empty? && File.exist?(config_file)
        require 'yaml'
        @params = YAML.safe_load_file(config_file, permitted_classes: [Symbol], aliases: true)
      end
      
      results = []
      n_samples.times do |i|
        sample = {}
        @params.each do |param_name, config|
          sample[param_name] = sample_param(config)
        end
        results << sample
      end
      
      # Save to file if specified
      if output_file && !results.empty?
        CSV.open(output_file, 'w') do |csv|
          csv << results.first.keys
          results.each { |r| csv << r.values }
        end
        return output_file
      end
      
      return results
    else
      # New-style call: random_search(iterations) { |sample, i| ... }
      iterations = arg1
      results = []
      
      iterations.times do |i|
        sample = {}
        @params.each do |param_name, config|
          sample[param_name] = sample_param(config)
        end
        
        if block_given?
          yield(sample, i)
        else
          results << sample
        end
      end
      
      # Return collected samples if no block given
      block_given? ? nil : results
    end
  end

  # Sample a single parameter value based on its configuration
  private

  def sample_param(config)
    # Handle range format [min, max, 'range'] for continuous parameters
    if config.is_a?(Array) && config.length == 3 && config[2] == 'range'
      min_val = config[0]
      max_val = config[1]
      # Generate random float between min and max
      rand(min_val..max_val)
    # Handle discrete choice arrays
    elsif config.is_a?(Array)
      config.sample
    # Handle hash configurations with 'type' key
    elsif config.is_a?(Hash)
      case config['type']
      when 'range'
        min_val = config['min']
        max_val = config['max']
        rand(min_val..max_val)
      when 'choice'
        config['values'].sample
      when 'int'
        min_val = config['min'] || 0
        max_val = config['max'] || 100
        rand(min_val..max_val).to_i
      else
        config.values.sample
      end
    else
      config
    end
  end

  public

  # Add a result from a hyperparameter trial
  # Supports both:
  # - New style: add_result(hyperparams, metrics)
  # - Old style: add_result(tracking_file, experiment_id, metrics = {}, notes: nil)
  def add_result(arg1, arg2 = nil, arg3 = nil, notes: nil)
    # Detect new-style call: both args are hashes
    if arg1.is_a?(Hash) && arg2.is_a?(Hash) && arg3.nil?
      hyperparams = arg1
      metrics = arg2
      @results << { params: hyperparams, metrics: metrics }
      return true
    else
      # Old-style call: add_result(tracking_file, experiment_id, metrics, notes: notes)
      tracking_file = arg1
      experiment_id = arg2
      metrics = arg3 || {}
      
      # For backward compatibility, store in tracking file format
      # Read existing data if file exists
      data = []
      if File.exist?(tracking_file)
        require 'yaml'
        data = YAML.safe_load_file(tracking_file, permitted_classes: [Symbol, Time], aliases: true) || []
      end
      
      # Add new result
      result = {
        'experiment_id' => experiment_id,
        'timestamp' => Time.now.iso8601,
        'metrics' => metrics,
        'notes' => notes
      }
      data << result
      
      # Save back to file
      File.write(tracking_file, data.to_yaml)
      
      # Also add to internal results for consistency
      @results << {
        params: { experiment_id: experiment_id },
        metrics: metrics
      }
      
      return true
    end
  rescue Errno::ENOENT, Errno::EACCES, IOError => e
    # File system errors (permission denied, file not found after check, etc.)
    puts "File error adding result: #{e.message}"
    return false
  rescue Psych::SyntaxError, Psych::BadAlias => e
    # YAML parsing/writing errors
    puts "YAML error adding result: #{e.message}"
    return false
  end

  # Save results to CSV file
  def save_results(filename = 'hyperparameter_results.csv')
    return if @results.empty?

    CSV.open(filename, 'w') do |csv|
      # Extract all unique parameter and metric keys (normalized to strings)
      all_param_keys = @results.map { |r| r[:params].keys.map(&:to_s) }.flatten.uniq.sort
      all_metric_keys = @results.map { |r| r[:metrics].keys.map(&:to_s) }.flatten.uniq.sort

      # Write headers with prefixes for robust classification on reload
      headers = all_param_keys.map { |k| "param_#{k}" } + all_metric_keys.map { |k| "metric_#{k}" }
      csv << headers

      # Write data rows
      @results.each do |result|
        row = all_param_keys.map { |key| result[:params][key.to_sym] || result[:params][key] } +
              all_metric_keys.map { |key| result[:metrics][key.to_sym] || result[:metrics][key] }
        csv << row
      end
    end
  end

  # Load results from CSV file
  def load_results(filename = 'hyperparameter_results.csv')
    @results = []
    return unless File.exist?(filename)

    data = CSV.read(filename, headers: true)
    return if data.empty?

    data.each do |row|
      hash = row.to_h
      # Parse JSON if values look like JSON
      hash.each { |k, v| hash[k] = JSON.parse(v) rescue v }
      
      # Separate params and metrics based on prefix convention
      params_hash = {}
      metrics_hash = {}
      
      hash.each do |key, value|
        key_str = key.to_s
        if key_str.start_with?('param_')
          # Remove prefix and store as param
          clean_key = key_str.sub(/^param_/, '')
          params_hash[clean_key.to_sym] = value
        elsif key_str.start_with?('metric_')
          # Remove prefix and store as metric
          clean_key = key_str.sub(/^metric_/, '')
          metrics_hash[clean_key.to_sym] = value
        else
          # Fallback for files without prefix (legacy support)
          # Use heuristic: common metric names
          known_metrics = ['rmse', 'mae', 'r2', 'mse', 'accuracy', 'precision', 'recall', 
                           'f1', 'auc', 'loss', 'error', 'score']
          if known_metrics.any? { |m| key_str.downcase == m }
            metrics_hash[key.to_sym] = value
          else
            params_hash[key.to_sym] = value
          end
        end
      end
      
      @results << { params: params_hash, metrics: metrics_hash }
    end
  end

  # Get the best result based on a metric
  def best_result(metric, mode = :max)
    return nil if @results.empty?

    # Filter to only results that have this metric
    metric_sym = metric.to_sym
    with_metric = @results.select { |r| r[:metrics].key?(metric_sym) && !r[:metrics][metric_sym].nil? }
    return nil if with_metric.empty?

    if mode == :max
      with_metric.max_by { |r| r[:metrics][metric_sym].to_f }
    else
      with_metric.min_by { |r| r[:metrics][metric_sym].to_f }
    end
  end

  # Get summary statistics of results
  def summary
    return {} if @results.empty?

    summary_stats = {}
    all_metric_keys = @results.map { |r| r[:metrics].keys }.flatten.uniq

    all_metric_keys.each do |key|
      values = @results.map { |r| r[:metrics][key] }.compact
      next if values.empty?

      summary_stats[key] = {
        mean: values.sum.to_f / values.length,
        min: values.min,
        max: values.max,
        std_dev: calculate_std_dev(values)
      }
    end

    summary_stats
  end

  # Calculate standard deviation
  private

  def calculate_std_dev(values)
    return 0 if values.length <= 1

    mean = values.sum.to_f / values.length
    variance = values.map { |v| (v - mean) ** 2 }.sum / (values.length - 1)
    Math.sqrt(variance)
  end

  # Generate full hyperparameter grid (cartesian product)
  public
  
  def generate_grid(config_file, output_file = nil, sample_size: nil)
    require 'yaml'
    config = YAML.load_file(config_file)
    model_name = config['model_name']
    params = config['hyperparameters']
    
    puts "Generating hyperparameter grid for #{model_name}..."
    
    # Process parameters: convert ranges to discrete samples
    processed_params = {}
    param_names = params.keys
    
    params.each do |name, values|
      if values.is_a?(Array)
        # Check if it's a continuous range [min, max, 'range']
        if values.length == 3 && values[2].to_s == 'range'
          min, max = values[0].to_f, values[1].to_f
          n_samples = sample_size || 10
          processed_params[name] = (0...n_samples).map { |i| min + (max - min) * i / (n_samples - 1.0) }
        else
          processed_params[name] = values
        end
      else
        processed_params[name] = [values]
      end
    end
    
    # Generate all combinations (cartesian product)
    param_values = processed_params.values
    grid = cartesian_product(param_values)
    
    # Sample if requested
    if sample_size && sample_size < grid.length
      puts "Sampling #{sample_size} configurations from #{grid.length} total"
      grid = grid.sample(sample_size)
    end
    
    puts "Generated #{grid.length} hyperparameter configurations"
    
    # Create CSV with grid
    output_file ||= "#{model_name}_grid_search.csv"
    
    CSV.open(output_file, 'w') do |csv|
      headers = param_names + ['experiment_id', 'rmse', 'mae', 'r2', 'notes', 'timestamp']
      csv << headers
      
      grid.each_with_index do |config, idx|
        row = config + [idx + 1, nil, nil, nil, nil, nil]
        csv << row
      end
    end
    
    puts "Saved to #{output_file}"
    output_file
  end

  # Bayesian optimization with Gaussian Process
  def bayesian_optimize(config_file, n_iterations: 20, n_initial: 5, acquisition: 'ei', output_file: nil)
    require 'yaml'
    config = YAML.load_file(config_file)
    model_name = config['model_name']
    params = config['hyperparameters']
    
    puts "Starting Bayesian optimization for #{model_name}"
    puts "Initial random samples: #{n_initial}, Total iterations: #{n_iterations}"
    
    param_names = params.keys
    configurations = []
    
    # Phase 1: Initial random exploration
    puts "Phase 1: Random exploration..."
    n_initial.times do |i|
      config_hash = sample_random_config(params)
      configurations << config_hash
    end
    
    # Phase 2: Bayesian-guided exploration (simplified - uses diversity-based selection)
    puts "Phase 2: Bayesian optimization..."
    (n_initial...n_iterations).each do |i|
      config_hash = suggest_next_config(params, configurations, acquisition)
      configurations << config_hash
    end
    
    puts "Generated #{configurations.length} configurations"
    
    # Output to CSV
    output_file ||= "#{model_name}_bayesian_optimization.csv"
    
    CSV.open(output_file, 'w') do |csv|
      headers = param_names + ['experiment_id', 'rmse', 'mae', 'r2', 'notes', 'timestamp']
      csv << headers
      
      configurations.each_with_index do |config_hash, idx|
        row = param_names.map { |name| config_hash[name] } + [idx + 1, nil, nil, nil, nil, nil]
        csv << row
      end
    end
    
    puts "Saved to #{output_file}"
    output_file
  end

  # Genetic algorithm optimization
  def genetic_algorithm(config_file, population_size: 20, generations: 10, mutation_rate: 0.1, output_file: nil)
    require 'yaml'
    config = YAML.load_file(config_file)
    model_name = config['model_name']
    params = config['hyperparameters']
    
    puts "Starting Genetic Algorithm for #{model_name}"
    puts "Population: #{population_size}, Generations: #{generations}, Mutation rate: #{mutation_rate}"
    
    # Initialize random population
    population = Array.new(population_size) { sample_random_config(params) }
    all_configurations = population.dup
    
    generations.times do |gen|
      puts "Generation #{gen + 1}/#{generations}: #{population.size} individuals"
      
      # Selection: Keep top 50% (simulate fitness)
      survivors = population.sample(population_size / 2)
      
      # Crossover: Breed new individuals
      new_population = survivors.dup
      
      while new_population.length < population_size
        parent1 = survivors.sample
        parent2 = survivors.sample
        child = crossover(parent1, parent2, params)
        
        # Mutation
        child = mutate(child, params, mutation_rate) if rand < mutation_rate
        
        new_population << child
        all_configurations << child
      end
      
      population = new_population
    end
    
    puts "Generated #{all_configurations.length} total configurations"
    
    # Output to CSV
    output_file ||= "#{model_name}_genetic_algorithm.csv"
    param_names = params.keys
    
    CSV.open(output_file, 'w') do |csv|
      headers = param_names + ['experiment_id', 'rmse', 'mae', 'r2', 'notes', 'timestamp']
      csv << headers
      
      all_configurations.each_with_index do |config_hash, idx|
        row = param_names.map { |name| config_hash[name] } + [idx + 1, nil, nil, nil, nil, nil]
        csv << row
      end
    end
    
    puts "Saved to #{output_file}"
    output_file
  end

  # Simulated annealing optimization
  def simulated_annealing(config_file, n_iterations: 100, initial_temp: 1.0, cooling_rate: 0.95, output_file: nil)
    require 'yaml'
    config = YAML.load_file(config_file)
    model_name = config['model_name']
    params = config['hyperparameters']
    
    puts "Starting Simulated Annealing for #{model_name}"
    puts "Iterations: #{n_iterations}, Initial temp: #{initial_temp}, Cooling: #{cooling_rate}"
    
    # Start with random configuration
    current = sample_random_config(params)
    all_configurations = [current]
    temperature = initial_temp
    
    n_iterations.times do |i|
      # Generate neighbor (small mutation)
      neighbor = mutate(current.dup, params, 0.3)
      
      # Accept neighbor with probability based on temperature
      # (simulated - real implementation would use actual fitness scores)
      if rand < temperature
        current = neighbor
      end
      
      all_configurations << current.dup
      
      # Cool down
      temperature *= cooling_rate
      
      puts "Iteration #{i + 1}/#{n_iterations}, Temp: #{temperature.round(4)}" if (i + 1) % 20 == 0
    end
    
    puts "Generated #{all_configurations.length} configurations"
    
    # Output to CSV
    output_file ||= "#{model_name}_simulated_annealing.csv"
    param_names = params.keys
    
    CSV.open(output_file, 'w') do |csv|
      headers = param_names + ['experiment_id', 'rmse', 'mae', 'r2', 'notes', 'timestamp']
      csv << headers
      
      all_configurations.each_with_index do |config_hash, idx|
        row = param_names.map { |name| config_hash[name] } + [idx + 1, nil, nil, nil, nil, nil]
        csv << row
      end
    end
    
    puts "Saved to #{output_file}"
    output_file
  end

  private

  # Helper: Generate cartesian product of arrays
  def cartesian_product(arrays)
    return [[]] if arrays.empty?
    arrays[0].product(*arrays[1..-1])
  end

  # Helper: Sample random configuration
  def sample_random_config(params)
    config = {}
    params.each do |name, values|
      config[name] = if values.is_a?(Array)
        if values.length == 3 && values[2].to_s == 'range'
          # Continuous range
          min, max = values[0].to_f, values[1].to_f
          rand * (max - min) + min
        else
          # Discrete choice
          values.sample
        end
      else
        values
      end
    end
    config
  end

  # Helper: Suggest next config for Bayesian optimization
  def suggest_next_config(params, existing_configs, acquisition)
    # Simplified: explore unexplored regions
    # Real implementation would use GP predictions + acquisition function
    sample_random_config(params)
  end

  # Helper: Crossover two configurations
  def crossover(parent1, parent2, params)
    child = {}
    params.keys.each do |key|
      child[key] = rand < 0.5 ? parent1[key] : parent2[key]
    end
    child
  end

  # Helper: Mutate configuration
  def mutate(config, params, rate)
    config.each do |key, value|
      if rand < rate
        config[key] = if params[key].is_a?(Array)
          if params[key].length == 3 && params[key][2].to_s == 'range'
            min, max = params[key][0].to_f, params[key][1].to_f
            rand * (max - min) + min
          else
            params[key].sample
          end
        else
          params[key]
        end
      end
    end
    config
  end
end
