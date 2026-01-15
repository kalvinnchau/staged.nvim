default:
  @just --list

test:
  nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"

fmt:
  mise x -- stylua lua/ plugin/ tests/

lint:
  mise x -- stylua --check lua/ plugin/ tests/
