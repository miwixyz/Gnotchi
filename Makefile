.PHONY: docs gen lock build test render lint hooks dev install profile release release-dry-run clean

APP = Gnotchi
CONFIG ?= Debug
DERIVED = build

# CHANGELOG lebt im Repo-Wurzelverzeichnis und wird bei jedem Build ins Bundle
# gespiegelt (Kalli-Muster): Die App kann nie eine ältere Fassung anzeigen.
docs:
	cp CHANGELOG.md Gnotchi/Resources/CHANGELOG.md

# Lockfile lebt im Repo, das Projekt ist generiert (gitignoriert). Ohne Einspielen
# wäre Sparkles Commit-SHA nicht versioniert (Kalli-Muster).
SPM_DIR = $(APP).xcodeproj/project.xcworkspace/xcshareddata/swiftpm

gen: docs
	xcodegen generate
	@mkdir -p "$(SPM_DIR)"
	@cp Package.resolved "$(SPM_DIR)/Package.resolved"

# Nach einem bewussten Abhängigkeits-Update: Lockfile zurückschreiben.
lock:
	@cp "$(SPM_DIR)/Package.resolved" Package.resolved
	@git diff --stat Package.resolved

build: gen
	xcodebuild -project $(APP).xcodeproj -scheme $(APP) \
		-configuration $(CONFIG) -derivedDataPath $(DERIVED) \
		-onlyUsePackageVersionsFromResolvedFile CODE_SIGNING_ALLOWED=NO build

# OHNE Host-App (ab 2026-10-29, Kalli-Muster): Die App-Quellen werden direkt ins Testbündel
# kompiliert (project.yml), die Tests laufen im `xctest`-Agenten. Es startet keine zweite Gnotchi,
# also gibt es keine zweite Identität für dev.mwlr.gnotchi in den Datenschutz-Einstellungen und
# keinen Grund mehr für die Developer-ID-Signatur, die bis 0.18.2 hier stand. Legt ein Test
# AppModel an, startet es weder Sparkle noch den Adapter (AppModel.isRunningTests).
test: gen
	xcodebuild -project $(APP).xcodeproj -scheme $(APP)Tests \
		-destination 'platform=macOS' \
		-derivedDataPath $(DERIVED) \
		-onlyUsePackageVersionsFromResolvedFile CODE_SIGNING_ALLOWED=NO test

# Nur die Insel-Bilder (IslandViewRenderTests) nach build/render/ – ohne App-Start, für die Sichtprüfung
# nach jeder Änderung an der Insel. Vorher von Hand mit TEST_RUNNER_GNOTCHI_RENDER_DIR (20.10.: viermal
# an einem Tag). Alte Bilder fliegen vorher raus; ohne neues Bild bricht das Ziel ab (kein stilles „fertig“).
RENDER_DIR = $(CURDIR)/build/render
render: gen
	@mkdir -p "$(RENDER_DIR)"
	@find "$(RENDER_DIR)" -name 'gnotchi-island-*.png' -delete
	@TEST_RUNNER_GNOTCHI_RENDER_DIR="$(RENDER_DIR)" xcodebuild -project $(APP).xcodeproj -scheme $(APP)Tests \
		-destination 'platform=macOS' -derivedDataPath $(DERIVED) \
		-onlyUsePackageVersionsFromResolvedFile CODE_SIGNING_ALLOWED=NO \
		test -only-testing:GnotchiTests/IslandViewRenderTests 2>&1 | grep -E '^xcodebuild: error:|\.swift:[0-9]+:[0-9]+: error:|\*\* TEST' || true
	@n=$$(find "$(RENDER_DIR)" -name 'gnotchi-island-*.png' | wc -l | tr -d ' '); \
	if [ "$$n" -eq 0 ]; then echo "✗ keine Bilder in $(RENDER_DIR) – Testausgabe oben prüfen"; exit 1; fi; \
	echo "✓ $$n Bilder in $(RENDER_DIR):"; ls "$(RENDER_DIR)" | sed 's/^/  /'

# Datenschutz-Gate zuerst (docs/SECURE-DESIGN.md G16): keine echten Hördaten im Repo.
lint:
	@sh scripts/privacy-gate.sh
	@command -v swiftlint >/dev/null || { echo "swiftlint fehlt -> brew install swiftlint"; exit 1; }
	swiftlint lint --quiet --strict

# Einmal je Klon: Git-Hooks aus .githooks/ benutzen (Datenschutz-Gate vor jedem Commit).
hooks:
	git config core.hooksPath .githooks
	@echo "✓ core.hooksPath = $$(git config core.hooksPath)"

# Testversion: bauen, mit Developer ID signierte KOPIE unter /tmp starten.
# Developer ID, damit die Signaturprüfung vor dem Adapter-Start (G2) besteht und
# die Automation-Freigabe über Builds hinweg hält.
dev:
	@bash scripts/dev-signed.sh

# Einmal je Mac (ab 0.11.0, G38): Xcode legt beim Developer-ID-Export das Profil
# „Mac Team Direct Provisioning Profile: dev.mwlr.gnotchi“ an. dev/install betten es danach ein
# (scripts/profile.sh). Archiv und Export landen im gitignorierten build-profile/ und werden nicht benutzt.
profile: gen
	@mkdir -p build-profile
	xcodebuild -project $(APP).xcodeproj -scheme $(APP) -configuration Release \
		-derivedDataPath build-profile -archivePath build-profile/$(APP).xcarchive \
		-onlyUsePackageVersionsFromResolvedFile -allowProvisioningUpdates archive >build-profile/archive.log 2>&1 \
		|| { grep -E 'error:' build-profile/archive.log | sort -u | head -8; exit 1; }
	xcodebuild -exportArchive -archivePath build-profile/$(APP).xcarchive -exportPath build-profile/export \
		-exportOptionsPlist scripts/exportOptions-developer-id.plist -allowProvisioningUpdates >build-profile/export.log 2>&1 \
		|| { grep -E 'error' build-profile/export.log | sort -u | head -8; exit 1; }
	@. scripts/profile.sh && p=$$(gnotchi_profile_path) && echo "✓ Profil: $$p"

# lint zuerst: Ein Release mit Linter-Verstoß geht gar nicht erst los.
release: lint
	@bash scripts/release.sh

release-dry-run:
	@echo "VERSION:      $$(awk -F'\"' '/MARKETING_VERSION:/ { print $$2; exit }' project.yml)"
	@printf "DEVELOPER_ID: "; security find-identity -v -p codesigning | awk -F'\"' '/Developer ID Application/ { print $$2; exit }'
	@[ -z "$$(git status --porcelain)" ] && echo "Arbeitsbaum:  sauber" || echo "Arbeitsbaum:  NICHT sauber"

clean:
	rm -rf $(DERIVED) $(APP).xcodeproj

# Testfassung lokal: signiert nach /Applications, Build-Nummer wie ein Release. Ohne Doku-Gate.
install:
	@sh scripts/install-signed.sh
