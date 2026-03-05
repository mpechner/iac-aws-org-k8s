# Penetration Test Run Results

This directory contains actual penetration test execution results, organized by date/time of the test run.

## Directory Structure

```
penetration-run/
├── README.md                          # This file
└── YYYYMMDD-HHMMSS/                   # Timestamped test run
    ├── security-assessment-*.txt      # Test output/results
    └── ADDENDUM-Security-Fixes-*.md   # Remediation report (if applicable)
```

## Contents

Each timestamped directory contains:

- **security-assessment-YYYYMMDDHHMMSS.txt** - Raw test output from `./run-all-tests.sh`
  - Security headers assessment
  - TLS/SSL configuration results
  - Information disclosure findings
  - Attack vector validation results
  - Rate limiting assessment

- **ADDENDUM-Security-Fixes-YYYYMMDD.md** (if created) - Remediation documentation
  - Findings from the test run
  - Fixes applied
  - Deployment instructions
  - Verification steps

## Templates vs Results

- **Templates** (`../reports/` directory) - Reusable report templates
- **Results** (this directory) - Actual test execution output specific to each run

## Running New Tests

```bash
cd penetration-test
export TARGET_URL=https://nginx.dev.foobar.support
./run-all-tests.sh
```

Results will be saved to `reports/security-assessment-*.txt` and should be moved to this directory with a timestamped subdirectory.

---

**Note:** Report templates are in `../reports/` directory. This directory is for actual test run artifacts only.
