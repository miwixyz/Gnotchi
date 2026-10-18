.PHONY: docs gen lock build test lint hooks dev install release release-dry-run clean

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

# MIT Signatur (wie Kalli/Seam): Der Test-Host ist die App selbst. Ad hoc signiert
# entstünde eine zweite Identität für dev.mwlr.gnotchi in den Datenschutz-Einstellungen
# (Automation). Gnotchi startet im Testlauf weder Sparkle noch den Adapter
# (siehe GnotchiApp.isRunningTests).
test: gen
	xcodebuild -project $(APP).xcodeproj -scheme $(APP) \
		-destination 'platform=macOS' \
		-derivedDataPath $(DERIVED) \
		-onlyUsePackageVersionsFromResolvedFile -allowProvisioningUpdates test

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
