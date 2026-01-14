require 'csv'
require 'logger'

class ModelValidator
  attr_reader :logger

  def initialize(logger = Logger.new(STDOUT))
    @logger = logger
  end

  # Time series cross-validation (expanding window)
  def time_series_cv_split(data, date_col, n_splits: 5, test_size: 0.2)
    logger.info "Generating time series CV splits (#{n_splits} folds)"
    
    # Sort by date
    sorted_data = data.sort_by { |r| Date.parse(r[date_col].to_s) }
    total_size = sorted_data.size
    test_samples = (total_size * test_size).to_i
    
    splits = []
    
    n_splits.times do |i|
      # Expanding window: train size grows, test size stays constant
      train_end = total_size - test_samples * (n_splits - i)
      test_end = train_end + test_samples
      
      train = sorted_data[0...train_end]
      test = sorted_data[train_end...test_end]
      
      splits << {
        fold: i + 1,
        train: train,
        test: test,
        train_size: train.size,
        test_size: test.size
      }
    end
    
    logger.info "Created #{splits.size} time series CV splits"
    splits
  end

  # Stratified split by outcome
  def stratified_split(data, target_col, test_size: 0.2, random_seed: 42)
    logger.info "Creating stratified train/test split"
    
    srand(random_seed)
    
    # Group by target classes
    grouped = data.group_by { |r| r[target_col] }
    
    train_data = []
    test_data = []
    
    grouped.each do |target_val, rows|
      shuffled = rows.shuffle
      split_idx = (rows.size * (1 - test_size)).to_i
      
      train_data.concat(shuffled[0...split_idx])
      test_data.concat(shuffled[split_idx..-1])
    end
    
    logger.info "Train: #{train_data.size}, Test: #{test_data.size}"
    
    { train: train_data, test: test_data }
  end

  # Calculate prediction confidence intervals
  def calculate_confidence_intervals(predictions, actuals, confidence: 0.95)
    logger.info "Calculating #{confidence * 100}% confidence intervals"
    
    errors = predictions.zip(actuals).map { |pred, actual| (pred - actual).abs }
    errors.sort!
    
    # Percentile for confidence interval
    percentile_idx = (errors.size * confidence).to_i
    ci_bound = errors[percentile_idx]
    
    {
      confidence_level: confidence,
      ci_bound: ci_bound.round(4),
      mean_error: (errors.sum / errors.size).round(4),
      median_error: errors[errors.size / 2].round(4)
    }
  end

  # Detect model overfitting
  def detect_overfitting(train_metrics, test_metrics, threshold: 0.1)
    logger.info "Checking for overfitting"
    
    overfit_signals = []
    
    train_metrics.each do |metric, train_val|
      test_val = test_metrics[metric]
      next unless test_val
      
      # Check if test performance is significantly worse
      diff = (train_val - test_val).abs
      pct_diff = diff / train_val
      
      if pct_diff > threshold
        overfit_signals << {
          metric: metric,
          train: train_val,
          test: test_val,
          diff: diff,
          pct_diff: pct_diff
        }
      end
    end
    
    if overfit_signals.any?
      logger.warn "Overfitting detected! #{overfit_signals.size} metrics show degradation"
      overfit_signals.each do |signal|
        logger.warn "  #{signal[:metric]}: train=#{signal[:train].round(4)}, test=#{signal[:test].round(4)} (#{(signal[:pct_diff] * 100).round(1)}% worse)"
      end
    else
      logger.info "No overfitting detected"
    end
    
    {
      is_overfit: overfit_signals.any?,
      signals: overfit_signals
    }
  end

  # Bootstrap confidence intervals for metrics
  def bootstrap_metric(predictions, actuals, metric: :rmse, n_iterations: 1000)
    logger.info "Bootstrapping #{metric} (#{n_iterations} iterations)"
    
    bootstrap_scores = []
    n = predictions.size
    
    n_iterations.times do
      # Resample with replacement
      indices = Array.new(n) { rand(n) }
      sample_preds = indices.map { |i| predictions[i] }
      sample_actuals = indices.map { |i| actuals[i] }
      
      # Calculate metric
      score = case metric
      when :rmse
        Math.sqrt(sample_preds.zip(sample_actuals).map { |p, a| (p - a) ** 2 }.sum / n)
      when :mae
        sample_preds.zip(sample_actuals).map { |p, a| (p - a).abs }.sum / n
      when :r2
        ss_res = sample_preds.zip(sample_actuals).map { |p, a| (a - p) ** 2 }.sum
        mean_actual = sample_actuals.sum / n.to_f
        ss_tot = sample_actuals.map { |a| (a - mean_actual) ** 2 }.sum
        1 - (ss_res / ss_tot)
      end
      
      bootstrap_scores << score
    end
    
    bootstrap_scores.sort!
    
    {
      mean: bootstrap_scores.sum / bootstrap_scores.size,
      median: bootstrap_scores[bootstrap_scores.size / 2],
      ci_95_lower: bootstrap_scores[(bootstrap_scores.size * 0.025).to_i],
      ci_95_upper: bootstrap_scores[(bootstrap_scores.size * 0.975).to_i],
      std_dev: Math.sqrt(bootstrap_scores.map { |s| (s - bootstrap_scores.sum / bootstrap_scores.size) ** 2 }.sum / bootstrap_scores.size)
    }
  end

  # Learning curve analysis
  def generate_learning_curve(data, target_col, train_sizes: [0.1, 0.25, 0.5, 0.75, 1.0])
    logger.info "Generating learning curve"
    
    learning_curve = []
    
    train_sizes.each do |size|
      sample_size = (data.size * size).to_i
      sample_data = data.sample(sample_size)
      
      learning_curve << {
        train_size: sample_size,
        train_fraction: size
        # User will add train_score and val_score after training
      }
    end
    
    logger.info "Generated #{learning_curve.size} learning curve points"
    learning_curve
  end

  # Feature importance validation
  def validate_feature_importance(importances, top_n: 10)
    logger.info "Validating top #{top_n} features"
    
    sorted = importances.sort_by { |k, v| -v }
    top_features = sorted.first(top_n)
    
    total_importance = importances.values.sum
    cumulative = 0
    
    top_features.each do |feature, importance|
      cumulative += importance
      pct = (importance / total_importance * 100).round(2)
      cum_pct = (cumulative / total_importance * 100).round(2)
      
      logger.info "  #{feature}: #{importance.round(4)} (#{pct}%, cumulative: #{cum_pct}%)"
    end
    
    {
      top_features: top_features.to_h,
      cumulative_importance: cumulative / total_importance
    }
  end

  # Prediction calibration check
  def check_calibration(predictions, actuals, n_bins: 10)
    logger.info "Checking prediction calibration (#{n_bins} bins)"
    
    # Sort by predicted value
    sorted = predictions.zip(actuals).sort_by { |pred, _| pred }
    bin_size = sorted.size / n_bins
    
    calibration = []
    
    n_bins.times do |i|
      bin_start = i * bin_size
      bin_end = i == n_bins - 1 ? sorted.size : (i + 1) * bin_size
      bin_data = sorted[bin_start...bin_end]
      
      bin_preds = bin_data.map { |p, _| p }
      bin_actuals = bin_data.map { |_, a| a }
      
      avg_pred = bin_preds.sum / bin_preds.size
      avg_actual = bin_actuals.sum / bin_actuals.size
      
      calibration << {
        bin: i + 1,
        avg_predicted: avg_pred.round(3),
        avg_actual: avg_actual.round(3),
        calibration_error: (avg_pred - avg_actual).abs.round(3)
      }
    end
    
    mean_calibration_error = calibration.map { |b| b[:calibration_error] }.sum / calibration.size
    logger.info "Mean calibration error: #{mean_calibration_error.round(4)}"
    
    {
      bins: calibration,
      mean_calibration_error: mean_calibration_error
    }
  end
end
