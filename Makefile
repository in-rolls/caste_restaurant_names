.PHONY: sync analysis figures report lint format test check ci-docker

sync:
	uv sync --locked
	Rscript -e 'renv::restore(prompt = FALSE)'

analysis:
	Rscript scripts/01_analyze.R

figures:
	Rscript scripts/02_figures.R

report:
	Rscript scripts/03_report.R

lint:
	uv run --locked black --check scripts tests/python
	uv run --locked isort --check-only scripts tests/python
	uv run --locked flake8 scripts tests/python
	Rscript -e 'l <- unlist(lapply(c("R", "scripts", "tests/testthat"), lintr::lint_dir), recursive = FALSE); print(l); quit(status = as.integer(length(l) > 0L))'

format:
	uv run --locked black scripts tests/python
	uv run --locked isort scripts tests/python
	Rscript -e 'styler::cache_deactivate(); invisible(lapply(c("R", "scripts", "tests/testthat"), styler::style_dir))'

test:
	uv run --locked pytest
	Rscript tests/testthat.R

check: lint test
	Rscript scripts/99_run_all.R

ci-docker:
	uv export --locked --all-groups --no-emit-project --format requirements.txt | \
	  docker run --rm -i -v "$(CURDIR):/work" -w /work python:3.14-slim sh -c \
	  'cat > /tmp/requirements.txt && pip install --disable-pip-version-check -r /tmp/requirements.txt && black --check scripts tests/python && isort --check-only scripts tests/python && flake8 scripts tests/python && pytest'
