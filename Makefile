SHELL := /bin/bash
SAFE_CLI_VERSION := $(shell grep "^version" < Cargo.toml | head -n 1 | awk '{ print $$3 }' | sed 's/\"//g')
USER_ID := $(shell id -u)
GROUP_ID := $(shell id -g)
UNAME_S := $(shell uname -s)
PWD := $(shell echo $$PWD)
UUID := $(shell uuidgen | sed 's/-//g')
S3_BUCKET := safe-jenkins-build-artifacts
SAFE_AUTH_DEFAULT_PORT := 41805
GITHUB_REPO_OWNER := maidsafe
GITHUB_REPO_NAME := safe-cli

build-clean:
	rm -rf artifacts
	mkdir artifacts
ifeq ($(UNAME_S),Linux)
	docker run --name "safe-cli-build-${UUID}" -v "${PWD}":/usr/src/safe-cli:Z \
		-u ${USER_ID}:${GROUP_ID} \
		maidsafe/safe-cli-build:build \
		bash -c "rm -rf /target/release && cargo build --release"
	docker cp "safe-cli-build-${UUID}":/target .
	docker rm "safe-cli-build-${UUID}"
else
	rm -rf target
	cargo build --release
endif
	find target/release -maxdepth 1 -type f -exec cp '{}' artifacts \;

build:
	rm -rf artifacts
	mkdir artifacts
ifeq ($(UNAME_S),Linux)
	docker run --name "safe-cli-build-${UUID}" -v "${PWD}":/usr/src/safe-cli:Z \
		-u ${USER_ID}:${GROUP_ID} \
		maidsafe/safe-cli-build:build \
		cargo build --release
	docker cp "safe-cli-build-${UUID}":/target .
	docker rm "safe-cli-build-${UUID}"
else
	cargo build --release
endif
	find target/release -maxdepth 1 -type f -exec cp '{}' artifacts \;

build-dev:
	rm -rf artifacts
	mkdir artifacts
ifeq ($(UNAME_S),Linux)
	docker run --name "safe-cli-build-${UUID}" -v "${PWD}":/usr/src/safe-cli:Z \
		-u ${USER_ID}:${GROUP_ID} \
		maidsafe/safe-cli-build:build-dev \
		cargo build --release --features=mock-network
	docker cp "safe-cli-build-${UUID}":/target .
	docker rm "safe-cli-build-${UUID}"
else
	cargo build --release --features=mock-network
endif
	find target/release -maxdepth 1 -type f -exec cp '{}' artifacts \;

strip-artifacts:
ifeq ($(OS),Windows_NT)
	find artifacts -name "safe.exe" -exec strip -x '{}' \;
else ifeq ($(UNAME_S),Darwin)
	find artifacts -name "safe" -exec strip -x '{}' \;
else
	find artifacts -name "safe" -exec strip '{}' \;
endif

build-container:
	rm -rf target/
	docker rmi -f maidsafe/safe-cli-build:build
	docker build -f Dockerfile.build -t maidsafe/safe-cli-build:build \
		--build-arg build_type="non-dev" .

build-dev-container:
	rm -rf target/
	docker rmi -f maidsafe/safe-cli-build:build-dev
	docker build -f Dockerfile.build -t maidsafe/safe-cli-build:build-dev \
		--build-arg build_type="dev" .

push-container:
	docker push maidsafe/safe-cli-build:build

push-dev-container:
	docker push maidsafe/safe-cli-build:build-dev

clippy:
ifeq ($(UNAME_S),Linux)
	docker run --name "safe-cli-build-${UUID}" -v "${PWD}":/usr/src/safe-cli:Z \
		-u ${USER_ID}:${GROUP_ID} \
		maidsafe/safe-cli-build:build \
		/bin/bash -c "cargo clippy --all-targets --all-features -- -D warnings"
else
	cargo clippy --all-targets --all-features -- -D warnings
endif

