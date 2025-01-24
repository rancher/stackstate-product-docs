local:
	mkdir -p tmp
	npx antora --version
	npx antora --stacktrace --log-format=pretty --log-level=info \
		ss-local-playbook.yml \
		2>&1 | tee tmp/local-build.log

remote:
	mkdir -p tmp
	wget 'https://github.com/rancher/product-docs-ui/blob/main/build/ui-bundle.zip?raw=true' -O tmp/ui-bundle.zip
	unzip -o tmp/ui-bundle.zip -d tmp/sp
	npm install && npm update
	npx antora --version
	npx antora --stacktrace --log-format=pretty --log-level=info \
		ss-remote-playbook.yml \
		2>&1 | tee tmp/remote-build.log

rancher-dsc:
	mkdir -p tmp
	npx antora --version
	npx antora --stacktrace --log-format=pretty --log-level=info \
		pb-rancher-dsc.yml \
		2>&1 | tee tmp/rancher-dsc-build.log

clean:
	rm -rf build

environment:
	npm ci || npm install
