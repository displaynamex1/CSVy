"""
ELO Model - Reusable Python Module

This is the same EloModel class from the notebook, 
extracted as a .py file for easy importing.

Usage:
    from utils.elo_model import EloModel
    
    model = EloModel(params)
    model.fit(games_df)
    metrics = model.evaluate(test_df)
"""

import pandas as pd
import numpy as np
from sklearn.metrics import mean_squared_error, mean_absolute_error, r2_score


class EloModel:
    def __init__(self, params):
        """
        Initialize ELO model with hyperparameters.
        
        params: dict with keys:
            - k_factor: rating change rate (20-40)
            - home_advantage: home ice boost (50-150)
            - initial_rating: starting rating (1500)
            - mov_multiplier: margin of victory weight (0-1.5)
            - mov_method: 'linear' or 'logarithmic'
            - season_carryover: year-to-year retention (0.67-0.85)
            - ot_win_multiplier: OT win value (0.75-1.0)
            - rest_advantage_per_day: rating boost per rest day (0-10)
            - b2b_penalty: back-to-back penalty (0-50)
        """
        self.params = params
        self.ratings = {}
        self.rating_history = []
    
    def initialize_ratings(self, teams, divisions=None):
        """Initialize team ratings based on division tier."""
        initial = self.params.get('initial_rating', 1500)
        division_ratings = {
            'D1': initial + 100,
            'D2': initial,
            'D3': initial - 100
        }
        
        for i, team in enumerate(teams):
            if divisions is not None and i < len(divisions):
                div = divisions.iloc[i] if hasattr(divisions, 'iloc') else divisions[i]
                self.ratings[team] = division_ratings.get(div, initial)
            else:
                self.ratings[team] = initial
    
    def calculate_expected_score(self, team_elo, opponent_elo):
        """Calculate expected win probability."""
        return 1 / (1 + 10 ** ((opponent_elo - team_elo) / 400))
    
    def calculate_mov_multiplier(self, goal_diff):
        """Calculate margin of victory multiplier."""
        mov = self.params.get('mov_multiplier', 0)
        if mov == 0:
            return 1.0
        
        if self.params.get('mov_method', 'logarithmic') == 'linear':
            return 1 + (abs(goal_diff) * mov)
        return 1 + (np.log(abs(goal_diff) + 1) * mov)
    
    def get_actual_score(self, outcome):
        """Convert game outcome to actual score (0-1)."""
        if outcome in ['RW', 'W', 1]:  # Regulation win
            return 1.0
        elif outcome == 'OTW':  # Overtime win
            return self.params.get('ot_win_multiplier', 0.75)
        elif outcome == 'OTL':  # Overtime loss
            return 1 - self.params.get('ot_win_multiplier', 0.75)
        return 0.0  # Regulation loss
    
    def adjust_for_context(self, team_elo, is_home, rest_time, travel_dist, injuries):
        """Apply contextual adjustments to ELO rating."""
        adjusted = team_elo
        
        # Home advantage
        if is_home:
            adjusted += self.params.get('home_advantage', 0)
        
        # Back-to-back penalty
        if rest_time <= 1:
            adjusted -= self.params.get('b2b_penalty', 0)
        
        # Travel fatigue (15 points per 1000 miles)
        if not is_home and travel_dist > 0:
            adjusted -= (travel_dist / 1000) * 15
        
        # Injury penalty (25 points per key injury)
        adjusted -= injuries * 25
        
        return adjusted
    
    def update_ratings(self, game):
        """Update team ratings after a game."""
        home_team = game['home_team']
        away_team = game['away_team']
        
        # Get base ratings (default to 1500 for new teams)
        home_elo = self.ratings.get(home_team, 1500)
        away_elo = self.ratings.get(away_team, 1500)
        
        # Get context values with defaults for missing columns
        home_rest = game.get('home_rest', 2)
        away_rest = game.get('away_rest', 2)
        away_travel = game.get('away_travel_dist', game.get('travel_distance', 0))
        home_injuries = game.get('home_injuries', game.get('injuries', 0))
        away_injuries = game.get('away_injuries', game.get('injuries', 0))
        
        # Apply contextual adjustments
        home_adj = self.adjust_for_context(home_elo, True, home_rest, 0, home_injuries)
        away_adj = self.adjust_for_context(away_elo, False, away_rest, away_travel, away_injuries)
        
        # Rest differential advantage
        rest_diff = home_rest - away_rest
        home_adj += rest_diff * self.params.get('rest_advantage_per_day', 0)
        
        # Calculate expected scores
        home_expected = self.calculate_expected_score(home_adj, away_adj)
        
        # Handle different outcome column names
        if 'home_outcome' in game:
            home_actual = self.get_actual_score(game['home_outcome'])
        elif 'home_win' in game:
            home_actual = 1.0 if game['home_win'] else 0.0
        else:
            home_actual = 1.0 if game['home_goals'] > game['away_goals'] else 0.0
        
        # Calculate margin of victory multiplier
        goal_diff = game['home_goals'] - game['away_goals']
        mov_mult = self.calculate_mov_multiplier(goal_diff)
        
        # Update ratings
        k = self.params.get('k_factor', 32) * mov_mult
        self.ratings[home_team] = home_elo + k * (home_actual - home_expected)
        self.ratings[away_team] = away_elo + k * ((1 - home_actual) - (1 - home_expected))
        
        # Store history
        self.rating_history.append({
            'home_team': home_team,
            'away_team': away_team,
            'home_rating': self.ratings[home_team],
            'away_rating': self.ratings[away_team]
        })
    
    def predict_goals(self, game):
        """Predict goals for both teams."""
        home_team = game['home_team']
        away_team = game['away_team']
        
        # Get adjusted ratings
        home_elo = self.ratings.get(home_team, 1500)
        away_elo = self.ratings.get(away_team, 1500)
        
        # Get context values with defaults
        home_rest = game.get('home_rest', 2)
        away_rest = game.get('away_rest', 2)
        away_travel = game.get('away_travel_dist', game.get('travel_distance', 0))
        home_injuries = game.get('home_injuries', game.get('injuries', 0))
        away_injuries = game.get('away_injuries', game.get('injuries', 0))
        
        home_adj = self.adjust_for_context(home_elo, True, home_rest, 0, home_injuries)
        away_adj = self.adjust_for_context(away_elo, False, away_rest, away_travel, away_injuries)
        
        # Rest differential
        rest_diff = home_rest - away_rest
        home_adj += rest_diff * self.params.get('rest_advantage_per_day', 0)
        
        # Calculate win probability
        home_win_prob = self.calculate_expected_score(home_adj, away_adj)
        
        # Convert to expected goal differential
        # Scale: 50% win prob = 0 goal diff, 100% = +6 goals, 0% = -6 goals
        expected_diff = (home_win_prob - 0.5) * 12
        
        # League average is ~3 goals per team
        home_goals = 3.0 + (expected_diff / 2)
        away_goals = 3.0 - (expected_diff / 2)
        
        return home_goals, away_goals
    
    def predict_winner(self, game):
        """Predict winner and win probability."""
        home_team = game['home_team']
        away_team = game['away_team']
        
        home_elo = self.ratings.get(home_team, 1500)
        away_elo = self.ratings.get(away_team, 1500)
        
        home_adj = self.adjust_for_context(
            home_elo, True, 
            game.get('home_rest', 2), 0, game.get('home_injuries', 0)
        )
        away_adj = self.adjust_for_context(
            away_elo, False,
            game.get('away_rest', 2), 
            game.get('away_travel_dist', game.get('travel_distance', 0)), 
            game.get('away_injuries', 0)
        )
        
        rest_diff = game.get('home_rest', 2) - game.get('away_rest', 2)
        home_adj += rest_diff * self.params.get('rest_advantage_per_day', 0)
        
        home_win_prob = self.calculate_expected_score(home_adj, away_adj)
        
        if home_win_prob > 0.5:
            return home_team, home_win_prob
        else:
            return away_team, 1 - home_win_prob
    
    def fit(self, games_df):
        """Train the model on historical games."""
        # Initialize ratings
        teams = pd.concat([games_df['home_team'], games_df['away_team']]).unique()
        if 'division' in games_df.columns:
            divisions = games_df.groupby('home_team')['division'].first()
            self.initialize_ratings(teams, divisions)
        else:
            self.initialize_ratings(teams)
        
        # Update ratings game-by-game
        for _, game in games_df.iterrows():
            self.update_ratings(game)
    
    def evaluate(self, games_df):
        """Evaluate model on test set."""
        predictions = []
        actuals = []
        
        for _, game in games_df.iterrows():
            home_pred, _ = self.predict_goals(game)
            predictions.append(home_pred)
            actuals.append(game['home_goals'])
        
        rmse = mean_squared_error(actuals, predictions, squared=False)
        mae = mean_absolute_error(actuals, predictions)
        r2 = r2_score(actuals, predictions) if len(set(actuals)) > 1 else 0.0
        
        return {'rmse': rmse, 'mae': mae, 'r2': r2}
    
    def get_rankings(self, top_n=None):
        """Get team rankings sorted by ELO rating."""
        sorted_ratings = sorted(self.ratings.items(), key=lambda x: x[1], reverse=True)
        if top_n:
            return sorted_ratings[:top_n]
        return sorted_ratings
    
    def get_rating_history_df(self):
        """Get rating history as a DataFrame."""
        return pd.DataFrame(self.rating_history)
    
    def predict_goals(self, game):
        """Predict goals for both teams."""
        # Get adjusted ratings
        home_elo = self.ratings.get(game['home_team'], 1500)
        away_elo = self.ratings.get(game['away_team'], 1500)
        
        home_elo_adj = self.adjust_for_context(
            home_elo, True, 
            game.get('home_rest', 2), 0, game.get('home_injuries', 0)
        )
        away_elo_adj = self.adjust_for_context(
            away_elo, False,
            game.get('away_rest', 2), game.get('away_travel_dist', 0), game.get('away_injuries', 0)
        )
        
        # Rest differential
        rest_diff = game.get('home_rest', 2) - game.get('away_rest', 2)
        home_elo_adj += rest_diff * self.params.get('rest_advantage_per_day', 0)
        
        # Calculate win probability
        home_win_prob = self.calculate_expected_score(home_elo_adj, away_elo_adj)
        
        # Convert to expected goal differential
        expected_diff = (home_win_prob - 0.5) * 12
        
        # League average is ~3 goals per team
        home_goals = 3.0 + (expected_diff / 2)
        away_goals = 3.0 - (expected_diff / 2)
        
        return home_goals, away_goals
    
    def predict_winner(self, game):
        """Predict winner and win probability."""
        home_elo = self.ratings.get(game['home_team'], 1500)
        away_elo = self.ratings.get(game['away_team'], 1500)
        
        home_elo_adj = self.adjust_for_context(
            home_elo, True, 
            game.get('home_rest', 2), 0, game.get('home_injuries', 0)
        )
        away_elo_adj = self.adjust_for_context(
            away_elo, False,
            game.get('away_rest', 2), game.get('away_travel_dist', 0), game.get('away_injuries', 0)
        )
        
        rest_diff = game.get('home_rest', 2) - game.get('away_rest', 2)
        home_elo_adj += rest_diff * self.params.get('rest_advantage_per_day', 0)
        
        home_win_prob = self.calculate_expected_score(home_elo_adj, away_elo_adj)
        
        if home_win_prob > 0.5:
            return game['home_team'], home_win_prob
        else:
            return game['away_team'], 1 - home_win_prob
    
    def fit(self, games_df):
        """Train the model on historical games."""
        # Initialize ratings
        teams = pd.concat([games_df['home_team'], games_df['away_team']]).unique()
        if 'division' in games_df.columns:
            divisions = games_df.groupby('home_team')['division'].first()
            self.initialize_ratings(teams, divisions)
        else:
            self.initialize_ratings(teams)
        
        # Update ratings game-by-game
        for _, game in games_df.iterrows():
            self.update_ratings(game)
    
    def evaluate(self, games_df):
        """Evaluate model on test set."""
        predictions = []
        actuals = []
        
        for _, game in games_df.iterrows():
            home_pred, away_pred = self.predict_goals(game)
            predictions.append(home_pred)
            actuals.append(game['home_goals'])
        
        rmse = mean_squared_error(actuals, predictions, squared=False)
        mae = mean_absolute_error(actuals, predictions)
        r2 = r2_score(actuals, predictions) if len(set(actuals)) > 1 else 0.0
        
        return {'rmse': rmse, 'mae': mae, 'r2': r2}
    
    def get_rankings(self, top_n=None):
        """Get team rankings sorted by ELO rating."""
        sorted_ratings = sorted(self.ratings.items(), key=lambda x: x[1], reverse=True)
        if top_n:
            return sorted_ratings[:top_n]
        return sorted_ratings
    
    def get_rating_history_df(self):
        """Get rating history as a DataFrame."""
        return pd.DataFrame(self.rating_history)
