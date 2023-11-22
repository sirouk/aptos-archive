SHELL=/usr/bin/env bash

ifndef GIT_ORG
GIT_ORG = sirouk
endif

ifndef GIT_REPO
GIT_REPO = aptos-archive
endif

ifndef GIT_BATCH_SIZE
GIT_BATCH_SIZE = 20
endif

ifndef BIN_PATH
BIN_PATH=/root/.cargo/bin
endif

ifndef SOURCE_PATH
SOURCE_PATH=~/aptos-core
endif

ifndef REPO_PATH
REPO_PATH=~/${GIT_REPO}
endif

ifndef ARCHIVE_PATH
ARCHIVE_PATH=${REPO_PATH}/snapshots
endif

ifndef GENESIS_PATH
GENESIS_PATH=/mnt/md*/previewnet2/genesis
endif

ifndef DATA_PATH
DATA_PATH=/mnt/md*/previewnet2/data
endif

ifndef DB_PATH
DB_PATH=${DATA_PATH}/db
endif

ifndef BACKUP_SERVICE_URL
BACKUP_SERVICE_URL=http://localhost
endif

ifndef BACKUP_EPOCH_FREQ
BACKUP_EPOCH_FREQ = 1
endif

ifndef BACKUP_TRANS_FREQ
BACKUP_TRANS_FREQ = 1000000
endif

ifndef VERSION
VERSION = 0
endif

ifndef VERSION_START
VERSION_START = ${BACKUP_TRANS_FREQ}
endif



install: backup-genesis
	cd ${SOURCE_PATH} && cargo build -p aptos-debugger --profile performance
	sudo cp -f ${SOURCE_PATH}/target/performance/aptos-debugger ${BIN_PATH}/aptos-debugger

wipe-backups:
	cd ${REPO_PATH} && rm -rf ${ARCHIVE_PATH} && rm -rf ${REPO_PATH}/genesis && rm -rf metacache backup.log && git add -A && git commit -m "wipe-backups" && git push

wipe-db:
	sudo rm -rf ${DB_PATH} && sudo rm -rf ${DATA_PATH}/secure-data.json

prep-archive-path:
	mkdir -p ${ARCHIVE_PATH} && cd ${ARCHIVE_PATH}

sync-repo:
	cd ${REPO_PATH} && git pull && git reset --hard origin/main && git clean -xdf


backup-genesis:
	mkdir -p ${REPO_PATH}/genesis
	cp -f ${GENESIS_PATH}/genesis.blob ${REPO_PATH}/genesis/genesis.blob
	cp -f ${GENESIS_PATH}/waypoint.txt ${REPO_PATH}/genesis/waypoint.txt
	cd ${REPO_PATH}
	git add ${REPO_PATH}/genesis/genesis.blob
	git add ${REPO_PATH}/genesis/waypoint.txt
	git commit -m "commit genesis"
	git push

backup-continuous: prep-archive-path 
	cd ${ARCHIVE_PATH} && ${BIN_PATH}/aptos-debugger aptos-db backup continuously --backup-service-address ${BACKUP_SERVICE_URL}:6186 --state-snapshot-interval-epochs ${BACKUP_EPOCH_FREQ} --transaction-batch-size ${BACKUP_TRANS_FREQ} --command-adapter-config ${REPO_PATH}/epoch-archive.yaml

backup-epoch: prep-archive-path
	cd ${ARCHIVE_PATH} && ${BIN_PATH}/aptos-debugger aptos-db backup oneoff --backup-service-address ${BACKUP_SERVICE_URL}:6186 epoch-ending --start-epoch ${LAST_EPOCH} --end-epoch ${EPOCH_NOW} --target-db-dir ${DB_PATH} --command-adapter-config ${REPO_PATH}/epoch-archive.yaml

backup-snapshot: prep-archive-path
	cd ${ARCHIVE_PATH} && ${BIN_PATH}/aptos-debugger aptos-db backup oneoff --backup-service-address ${BACKUP_SERVICE_URL}:6186 state-snapshot --target-db-dir ${DB_PATH} --command-adapter-config ${REPO_PATH}/epoch-archive.yaml

backup-transaction: prep-archive-path
	cd ${ARCHIVE_PATH} && ${BIN_PATH}/aptos-debugger aptos-db backup oneoff --backup-service-address ${BACKUP_SERVICE_URL}:6186 transaction --start-version ${VERSION} --num_transactions ${BACKUP_TRANS_FREQ} --target-db-dir ${DB_PATH}--command-adapter-config ${REPO_PATH}/epoch-archive.yaml

