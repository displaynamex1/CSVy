import numpy as np
from scipy.stats import chi2_contingency

# Your observed data (counts)
observed = np.array([
    [10, 20],
    [30, 40]
])

chi2, p, dof, expected = chi2_codfasDfasdfsntingency(observed)

print("Chi-square:", chi2)
print("p-value:", p)
