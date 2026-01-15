.PHONY: all test

.PHONY: local
local:
	mkdir -p tmp
	npx antora --version
	npx antora --stacktrace --log-format=pretty --log-level=info \
		ss-local-playbook.yml \
		2>&1 | tee tmp/local-build.log

.PHONY: remote
remote:
	mkdir -p tmp
	npx antora --version
	npx antora --stacktrace --log-format=pretty --log-level=info \
		ss-remote-playbook.yml \
		2>&1 | tee tmp/remote-build.log

.PHONY: clean
clean:
	rm -rf build

.PHONY: environment
environment:
	npm ci || npm install

.PHONY: checkmake
checkmake:
	@if [ $$(which checkmake 2>/dev/null) ]; then \
		checkmake Makefile; \
	else \
		echo "checkmake not available"; \
	fi

.PHONY: preview
preview:
	npx http-server build/site -c-1
