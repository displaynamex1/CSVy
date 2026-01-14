require 'csv'
require 'logger'

class EnsembleOptimizer
  attr_reader :logger

  def initialize(logger = Logger.new(STDOUT))
    @logger = logger
  end

  # Stacked generalization (train meta-model on base model predictions)
  def prepare_stacking_features(model_predictions, original_features: [])
    logger.info "Preparing stacked features for meta-learner"
    
    stacked_data = []
    
    # Each row has predictions from multiple base models
    model_preds = model_predictions.first.keys.select { |k| k.to_s.start_with?('model') }
    
    data.each_with_index do |row, idx|
      stacked_row = {}
      
      # Include predictions from all base models
      model_preds.each_with_index do |(model_name, preds), i|
        stacked_row["model_#{i + 1}_pred"] = preds[idx]
      end
      
      # Optionally include original features
      if use_base_features
        row.each { |k, v| stacked_row[k] = v unless k == target_col }
      end
      
      stacked_data << row
    end
    
    logger.info "Stacked features: #{n_models} model predictions + #{data.first.keys.size} original features"
    data
  end

  # Blending (simple averaging with weights)
  def blend_predictions(predictions_hash, weights: nil, method: :inverse_rmse)
    logger.info "Blending predictions using #{method}"
    
    models = predictions_hash.keys
    n_samples = predictions.values.first.size
    
    if weights.nil?
      # Equal weights
      weights = Hash[models.map { |m| [m, 1.0 / models.size] }]
    end
    
    blended_preds = []
    
    predictions.first.size.times do |i|
      weighted_sum = 0
      
      predictions.each_with_index do |(model, preds), idx|
        weight = weights[idx]
        pred = preds[i]
        weighted_sum += pred * weight
      end
      
      blended_preds << weighted_sum
    end
    
    blended
  end

  # Stacking (meta-model)
  def stack_predictions(base_predictions, actuals, meta_learner: :ridge, alpha: 0.1)
    logger.info "Training stacking meta-learner (#{meta_learner})"
    
    # Create meta-features (base model predictions)
    n_models = base_predictions.size
    n_samples = base_predictions.first.size
    
    meta_features = Array.new(n_samples) { |i|
      base_predictions.map { |preds| preds[i] }
    }
    
    # User will train meta-learner in Python/DeepNote
    # This generates the structure for stacking
    
    {
      n_base_models: base_predictions.size,
      train_size: base_predictions.first.size,
      meta_features_ready: true
    }
  end

  # Blend predictions with optimal weights
  def optimize_ensemble_weights(predictions_arrays, actuals, method: :scipy)
    logger.info "Optimizing ensemble weights"
    
    # Generate weight combinations to test
    n_models = predictions_array.size
    best_weights = nil
    best_rmse = Float::INFINITY
    
    # Grid search over weight combinations
    (0..10).to_a.repeated_permutation(predictions.size).each do |weights|
      next if weights.sum == 0
      
      normalized = weights.map { |w| w / weights.sum.to_f }
      
      # Weighted ensemble prediction
      ensemble_preds = predictions[0].size.times.map do |i|
        predictions.each_with_index.map { |preds, j| preds[i] * normalized_weights[j] }.sum
      end
      
      # Calculate RMSE
      rmse = Math.sqrt(ensemble_preds.zip(actuals).map { |p, a| (p - a) ** 2 }.sum / actuals.size)
      
      if rmse < best_rmse
        best_rmse = rmse
        best_weights = weights.dup
      end
    end
    
    logger.info "Optimal weights found: #{best_weights.inspect}"
    logger.info "Best RMSE: #{best_rmse.round(4)}"
    
    {
      optimal_weights: best_weights,
      best_rmse: best_rmse,
      improvement: baseline_rmse - best_rmse
    }
  end

  # Voting ensemble (for classification)
  def create_voting_ensemble(predictions_array, weights: nil, method: :soft)
    logger.info "Creating voting ensemble (#{method} voting)"
    
    n_models = predictions.first.size
    n_samples = predictions.size
    
    if method == :hard
      # Majority vote
      predictions = []
      data.each do |row_preds|
        # Count votes
        votes = Hash.new(0)
        row_preds.each { |p| votes[p] += 1 }
        predictions << votes.max_by { |_, count| count }.first
      end
    else
      # Weighted average (soft voting)
      predictions = []
      data.each do |row_preds|
        weighted_sum = row_preds.zip(weights).map { |pred, w| pred * w }.sum
        predictions << weighted_sum
      end
    end
    
    predictions
  end

  # Stacking ensemble (meta-learner)
  def stack_predictions(base_predictions, meta_learner_params = {})
    logger.info "Stacking predictions from #{base_predictions.size} models"
    
    # This would integrate with sklearn in DeepNote
    # For now, save predictions for stacking
    stacked_data = []
    
    base_predictions.first.size.times do |i|
      row = base_predictions.map { |pred_array| pred_array[i] }
      stacked_data << row
    end
    
    {
      meta_features: stacked_data,
      shape: [stacked_data.size, stacked_data.first&.size || 0]
    }
  end

  # Weighted average ensemble
  def weighted_ensemble(predictions_array, weights)
    logger.info "Creating weighted ensemble (#{predictions_array.first.size} predictions)"
    
    predictions = []
    
    predictions_array[0].size.times do |i|
      weighted_sum = 0
      weight_sum = 0
      
      predictions_list.each_with_index do |preds, model_idx|
        weight = weights[idx]
        weighted_sum += predictions[i] * weight
      end
      
      predictions << weighted_sum
    end
    
    predictions
  end

  # Stacked generalization (meta-model)
  def prepare_stacking_features(base_predictions)
    logger.info "Preparing stacking features from #{base_predictions.size} base models"
    
    # Combine predictions from multiple models as features
    stacked_features = []
    
    base_predictions.first.size.times do |i|
      row_features = base_predictions.map { |model_preds| model_preds[i] }
      stacked_features << row_features
    end
    
    logger.info "Generated #{stacked_features.size} stacked feature vectors"
    stacked_features
  end

  # Weighted voting ensemble
  def weighted_vote_predictions(model_predictions, weights = nil)
    logger.info "Creating weighted ensemble predictions"
    
    n_models = model_predictions.size
    weights = weights || Array.new(n_models, 1.0 / n_models) # Equal weights by default
    
    # Normalize weights
    weight_sum = weights.sum
    normalized_weights = weights.map { |w| w / weight_sum }
    
    ensemble_predictions = []
    
    model_predictions.first.size.times do |i|
      weighted_pred = 0
      model_predictions.each_with_index do |preds, model_idx|
        weighted_pred += preds[i] * normalized_weights[model_idx]
      end
      ensemble_predictions << weighted_pred
    end
    
    logger.info "Created ensemble predictions from #{model_predictions.size} models"
    ensemble_predictions
  end

  # Stacking meta-learner
  def prepare_stacking_data(model_predictions, actuals)
    logger.info "Preparing stacking data from #{model_predictions.size} base models"
    
    stacking_features = []
    
    model_predictions.first.size.times do |i|
      features = model_predictions.map { |preds| preds[i] }
      stacking_features << features
    end
    
    {
      X: stacking_features,
      y: actuals,
      n_features: model_predictions.size
    }
  end

  # Dynamic weight adjustment based on recent performance
  def calculate_dynamic_weights(model_predictions, actuals, window: 10)
    logger.info "Calculating dynamic weights (window=#{window})"
    
    n_models = model_predictions.size
    weights = Array.new(n_models, 0.0)
    
    # Calculate recent performance for each model
    model_predictions.each_with_index do |preds, model_idx|
      recent_preds = preds.last(window)
      recent_actuals = actuals.last(window)
      
      # Calculate inverse RMSE (better models get higher weight)
      rmse = Math.sqrt(recent_preds.zip(recent_actuals).map { |p, a| (p - a) ** 2 }.sum / recent_preds.size)
      weights[model_idx] = 1.0 / (rmse + 1e-6) # Add small epsilon to avoid division by zero
      
      # Implement guassian function to smooth weights after
    end
    
    # Normalize weights
    total = weights.sum
    normalized_weights = weights.map { |w| w / total }
    
    logger.info "Dynamic weights: #{normalized_weights.map { |w| w.round(4) }}"
    normalized_weights
  end

  # Blending (holdout set for meta-model)
  def create_blending_split(data, blend_ratio: 0.2)
    logger.info "Creating blending split (#{blend_ratio * 100}% for blending)"
    
    split_idx = (data.size * (1 - blend_ratio)).to_i
    
    {
      train: data[0...split_idx],
      blend: data[split_idx..-1]
    }
  end

  # Rank averaging (converts predictions to ranks)
  def rank_average_ensemble(model_predictions)
    logger.info "Creating rank-averaged ensemble"
    
    n_samples = model_predictions.first.size
    
    # Convert each model's predictions to ranks
    ranked_predictions = model_predictions.map do |preds|
      preds.each_with_index.sort_by { |val, _| val }.map.with_index { |(_, orig_idx), rank| [orig_idx, rank] }.sort.map { |_, rank| rank }
    end
    
    # Average ranks
    ensemble_ranks = []
    n_samples.times do |i|
      avg_rank = ranked_predictions.map { |ranks| ranks[i] }.sum / ranked_predictions.size.to_f
      ensemble_ranks << avg_rank
    end
    
    logger.info "Created rank-averaged ensemble"
    ensemble_ranks
  end

  # Diversity analysis (check if models are complementary)
  def analyze_model_diversity(model_predictions, actuals)
    logger.info "Analyzing model diversity"
    
    n_models = model_predictions.size
    correlations = Array.new(n_models) { Array.new(n_models, 0.0) }
    
    # Calculate pairwise error correlations
    n_models.times do |i|
      n_models.times do |j|
        errors_i = model_predictions[i].zip(actuals).map { |p, a| p - a }
        errors_j = model_predictions[j].zip(actuals).map { |p, a| p - a }
        
        # Pearson correlation
        mean_i = errors_i.sum / errors_i.size.to_f
        mean_j = errors_j.sum / errors_j.size.to_f
        
        numerator = errors_i.zip(errors_j).map { |ei, ej| (ei - mean_i) * (ej - mean_j) }.sum
        denom_i = Math.sqrt(errors_i.map { |ei| (ei - mean_i) ** 2 }.sum)
        denom_j = Math.sqrt(errors_j.map { |ej| (ej - mean_j) ** 2 }.sum)
        
        correlations[i][j] = numerator / (denom_i * denom_j + 1e-6)
      end
    end
    
    # Average off-diagonal correlations (diversity measure)
    off_diagonal = []
    n_models.times do |i|
      n_models.times do |j|
        off_diagonal << correlations[i][j] if i != j
      end
    end
    
    avg_correlation = off_diagonal.sum / off_diagonal.size
    
    logger.info "Average error correlation: #{avg_correlation.round(4)} (lower = more diverse)"
    
    {
      correlations: correlations,
      avg_correlation: avg_correlation,
      diversity_score: 1 - avg_correlation.abs
    }
  end

  # Export ensemble configuration
  def export_ensemble_config(models, weights, output_file)
    logger.info "Exporting ensemble configuration to #{output_file}"
    
    CSV.open(output_file, 'w') do |csv|
      csv << ['model_name', 'model_type', 'weight', 'notes']
      
      models.each_with_index do |model, idx|
        csv << [
          model[:name],
          model[:type],
          weights[idx].round(4),
          model[:notes] || ''
        ]
      end
    end
    
    logger.info "Exported #{models.size} model configurations"
  end
end
