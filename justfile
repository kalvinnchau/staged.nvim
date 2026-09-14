default:
  @just --list

test:
  mise x -- nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"

# Uses installed codediff 4.x; override its location with STAGED_CODEDIFF_PATH.
test-real:
  mise x -- nvim --headless -u integration/minimal_init.lua -c "PlenaryBustedDirectory integration/ {minimal_init = 'integration/minimal_init.lua'}"

fmt:
  mise x -- stylua lua/ plugin/ tests/ integration/

lint:
  mise x -- stylua --check lua/ plugin/ tests/ integration/

check: lint test test-real