test:
ifndef SAFE_AUTH_PORT
	$(eval SAFE_AUTH_PORT := ${SAFE_AUTH_DEFAULT_PORT})
endif
	rm -rf artifacts
	mkdir artifacts
ifeq ($(UNAME_S),Linux)
	docker run --name "safe-cli-build-${UUID}" -v "${PWD}":/usr/src/safe-cli:Z \
		-u ${USER_ID}:${GROUP_ID} \
		maidsafe/safe-cli-build:build-dev \
		./resources/test-scripts/all-tests
	docker cp "safe-cli-build-${UUID}":/target .
	docker rm "safe-cli-build-${UUID}"
else
	$(eval MOCK_VAULT_PATH := ~/safe_auth-${SAFE_AUTH_PORT})
	RANDOM_PORT_NUMBER=${SAFE_AUTH_PORT} \
		SAFE_MOCK_VAULT_PATH=${MOCK_VAULT_PATH} ./resources/test-scripts/all-tests
endif
	find target/release -maxdepth 1 -type f -exec cp '{}' artifacts \;

package-build-artifacts:
ifndef SAFE_CLI_BRANCH
	@echo "A branch or PR reference must be provided."
	@echo "Please set SAFE_CLI_BRANCH to a valid branch or PR reference."
	@exit 1
endif
ifndef SAFE_CLI_BUILD_NUMBER
	@echo "A build number must be supplied for build artifact packaging."
	@echo "Please set SAFE_CLI_BUILD_NUMBER to a valid build number."
	@exit 1
endif
ifndef SAFE_CLI_BUILD_OS
	@echo "A value must be supplied for SAFE_CLI_BUILD_OS."
	@echo "Valid values are 'linux' or 'windows' or 'macos'."
	@exit 1
endif
ifndef SAFE_CLI_BUILD_TYPE
	@echo "A value must be supplied for SAFE_CLI_BUILD_TYPE."
	@echo "Valid values are 'dev' or 'non-dev'."
	@exit 1
endif
ifeq ($(SAFE_CLI_BUILD_TYPE),dev)
	$(eval ARCHIVE_NAME := ${SAFE_CLI_BRANCH}-${SAFE_CLI_BUILD_NUMBER}-safe-cli-${SAFE_CLI_BUILD_OS}-x86_64-${SAFE_CLI_BUILD_TYPE}.tar.gz)
else
	$(eval ARCHIVE_NAME := ${SAFE_CLI_BRANCH}-${SAFE_CLI_BUILD_NUMBER}-safe-cli-${SAFE_CLI_BUILD_OS}-x86_64.tar.gz)
