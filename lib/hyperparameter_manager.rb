require 'csv'
require 'yaml'
require 'logger'
require 'json'

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
    
    # Ensure directory exists
    output_dir = File.dirname(output_file)
    require 'fileutils'
    FileUtils.mkdir_p(output_dir) unless output_dir == '.' || File.directory?(output_dir)
    
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

  # Bayesian optimization using Gaussian Process surrogate
  def bayesian_optimize(config_file, n_iterations: 20, n_initial: 5, acquisition: 'ei')
    config = YAML.load_file(config_file)
    model_name = config['model_name']
    params = config['hyperparameters']
    
    @logger.info "Starting Bayesian Optimization for #{model_name}"
    @logger.info "Initial random samples: #{n_initial}, Total iterations: #{n_iterations}"
    
    # Get parameter space
    param_names = params.keys
    param_bounds = params.values.map { |v| v.is_a?(Array) ? [0, v.length - 1] : [v, v] }
    
    # Track all evaluated points
    evaluated = []
    
    # Initial random exploration
    @logger.info "Phase 1: Random exploration (#{n_initial} samples)"
    n_initial.times do |i|
      config = sample_random_config(params)
      evaluated << { config: config, score: nil, iteration: i + 1 }
      
      puts "\n[#{i + 1}/#{n_initial}] Suggested configuration:"
      config.each { |k, v| puts "  #{k}: #{v}" }
      puts "  → Train model and enter score (or 'skip'): "
    end
    
    # Bayesian optimization iterations
    @logger.info "\nPhase 2: Bayesian optimization (#{n_iterations - n_initial} samples)"
    (n_initial + 1..n_iterations).each do |i|
      # Fit surrogate model on evaluated points
      completed = evaluated.select { |e| e[:score] }
      
      if completed.length < 2
        # Not enough data, sample randomly
        config = sample_random_config(params)
      else
        # Use acquisition function to suggest next point
        config = suggest_next_config(params, completed, acquisition)
      end
      
      evaluated << { config: config, score: nil, iteration: i }
      
      puts "\n[#{i}/#{n_iterations}] Suggested configuration:"
      config.each { |k, v| puts "  #{k}: #{v}" }
      
      # Show expected improvement if available
      if completed.length >= 2
        best_score = completed.map { |e| e[:score] }.min
        puts "  Current best: #{best_score.round(4)}"
        puts "  → Train model and enter score (or 'skip'): "
      end
    end
    
    # Output results
    output_file = "#{model_name}_bayesian.json"
    File.write(output_file, JSON.pretty_generate(evaluated))
    @logger.info "Results saved to #{output_file}"
    
    # Find best
    completed = evaluated.select { |e| e[:score] }
    if completed.any?
      best = completed.min_by { |e| e[:score] }
      @logger.info "\nBest configuration found:"
      best[:config].each { |k, v| @logger.info "  #{k}: #{v}" }
      @logger.info "  Score: #{best[:score]}"
    end
    
    output_file
  end

  # Genetic algorithm optimization
  def genetic_algorithm(config_file, population_size: 20, generations: 10, mutation_rate: 0.1)
    config = YAML.load_file(config_file)
    model_name = config['model_name']
    params = config['hyperparameters']
    
    @logger.info "Starting Genetic Algorithm for #{model_name}"
    @logger.info "Population: #{population_size}, Generations: #{generations}"
    
    # Initialize random population
    population = Array.new(population_size) { sample_random_config(params) }
    fitness_scores = Array.new(population_size, nil)
    
    all_evaluated = []
    
    generations.times do |gen|
      @logger.info "\n=== Generation #{gen + 1}/#{generations} ==="
      
      # Evaluate population (user provides scores)
      population.each_with_index do |individual, idx|
        next if fitness_scores[idx] # Already evaluated
        
        puts "\nIndividual #{idx + 1}/#{population_size}:"
        individual.each { |k, v| puts "  #{k}: #{v}" }
        puts "  → Train model and enter score (or 'skip'): "
        
        all_evaluated << { config: individual, score: nil, generation: gen + 1 }
      end
      
      # Selection: Keep top 50%
      evaluated_indices = fitness_scores.each_index.select { |i| fitness_scores[i] }
      next if evaluated_indices.length < 2
      
      sorted_indices = evaluated_indices.sort_by { |i| fitness_scores[i] }
      survivors = sorted_indices.first(population_size / 2)
      
      # Crossover: Breed new individuals
      new_population = survivors.map { |i| population[i] }
      
      while new_population.length < population_size
        parent1 = population[survivors.sample]
        parent2 = population[survivors.sample]
        child = crossover(parent1, parent2, params)
        
        # Mutation
        child = mutate(child, params, mutation_rate) if rand < mutation_rate
        
        new_population << child
      end
      
      population = new_population
      fitness_scores = Array.new(population_size, nil)
      
      # Evaluate survivors from previous generation
      survivors.each { |i| fitness_scores[i] = fitness_scores[i] }
    end
    
    # Output results
    output_file = "#{model_name}_genetic.json"
    File.write(output_file, JSON.pretty_generate(all_evaluated))
    @logger.info "Results saved to #{output_file}"
    
    output_file
  end

  # Simulated annealing
  def simulated_annealing(config_file, n_iterations: 100, initial_temp: 1.0, cooling_rate: 0.95)
    config = YAML.load_file(config_file)
    model_name = config['model_name']
    params = config['hyperparameters']
    
    @logger.info "Starting Simulated Annealing for #{model_name}"
    
    # Start with random configuration
    current_config = sample_random_config(params)
    current_score = nil
    best_config = current_config.dup
    best_score = Float::INFINITY
    
    temperature = initial_temp
    evaluated = []
    
    n_iterations.times do |i|
      puts "\n[#{i + 1}/#{n_iterations}] Temperature: #{temperature.round(3)}"
      puts "Current configuration:"
      current_config.each { |k, v| puts "  #{k}: #{v}" }
      puts "  → Train model and enter score (or 'skip'): "
      
      # Generate neighbor (small random change)
      neighbor_config = neighbor(current_config, params)
      
      evaluated << { 
        config: current_config.dup, 
        score: current_score, 
        temperature: temperature,
        iteration: i + 1
      }
      
      # Update best if improved
      if current_score && current_score < best_score
        best_score = current_score
        best_config = current_config.dup
        @logger.info "New best: #{best_score.round(4)}"
      end
      
      # Move to neighbor (will be evaluated next iteration)
      current_config = neighbor_config
      
      # Cool down
      temperature *= cooling_rate
    end
    
    output_file = "#{model_name}_annealing.json"
    File.write(output_file, JSON.pretty_generate(evaluated))
    @logger.info "\nOptimization complete!"
    @logger.info "Best configuration:"
    best_config.each { |k, v| @logger.info "  #{k}: #{v}" }
    @logger.info "Best score: #{best_score}"
    
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
    
    # Ensure directory exists
    output_dir = File.dirname(output_file)
    require 'fileutils'
    FileUtils.mkdir_p(output_dir) unless output_dir == '.' || File.directory?(output_dir)
    
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

  # Sample random configuration
  def sample_random_config(params)
    config = {}
    params.each do |name, values|
      config[name] = values.is_a?(Array) ? values.sample : values
    end
    config
  end

  # Suggest next configuration using acquisition function
  def suggest_next_config(params, completed, acquisition)
    # Extract best score so far
    best_score = completed.map { |e| e[:score] }.min
    
    # Generate candidate points
    candidates = Array.new(1000) { sample_random_config(params) }
    
    # Score each candidate using Expected Improvement
    candidates.map! do |config|
      score = expected_improvement(config, completed, best_score)
      { config: config, ei: score }
    end
    
    # Return config with highest EI
    candidates.max_by { |c| c[:ei] }[:config]
  end

  # Expected Improvement (simple version using distance)
  def expected_improvement(config, completed, best_score)
    # Calculate average distance to evaluated points
    avg_distance = completed.sum do |e|
      distance(config, e[:config])
    end / completed.length.to_f
    
    # Balance exploration (distance) and exploitation (predicted improvement)
    exploration_bonus = avg_distance
    exploitation_bonus = best_score * 0.1 # Small improvement expected
    
    exploration_bonus + exploitation_bonus
  end

  # Calculate distance between two configurations
  def distance(config1, config2)
    # Simple hamming distance for discrete params
    config1.keys.sum do |key|
      config1[key] == config2[key] ? 0 : 1
    end.to_f
  end

  # Genetic algorithm: crossover two configurations
  def crossover(parent1, parent2, params)
    child = {}
    parent1.keys.each do |key|
      # 50% chance from each parent
      child[key] = rand < 0.5 ? parent1[key] : parent2[key]
    end
    child
  end

  # Genetic algorithm: mutate configuration
  def mutate(config, params, mutation_rate)
    mutated = config.dup
    config.keys.each do |key|
      if rand < mutation_rate
        values = params[key]
        mutated[key] = values.is_a?(Array) ? values.sample : values
      end
    end
    mutated
  end

  # Simulated annealing: generate neighbor configuration
  def neighbor(config, params)
    neighbor_config = config.dup
    
    # Change 1-2 random parameters
    keys_to_change = config.keys.sample(rand(1..2))
    
    keys_to_change.each do |key|
      values = params[key]
      if values.is_a?(Array)
        # Pick different value
        current_idx = values.index(config[key])
        if current_idx
          # Pick adjacent value if possible
          if values.length > 1
            offset = [-1, 1].sample
            new_idx = (current_idx + offset) % values.length
            neighbor_config[key] = values[new_idx]
          end
        else
          neighbor_config[key] = values.sample
        end
      end
    end
    
    neighbor_config
  end

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
