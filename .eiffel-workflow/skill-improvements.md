# Skill improvements queued (not applied mid-workflow)

Found while running /eiffel.contracts on simple_taskman, 2026-10-05.

## eiffel-contracts

1. **Compile commands are rejected by ec.sh.** Steps 6 and 6b say
   `ec.sh -batch -config X.ecf -target X_tests -c_compile`. The wrapper rejects
   raw flags. Use `ec.sh check -config X.ecf -target X_tests`, then
   `ec.sh test -config X.ecf -target X_tests`.
2. **Folder and base class.** The skill writes tests to `test/` inheriting
   `EQA_TEST_SET`. The ecosystem standard (oracle rule "Testing Standard") is
   `testing/` with `TEST_APP`, `LIB_TESTS`, and `TEST_SET_BASE`.
3. **Cluster name clash.** A test cluster named `testing` collides with the
   ISE `testing` library (VD00). Name the cluster `tests`.
4. **Extending targets drop assertions.** A test target that `extends` the
   library target must repeat `<option><assertions .../></option>`, or every
   cluster it declares runs with contracts off. Add to the ECF template.
5. **Do not trust the green line.** `ec.sh check` prints "Syntax and type check
   passed" even after `Error code:`. The gate is "System Recompiled." with no
   "Error code:" in the output, from clean EIFGENs when files were added.
6. **Empty-body stubs.** "`do end` stubs" do not compile for functions with an
   attached reference result (void safety). Say: create a minimal attached
   Result and mark the body `-- Phase 4:`.
7. **Skeletal tests.** Empty `-- TODO: Phase 5` tests pass vacuously. Prefer
   tests written from the contracts now, expected to fail until Phase 4, with
   the runner reporting them.
8. **Completion message.** Step "Next: /eiffel.mml" is redundant when Phase 0
   decided MML is required and Phase 1 already wrote the model queries.
