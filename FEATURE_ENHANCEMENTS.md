# 🚀 Feature Enhancements - Complete List

## New Features Added

### 1. **Playoff Pressure Indicators** ✅
- `pts_from_playoff_line` - Distance from 8th place cutoff
- `playoff_probability` - Probability of making playoffs (0-1)
- `is_clinched` - Whether team has clinched playoff spot
- `is_eliminated` - Whether team is eliminated

**Why it matters**: Teams fighting for playoffs play differently than teams that have clinched or are eliminated.

### 2. **Streak Parsing** ✅
- `streak_type` - 1 for winning streak, -1 for losing streak
- `streak_length` - Number of games in current streak
- `is_winning_streak` - Binary indicator
- `is_losing_streak` - Binary indicator

**Why it matters**: Momentum is real - teams on winning streaks perform better.

### 3. **L10 (Last 10 Games) Parsing** ✅
- `l10_wins`, `l10_losses`, `l10_ot` - Record breakdown
- `l10_win_rate` - Win percentage in last 10
- `l10_points` - Points earned in last 10
- `l10_points_pct` - Points percentage

**Why it matters**: Recent form is more predictive than season-long averages.

### 4. **Shootout Performance** ✅
- `so_wins`, `so_losses` - Shootout record
- `so_win_rate` - Shootout win percentage
- `so_total` - Total shootout games

**Why it matters**: Indicates clutch performance and ability to win close games.

### 5. **Enhanced Team Strength Index** ✅
- `enhanced_strength_index` - More sophisticated calculation (0-100 scale)
- `offense_rating` - Offensive strength rating
- `defense_rating` - Defensive strength rating

**Components**:
- Win rate (30%)
- Goal differential per game (20%)
- Pythagorean expectation (30%)
- Goals for per game (10%)
- Goals against per game (10%)

**Why it matters**: Better captures team quality than simple win rate.

### 6. **Opponent Strength at Time of Game** ✅
- `opponent_strength` - Opponent's strength BEFORE this game
- `opponent_pts_per_game` - Opponent's points per game up to this game
- `opponent_gf_per_game` - Opponent's goals for per game
- `opponent_ga_per_game` - Opponent's goals against per game

**Why it matters**: Teams improve/decline over season - opponent strength at time of game is more accurate than season average.

### 7. **Conference/Division Adjustments** ✅
- `conference_strength` - Average win % in conference
- `division_strength` - Average win % in division
- `adjusted_win_pct` - Win % normalized by conference strength

**Why it matters**: Some conferences/divisions are stronger - normalize for fair comparison.

### 8. **Head-to-Head Records** ✅
- `h2h_win_rate` - Win rate against specific opponent

**Why it matters**: Some teams match up better against certain opponents.

### 9. **Feature Correlation Analysis** ✅
- New CLI command: `feature-correlation`
- Automatically generates correlation report in pipeline
- Identifies most predictive features

**Usage**:
```bash
ruby cli.rb feature-correlation data/processed/competitive_features.csv PTS -o correlations.csv
```

**Why it matters**: Helps identify which features actually matter for predictions.

## Updated Features

### Competitive Pipeline Now Generates 30+ Features

The `competitive-pipeline` command now automatically creates:

**Core Features** (14):
1. Team strength index
2. Enhanced strength index
3. Pythagorean wins
4. Pythagorean win percentage
5. Luck factor
6. Momentum score
7. Rest days
8. Back-to-back flag
9. Clutch factor
10. Home/away splits
11. Strength of schedule
12. Consistency metrics
13. Time decay weights
14. Interaction features (offense_power, defense_weakness)

**New Features** (16+):
15. Playoff pressure indicators (4 features)
16. Streak parsing (4 features)
17. L10 record parsing (5 features)
18. Shootout performance (4 features)
19. Enhanced strength components (2 features)
20. Opponent strength at game (4 features)
21. Conference/division adjustments (3 features)
22. Head-to-head records (1 feature)
23. Rolling averages (multiple windows)
24. Lag features (multiple periods)
25. EWMA features
26. Polynomial features

**Total: 30+ engineered features**

## Usage Examples

### Full Pipeline with All Features
```bash
ruby cli.rb competitive-pipeline data/nhl_data.csv -o data/processed
```

**Outputs**:
- `competitive_features.csv` - Full dataset with all features
- `train.csv` - Training set (time series split)
- `test.csv` - Test set
- `feature_correlations.csv` - Top 20 feature correlations

### Feature Correlation Analysis
```bash
# Analyze which features correlate most with points
ruby cli.rb feature-correlation data/processed/competitive_features.csv PTS -o correlations.csv

# Analyze which features correlate with wins
ruby cli.rb feature-correlation data/processed/competitive_features.csv W -o win_correlations.csv
```

### Standalone Feature Creation
```bash
# Just create advanced features (if you already have cleaned data)
ruby cli.rb advanced-features data/cleaned.csv -o data/advanced.csv
```

## Feature Categories

### Time-Based Features
- Rolling averages (5, 10 game windows)
- Lag features (1, 3, 5 games ago)
- EWMA (exponentially weighted)
- Time decay weights
- L10 record
- Streak indicators

### Strength Metrics
- Team strength index (basic)
- Enhanced strength index (sophisticated)
- Pythagorean expectation
- Offense/defense ratings
- Consistency scores

### Context Features
- Home/away splits
- Rest days & back-to-back
- Opponent strength at game time
- Strength of schedule
- Conference/division strength

### Performance Indicators
- Momentum score
- Clutch factor
- Shootout performance
- Head-to-head records
- Playoff pressure

### Mathematical Features
- Interaction features (multiplicative)
- Polynomial features (non-linear)
- Luck factor (actual vs expected)

## Expected Impact

These enhancements should improve model performance by:

1. **Better feature quality**: Enhanced strength index is more accurate
2. **Temporal accuracy**: Opponent strength at game time vs season average
3. **Context awareness**: Playoff pressure, streaks, recent form
4. **Feature selection**: Correlation analysis identifies important features

**Expected improvement**: 5-10% reduction in RMSE from better feature engineering.

## Next Steps

1. Run pipeline on your data
2. Check feature correlations to identify most important features
3. Use correlation insights to select features for models
4. Compare model performance with vs without new features

## Technical Notes

- All features handle missing data gracefully
- Features are calculated in correct order (no data leakage)
- Time series features respect temporal ordering
- Opponent strength uses only past data (no future leakage)
