require 'csv'
require 'logger'

class AdvancedFeatures
  attr_reader :logger

  def initialize(logger = Logger.new(STDOUT))
    @logger = logger
  end

  # Team strength indicators
  def calculate_team_strength_index(data, team_col, wins_col, losses_col, diff_col)
    logger.info "Calculating team strength index"
    
    data.each do |row|
      wins = row[wins_col].to_f
      losses = row[losses_col].to_f
      diff = row[diff_col].to_f
      
      # Composite strength: win rate + normalized goal differential
      games = wins + losses
      win_rate = games > 0 ? wins / games : 0.5
      
      # Strength index (0-100 scale)
      strength = (win_rate * 50) + (diff * 0.5)
      row['team_strength_index'] = strength.round(2)
    end
    
    data
  end

  # Interaction features (multiplicative effects)
  def create_interaction_features(data, col1, col2, interaction_name = nil)
    logger.info "Creating interaction: #{col1} × #{col2}"
    
    interaction_name ||= "#{col1}_x_#{col2}"
    
    data.each do |row|
      val1 = row[col1].to_f
      val2 = row[col2].to_f
      row[interaction_name] = (val1 * val2).round(4)
    end
    
    data
  end

  # Polynomial features (non-linear relationships)
  def create_polynomial_features(data, col, degree: 2)
    logger.info "Creating polynomial features for #{col} (degree #{degree})"
    
    (2..degree).each do |d|
      new_col = "#{col}_pow#{d}"
      data.each do |row|
        val = row[col].to_f
        row[new_col] = (val ** d).round(4)
      end
    end
    
    data
  end

  # Momentum score (recent performance trend)
  def calculate_momentum(data, group_col, result_col, window: 10)
    logger.info "Calculating momentum score (last #{window} games)"
    
    grouped = data.group_by { |row| row[group_col] }
    
    grouped.each do |team, team_data|
      team_data.sort_by! { |r| r['date'] || r['game_number'] || 0 }
      
      team_data.each_with_index do |row, idx|
        recent = team_data[[0, idx - window + 1].max..idx]
        
        # Calculate win rate in window
        wins = recent.count { |r| r[result_col].to_s.upcase == 'W' }
        momentum = wins.to_f / recent.size
        
        row['momentum_score'] = momentum.round(3)
      end
    end
    
    data
  end

  # Rest advantage (days since last game)
  def calculate_rest_days(data, group_col, date_col)
    logger.info "Calculating rest days between games"
    
    grouped = data.group_by { |row| row[group_col] }
    
    grouped.each do |team, team_data|
      team_data.sort_by! { |r| Date.parse(r[date_col].to_s) }
      
      team_data.each_with_index do |row, idx|
        if idx == 0
          row['rest_days'] = 3 # Default for first game
        else
          prev_date = Date.parse(team_data[idx - 1][date_col].to_s)
          curr_date = Date.parse(row[date_col].to_s)
          row['rest_days'] = (curr_date - prev_date).to_i
        end
        
        # Flag back-to-back games
        row['is_back_to_back'] = row['rest_days'].to_i <= 1 ? 1 : 0
      end
    end
    
    data
  end

  # Head-to-head record
  def calculate_h2h_record(data, team1_col, team2_col, result_col)
    logger.info "Calculating head-to-head records"
    
    h2h_wins = Hash.new(0)
    h2h_games = Hash.new(0)
    
    data.each do |row|
      team1 = row[team1_col]
      team2 = row[team2_col]
      result = row[result_col]
      
      matchup = [team1, team2].sort.join('_vs_')
      h2h_games[matchup] += 1
      
      if result.to_s.upcase == 'W'
        h2h_wins["#{team1}_vs_#{team2}"] += 1
      end
    end
    
    # Add win rate against specific opponent
    data.each do |row|
      team1 = row[team1_col]
      team2 = row[team2_col]
      key = "#{team1}_vs_#{team2}"
      
      games = h2h_games[[team1, team2].sort.join('_vs_')]
      wins = h2h_wins[key]
      
      row['h2h_win_rate'] = games > 0 ? (wins.to_f / games).round(3) : 0.5
    end
    
    data
  end

  # Strength of schedule
  def calculate_strength_of_schedule(data, team_col, opponent_col, opponent_wins_col)
    logger.info "Calculating strength of schedule"
    
    # Calculate average opponent win rate
    team_schedules = Hash.new { |h, k| h[k] = [] }
    
    data.each do |row|
      team = row[team_col]
      opponent = row[opponent_col]
      opp_wins = row[opponent_wins_col].to_f
      
      team_schedules[team] << opp_wins
    end
    
    # Add SOS to each row
    data.each do |row|
      team = row[team_col]
      opponents = team_schedules[team]
      
      sos = opponents.any? ? opponents.sum / opponents.size : 0.5
      row['strength_of_schedule'] = sos.round(3)
    end
    
    data
  end

  # Clutch performance (close game win rate)
  def calculate_clutch_factor(data, group_col, goal_diff_col, result_col)
    logger.info "Calculating clutch performance in close games"
    
    grouped = data.group_by { |row| row[group_col] }
    
    grouped.each do |team, team_data|
      close_games = team_data.select { |r| r[goal_diff_col].to_i.abs <= 1 }
      close_wins = close_games.count { |r| r[result_col].to_s.upcase == 'W' }
      
      clutch_factor = close_games.any? ? close_wins.to_f / close_games.size : 0.5
      
      team_data.each do |row|
        row['clutch_factor'] = clutch_factor.round(3)
      end
    end
    
    data
  end

  # Home/away splits
  def calculate_home_away_splits(data, group_col, location_col, wins_col)
    logger.info "Calculating home/away performance splits"
    
    grouped = data.group_by { |row| row[group_col] }
    
    grouped.each do |team, team_data|
      home_games = team_data.select { |r| r[location_col].to_s.upcase == 'HOME' }
      away_games = team_data.select { |r| r[location_col].to_s.upcase == 'AWAY' }
      
      home_wins = home_games.count { |r| r[wins_col].to_i > 0 }
      away_wins = away_games.count { |r| r[wins_col].to_i > 0 }
      
      home_win_rate = home_games.any? ? home_wins.to_f / home_games.size : 0.5
      away_win_rate = away_games.any? ? away_wins.to_f / away_games.size : 0.5
      
      team_data.each do |row|
        row['home_win_rate'] = home_win_rate.round(3)
        row['away_win_rate'] = away_win_rate.round(3)
        row['home_away_diff'] = (home_win_rate - away_win_rate).round(3)
      end
    end
    
    data
  end

  # Pythagorean expectation (expected wins based on goals)
  def calculate_pythagorean_wins(data, gf_col, ga_col, games_col)
    logger.info "Calculating Pythagorean expected wins"
    
    data.each do |row|
      gf = row[gf_col].to_f
      ga = row[ga_col].to_f
      games = row[games_col].to_f
      
      # Pythagorean formula: GF^2 / (GF^2 + GA^2)
      if gf > 0 && ga > 0
        expected_win_pct = (gf ** 2) / ((gf ** 2) + (ga ** 2))
        expected_wins = expected_win_pct * games
        
        row['pythagorean_wins'] = expected_wins.round(2)
        row['pythagorean_win_pct'] = expected_win_pct.round(3)
        
        # Luck factor (actual wins - expected wins)
        actual_wins = row['W'].to_f
        row['luck_factor'] = (actual_wins - expected_wins).round(2)
      end
    end
    
    data
  end

  # Variance/consistency metrics
  def calculate_consistency_metrics(data, group_col, score_col)
    logger.info "Calculating team consistency metrics"
    
    grouped = data.group_by { |row| row[group_col] }
    
    grouped.each do |team, team_data|
      scores = team_data.map { |r| r[score_col].to_f }
      
      mean = scores.sum / scores.size.to_f
      variance = scores.map { |s| (s - mean) ** 2 }.sum / scores.size
      std_dev = Math.sqrt(variance)
      
      # Coefficient of variation (lower = more consistent)
      cv = mean != 0 ? std_dev / mean : 0
      
      team_data.each do |row|
        row['score_std_dev'] = std_dev.round(3)
        row['score_cv'] = cv.round(3)
        row['consistency_score'] = (1 - cv).round(3) # Higher = more consistent
      end
    end
    
    data
  end

  # Time decay weights (recent games matter more)
  def apply_time_decay_weights(data, date_col, decay_rate: 0.05)
    logger.info "Applying time decay weights (decay=#{decay_rate})"
    
    data.sort_by! { |r| Date.parse(r[date_col].to_s) }
    
    max_date = Date.parse(data.last[date_col].to_s)
    
    data.each do |row|
      curr_date = Date.parse(row[date_col].to_s)
      days_ago = (max_date - curr_date).to_i
      
      # Exponential decay: weight = exp(-decay_rate * days_ago)
      weight = Math.exp(-decay_rate * days_ago)
      row['time_weight'] = weight.round(4)
    end
    
    data
  end

  # Conference/division strength adjustments
  def calculate_conference_adjustments(data, conference_col, division_col, win_pct_col)
    logger.info "Calculating conference/division strength adjustments"
    
    # Average win % by conference
    conf_grouped = data.group_by { |r| r[conference_col] }
    conf_avg = {}
    
    conf_grouped.each do |conf, rows|
      avg = rows.map { |r| r[win_pct_col].to_f }.sum / rows.size
      conf_avg[conf] = avg
    end
    
    # Average win % by division
    div_grouped = data.group_by { |r| r[division_col] }
    div_avg = {}
    
    div_grouped.each do |div, rows|
      avg = rows.map { |r| r[win_pct_col].to_f }.sum / rows.size
      div_avg[div] = avg
    end
    
    # Apply adjustments
    data.each do |row|
      conf = row[conference_col]
      div = row[division_col]
      
      row['conference_strength'] = conf_avg[conf].round(3)
      row['division_strength'] = div_avg[div].round(3)
      
      # Adjusted win % (normalize by conference strength)
      win_pct = row[win_pct_col].to_f
      adjusted = win_pct / conf_avg[conf] * 0.5 # Normalize to league average
      row['adjusted_win_pct'] = adjusted.round(3)
    end
    
    data
  end
end
