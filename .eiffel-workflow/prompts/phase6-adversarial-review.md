# Adversarial Test Suggestions: simple_taskman

Contracts: ../../src/  Current tests: ../../testing/ (182 tests; contracts kept in the test binary)

## Suggest Tests For
1. Boundary values: 0, 1, INTEGER_64 max, empty and very long names, -0.0, NaN/infinity bit patterns
2. Capacity limits: series capacity 1 and full rings; 5,000 processes; 1,024 logical processors; hour-long windows
3. SCOOP concurrent access: several readers on one slot; stop before start; rapid start/stop; a reader that never reads
4. State transitions in unexpected order: close twice, sample after close, slot operations in any order, wall-clock changes mid-run
5. Resource exhaustion: long sampler runs with process churn; repeated native/PDH reads; damaged recordings at every byte

Already covered: see evidence/phase6-tests.txt. Report only what is not.