backup-version: backup-epoch backup-snapshot backup-transaction


restore-genesis:
	mkdir -p ${GENESIS_PATH} && cp -f ${REPO_PATH}/genesis/genesis.blob ${GENESIS_PATH}/genesis.blob && cp -f ${REPO_PATH}/genesis/waypoint.txt ${GENESIS_PATH}/waypoint.txt

restore-all: sync-repo wipe-db restore-genesis
	cd ${ARCHIVE_PATH} && ${BIN_PATH}/aptos-debugger aptos-db restore bootstrap-db --target-db-dir ${DB_PATH} --metadata-cache-dir ${REPO_PATH}/metacache --command-adapter-config ${REPO_PATH}/epoch-archive.yaml

restore-latest: sync-repo wipe-db
	cd ${ARCHIVE_PATH} && ${BIN_PATH}/aptos-debugger aptos-db restore bootstrap-db --enable-storage-sharding --ledger-history-start-version ${VERSION_START} --target-version ${VERSION} --target-db-dir ${DB_PATH} --metadata-cache-dir ${REPO_PATH}/metacache --command-adapter-config ${REPO_PATH}/epoch-archive.yaml

restore-not-yet:
	echo "Not now, but soon. You can play, but be careful!"

restore-epoch: restore-not-yet
	cd ${ARCHIVE_PATH} && ${BIN_PATH}/aptos-debugger aptos-db restore oneoff epoch-ending

restore-transaction: restore-not-yet
	cd ${ARCHIVE_PATH} && ${BIN_PATH}/aptos-debugger aptos-db restore oneoff transaction

restore-snapshot: restore-not-yet
	echo "Hint: --restore-mode [default, kv_only, tree_only]"
	cd ${ARCHIVE_PATH} && ${BIN_PATH}/aptos-debugger aptos-db restore oneoff state-snapshot 


git-setup:
	@if [ ! -d ${REPO_PATH} ]; then \
		mkdir -p ${REPO_PATH} && cd ${REPO_PATH} && git clone https://github.com/${GIT_ORG}/${GIT_REPO} .; \
	elif [ -d ${REPO_PATH}/.git ]; then \
		cd ${REPO_PATH}; \
	else \
		echo "Directory exists but is not a git repository. Please handle manually."; \
	fi

git-pull:
	@cd ${REPO_PATH}; \
	git pull;

git: git-setup git-pull git-sling-all

git-sling-all:
	@cd ${ARCHIVE_PATH}; \
	paths=$$(git status --porcelain */* | grep '^??' | awk '{print $$2}' | xargs -I {} stat --format="%Y %n" ${REPO_PATH}/{} | sort -n | awk '{print $$2}'); \
	cd ${REPO_PATH}; \
	counter=0; \
	for path in $$paths; do \
		if [ -f "$$path" ]; then \
			git add "$$path"; \
			counter=$$((counter + 1)); \
		fi; \
		if [ $$counter -eq ${GIT_BATCH_SIZE} ]; then \
			git commit -m "batch backup continuously"; \
			git push; \
			counter=0; \
		fi; \
	done; \

start-continuous:
	@cd ${REPO_PATH}; \
	ps aux | grep "aptos-debugger aptos-db backup continuously" | grep -v "grep" > /dev/null; \
	ps_exit_status=$$?; \
	if [ $$ps_exit_status -ne 0 ]; then \
		echo "Starting Continuous Backup via aptos-debugger aptos-db..."; \
		cd ${REPO_PATH} && make backup-continuous >> ${REPO_PATH}/backup.log 2>&1 & \
	else \
		echo "aptos-debugger aptos-db is already running"; \
	fi

stop-continuous:
	@cd ${REPO_PATH}; \
	ps aux | grep "aptos-debugger aptos-db backup continuously" | grep -v "grep" > /dev/null; \
	ps_exit_status=$$?; \
	if [ $$ps_exit_status -ne 0 ]; then \
		echo "Stopping Continuous Backup via aptos-debugger aptos-db..."; \
		pkill -f "aptos-debugger aptos-db backup continuously"; \
	else \
		echo "aptos-debugger aptos-db is not running"; \
	fi

log-cleanup:
	echo "This is where we will eventually deal with the size of backup.log!"

cron: start-continuous git log-cleanup
