.PHONY: project build test run icon clean

project: ## Generate CodeFactory.xcodeproj (requires xcodegen)
	xcodegen generate

build: project ## Build a Debug app into build/DerivedData
	xcodebuild -project CodeFactory.xcodeproj -scheme CodeFactory -configuration Debug \
		-derivedDataPath build/DerivedData build

release: project ## Build a Release app
	xcodebuild -project CodeFactory.xcodeproj -scheme CodeFactory -configuration Release \
		-derivedDataPath build/DerivedData build

test: ## Run the CodeFactoryKit unit tests
	cd Packages/CodeFactoryKit && swift test

run: build ## Build and launch
	open "build/DerivedData/Build/Products/Debug/Ultra Code Factory.app"

icon: ## Regenerate the app icon sizes from Scripts/icon-artwork.png
	swift Scripts/mask-icon.swift Scripts/icon-artwork.png App/CodeFactory/Resources/Assets.xcassets/AppIcon.appiconset

clean:
	rm -rf build CodeFactory.xcodeproj Packages/CodeFactoryKit/.build
