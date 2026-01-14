# CSVy - Directory Structure

```
CSVy/
├── cli.rb                    # Main CLI entry point
├── README.md                 # Project overview
├── TODO.md                   # Competition tasks
├── Gemfile                   # Ruby dependencies
├── Rakefile                  # Build tasks
│
├── lib/                      # Ruby modules
│   ├── advanced_features.rb
│   ├── csv_cleaner.rb
│   ├── csv_diagnostics.rb
│   ├── csv_io_handler.rb
│   ├── csv_merger.rb
│   ├── csv_processor.rb
│   ├── data_preprocessor.rb
│   ├── data_validator.rb
│   ├── database_manager.rb
│   ├── dataframe_handler.rb
│   ├── ensemble_builder.rb
│   ├── html_reporter.rb
│   ├── hyperparameter_manager.rb
│   ├── model_tracker.rb
│   ├── model_validator.rb
│   └── time_series_features.rb
│
├── config/                   # Configuration files
│   └── hyperparams/          # Model hyperparameter configs
│       ├── model1_baseline.yaml
│       ├── model2_linear_regression.yaml
│       ├── model3_elo.yaml
│       ├── model4_xgboost.yaml
│       ├── model4_random_forest.yaml
│       └── model5_ensemble.yaml
│
├── data/                     # Sample datasets
│   ├── sample_advanced.csv
│   ├── sample_employees.csv
│   ├── sample_nhl_standings.csv
│   ├── sample_nhl_standings_report.html
│   ├── sample_products.csv
│   ├── sample_students_dirty.csv
│   ├── sample_weather.csv
│   └── test_fix.csv
│
├── docs/                     # Documentation
│   ├── guides/               # User guides (moved from root)
│   │   ├── QUICK_START.md
│   │   ├── QUICK_REFERENCE.md
│   │   ├── USAGE_GUIDE.md
│   │   ├── WINNING_STRATEGY.md
│   │   ├── CALCULATIONS.md
│   │   └── FEATURES.md
│   └── HOCKEY_FEATURES.md    # Hockey-specific features
│
├── output/                   # Generated files (gitignored)
│   ├── hyperparams/          # Generated hyperparameter CSVs
│   ├── reports/              # HTML tracking reports
│   └── predictions/          # Model predictions
│
├── experiments/              # Experiment tracking
│   └── elo_random.csv
│
├── scripts/                  # Utility scripts
│   ├── competitive_pipeline.rb
│   └── preprocess_hockey.sh
│
└── spec/                     # RSpec tests
    ├── spec_helper.rb
    ├── csv_cleaner_spec.rb
    ├── csv_merger_spec.rb
    ├── csv_processor_spec.rb
    ├── data_preprocessor_spec.rb
    └── data_validator_spec.rb
```

## File Organization

### Root Level
- **cli.rb**: Main command-line interface
- **README.md**: Project documentation
- **TODO.md**: Competition task list

### lib/
Core Ruby modules for data processing, feature engineering, and model management.

### config/hyperparams/
YAML files defining hyperparameter search spaces for all 5 models.

### data/
Sample datasets for testing and development.

### docs/
All documentation consolidated here:
- **guides/**: User guides and strategies
- **HOCKEY_FEATURES.md**: Feature engineering documentation

### output/
Generated files organized by type:
- **hyperparams/**: CSV files with hyperparameter configurations
- **reports/**: HTML tracking dashboards
- **predictions/**: Model prediction outputs

### experiments/
Experiment tracking and results.

### scripts/
Automation scripts for data pipelines.

### spec/
RSpec test files.