endif
	tar -C artifacts -zcvf ${ARCHIVE_NAME} .
	rm artifacts/**
	mv ${ARCHIVE_NAME} artifacts

retrieve-all-build-artifacts:
ifndef SAFE_CLI_BRANCH
	@echo "A branch or PR reference must be provided."
	@echo "Please set SAFE_CLI_BRANCH to a valid branch or PR reference."
	@exit 1
endif
ifndef SAFE_CLI_BUILD_NUMBER
	@echo "A build number must be supplied for build artifact packaging."
	@echo "Please set SAFE_CLI_BUILD_NUMBER to a valid build number."
	@exit 1
endif
	rm -rf artifacts
	mkdir -p artifacts/linux/release
	mkdir -p artifacts/win/release
	mkdir -p artifacts/macos/release
	mkdir -p artifacts/linux/dev
	mkdir -p artifacts/win/dev
	mkdir -p artifacts/macos/dev
	aws s3 cp --no-sign-request --region eu-west-2 s3://${S3_BUCKET}/${SAFE_CLI_BRANCH}-${SAFE_CLI_BUILD_NUMBER}-safe-cli-linux-x86_64.tar.gz .
	aws s3 cp --no-sign-request --region eu-west-2 s3://${S3_BUCKET}/${SAFE_CLI_BRANCH}-${SAFE_CLI_BUILD_NUMBER}-safe-cli-windows-x86_64.tar.gz .
	aws s3 cp --no-sign-request --region eu-west-2 s3://${S3_BUCKET}/${SAFE_CLI_BRANCH}-${SAFE_CLI_BUILD_NUMBER}-safe-cli-macos-x86_64.tar.gz .
	aws s3 cp --no-sign-request --region eu-west-2 s3://${S3_BUCKET}/${SAFE_CLI_BRANCH}-${SAFE_CLI_BUILD_NUMBER}-safe-cli-linux-x86_64-dev.tar.gz .
	aws s3 cp --no-sign-request --region eu-west-2 s3://${S3_BUCKET}/${SAFE_CLI_BRANCH}-${SAFE_CLI_BUILD_NUMBER}-safe-cli-windows-x86_64-dev.tar.gz .
	aws s3 cp --no-sign-request --region eu-west-2 s3://${S3_BUCKET}/${SAFE_CLI_BRANCH}-${SAFE_CLI_BUILD_NUMBER}-safe-cli-macos-x86_64-dev.tar.gz .
	tar -C artifacts/linux/release -xvf ${SAFE_CLI_BRANCH}-${SAFE_CLI_BUILD_NUMBER}-safe-cli-linux-x86_64.tar.gz
	tar -C artifacts/win/release -xvf ${SAFE_CLI_BRANCH}-${SAFE_CLI_BUILD_NUMBER}-safe-cli-windows-x86_64.tar.gz
	tar -C artifacts/macos/release -xvf ${SAFE_CLI_BRANCH}-${SAFE_CLI_BUILD_NUMBER}-safe-cli-macos-x86_64.tar.gz
	tar -C artifacts/linux/dev -xvf ${SAFE_CLI_BRANCH}-${SAFE_CLI_BUILD_NUMBER}-safe-cli-linux-x86_64-dev.tar.gz
	tar -C artifacts/win/dev -xvf ${SAFE_CLI_BRANCH}-${SAFE_CLI_BUILD_NUMBER}-safe-cli-windows-x86_64-dev.tar.gz
	tar -C artifacts/macos/dev -xvf ${SAFE_CLI_BRANCH}-${SAFE_CLI_BUILD_NUMBER}-safe-cli-macos-x86_64-dev.tar.gz
	rm ${SAFE_CLI_BRANCH}-${SAFE_CLI_BUILD_NUMBER}-safe-cli-linux-x86_64.tar.gz
	rm ${SAFE_CLI_BRANCH}-${SAFE_CLI_BUILD_NUMBER}-safe-cli-windows-x86_64.tar.gz
	rm ${SAFE_CLI_BRANCH}-${SAFE_CLI_BUILD_NUMBER}-safe-cli-macos-x86_64.tar.gz
	rm ${SAFE_CLI_BRANCH}-${SAFE_CLI_BUILD_NUMBER}-safe-cli-linux-x86_64-dev.tar.gz
	rm ${SAFE_CLI_BRANCH}-${SAFE_CLI_BUILD_NUMBER}-safe-cli-windows-x86_64-dev.tar.gz
	rm ${SAFE_CLI_BRANCH}-${SAFE_CLI_BUILD_NUMBER}-safe-cli-macos-x86_64-dev.tar.gz

clean:
ifndef SAFE_AUTH_PORT
	$(eval SAFE_AUTH_PORT := ${SAFE_AUTH_DEFAULT_PORT})
endif
ifeq ($(OS),Windows_NT)
	powershell.exe -File resources\test-scripts\cleanup.ps1 -port ${SAFE_AUTH_PORT}
else ifeq ($(UNAME_S),Darwin)
	lsof -t -i tcp:${SAFE_AUTH_PORT} | xargs -n 1 -x kill
endif
	$(eval MOCK_VAULT_PATH := ~/safe_auth-${SAFE_AUTH_PORT})
	rm -rf ${MOCK_VAULT_PATH}

package-commit_hash-artifacts-for-deploy:
	rm -f *.zip
	rm -rf deploy
	mkdir -p deploy/dev
	mkdir -p deploy/release
	zip safe-cli-$$(git rev-parse --short HEAD)-x86_64-unknown-linux-gnu.zip artifacts/linux/release/safe
	zip safe-cli-$$(git rev-parse --short HEAD)-x86_64-pc-windows-gnu.zip artifacts/win/release/safe.exe
	zip safe-cli-$$(git rev-parse --short HEAD)-x86_64-apple-darwin.zip artifacts/macos/release/safe
	zip safe-cli-$$(git rev-parse --short HEAD)-x86_64-unknown-linux-gnu-dev.zip artifacts/linux/dev/safe
	zip safe-cli-$$(git rev-parse --short HEAD)-x86_64-pc-windows-gnu-dev.zip artifacts/win/dev/safe.exe
	zip safe-cli-$$(git rev-parse --short HEAD)-x86_64-apple-darwin-dev.zip artifacts/macos/dev/safe
	mv safe-cli-$$(git rev-parse --short HEAD)-x86_64-unknown-linux-gnu.zip deploy/release
	mv safe-cli-$$(git rev-parse --short HEAD)-x86_64-pc-windows-gnu.zip deploy/release
	mv safe-cli-$$(git rev-parse --short HEAD)-x86_64-apple-darwin.zip deploy/release
	mv safe-cli-$$(git rev-parse --short HEAD)-x86_64-unknown-linux-gnu-dev.zip deploy/dev
	mv safe-cli-$$(git rev-parse --short HEAD)-x86_64-pc-windows-gnu-dev.zip deploy/dev
	mv safe-cli-$$(git rev-parse --short HEAD)-x86_64-apple-darwin-dev.zip deploy/dev

package-version-artifacts-for-deploy:
	rm -rf deploy
	mkdir -p deploy/dev
	mkdir -p deploy/release
	( \
		cd deploy/release; \
		zip -j safe-cli-${SAFE_CLI_VERSION}-x86_64-unknown-linux-gnu.zip \
			../../artifacts/linux/release/safe; \
		zip -j safe-cli-${SAFE_CLI_VERSION}-x86_64-pc-windows-gnu.zip \
			../../artifacts/win/release/safe.exe; \
		zip -j safe-cli-${SAFE_CLI_VERSION}-x86_64-apple-darwin.zip \
			../../artifacts/macos/release/safe; \
		tar -C ../../artifacts/linux/release \
			-zcvf safe-cli-${SAFE_CLI_VERSION}-x86_64-unknown-linux-gnu.tar.gz safe; \
		tar -C ../../artifacts/win/release \
			-zcvf safe-cli-${SAFE_CLI_VERSION}-x86_64-pc-windows-gnu.tar.gz safe.exe; \
		tar -C ../../artifacts/macos/release \
			-zcvf safe-cli-${SAFE_CLI_VERSION}-x86_64-apple-darwin.tar.gz safe; \
	)
	( \
		cd deploy/dev; \
		zip -j safe-cli-${SAFE_CLI_VERSION}-x86_64-unknown-linux-gnu-dev.zip \
			../../artifacts/linux/dev/safe; \
		zip -j safe-cli-${SAFE_CLI_VERSION}-x86_64-pc-windows-gnu-dev.zip \
			../../artifacts/win/dev/safe.exe; \
		zip -j safe-cli-${SAFE_CLI_VERSION}-x86_64-apple-darwin-dev.zip \
			../../artifacts/macos/dev/safe; \
	)

deploy-github-release:
ifndef GITHUB_TOKEN
	@echo "Please set GITHUB_TOKEN to the API token for a user who can create releases."
	@exit 1
endif
	github-release release \
		--user ${GITHUB_REPO_OWNER} \
		--repo ${GITHUB_REPO_NAME} \
		--tag ${SAFE_CLI_VERSION} \
		--name "safe-cli" \
		--description "$$(./resources/get_release_description.sh ${SAFE_CLI_VERSION})";
	github-release upload \
		--user ${GITHUB_REPO_OWNER} \
		--repo ${GITHUB_REPO_NAME} \
		--tag ${SAFE_CLI_VERSION} \
		--name "safe-cli-${SAFE_CLI_VERSION}-x86_64-unknown-linux-gnu.zip" \
		--file deploy/release/safe-cli-${SAFE_CLI_VERSION}-x86_64-unknown-linux-gnu.zip;
	github-release upload \
		--user ${GITHUB_REPO_OWNER} \
		--repo ${GITHUB_REPO_NAME} \
		--tag ${SAFE_CLI_VERSION} \
		--name "safe-cli-${SAFE_CLI_VERSION}-x86_64-pc-windows-gnu.zip" \
		--file deploy/release/safe-cli-${SAFE_CLI_VERSION}-x86_64-pc-windows-gnu.zip;
	github-release upload \
		--user ${GITHUB_REPO_OWNER} \
		--repo ${GITHUB_REPO_NAME} \
		--tag ${SAFE_CLI_VERSION} \
		--name "safe-cli-${SAFE_CLI_VERSION}-x86_64-apple-darwin.zip" \
		--file deploy/release/safe-cli-${SAFE_CLI_VERSION}-x86_64-apple-darwin.zip;
	github-release upload \
		--user ${GITHUB_REPO_OWNER} \
		--repo ${GITHUB_REPO_NAME} \
		--tag ${SAFE_CLI_VERSION} \
		--name "safe-cli-${SAFE_CLI_VERSION}-x86_64-unknown-linux-gnu.tar.gz" \
		--file deploy/release/safe-cli-${SAFE_CLI_VERSION}-x86_64-unknown-linux-gnu.tar.gz;
	github-release upload \
		--user ${GITHUB_REPO_OWNER} \
		--repo ${GITHUB_REPO_NAME} \
		--tag ${SAFE_CLI_VERSION} \
		--name "safe-cli-${SAFE_CLI_VERSION}-x86_64-pc-windows-gnu.tar.gz" \
		--file deploy/release/safe-cli-${SAFE_CLI_VERSION}-x86_64-pc-windows-gnu.tar.gz;
	github-release upload \
		--user ${GITHUB_REPO_OWNER} \
		--repo ${GITHUB_REPO_NAME} \
		--tag ${SAFE_CLI_VERSION} \
		--name "safe-cli-${SAFE_CLI_VERSION}-x86_64-apple-darwin.tar.gz" \
		--file deploy/release/safe-cli-${SAFE_CLI_VERSION}-x86_64-apple-darwin.tar.gz;
	github-release upload \
		--user ${GITHUB_REPO_OWNER} \
		--repo ${GITHUB_REPO_NAME} \
		--tag ${SAFE_CLI_VERSION} \
		--name "safe_completion.sh" \
		--file resources/safe_completion.sh

retrieve-cache:
ifndef SAFE_CLI_BRANCH
	@echo "A branch reference must be provided."
	@echo "Please set SAFE_CLI_BRANCH to a valid branch reference."
	@exit 1
endif
ifndef SAFE_CLI_OS
	@echo "The OS for the cache must be specified."
	@echo "Please set SAFE_CLI_OS to either 'macos' or 'windows'."
	@exit 1
endif
	aws s3 cp \
		--no-sign-request \
		--region eu-west-2 \
		s3://${S3_BUCKET}/safe_cli-${SAFE_CLI_BRANCH}-${SAFE_CLI_OS}-cache.tar.gz .
	mkdir target
	tar -C target -xvf safe_cli-${SAFE_CLI_BRANCH}-${SAFE_CLI_OS}-cache.tar.gz
	rm safe_cli-${SAFE_CLI_BRANCH}-${SAFE_CLI_OS}-cache.tar.gz
