.PHONY: generate build run release clean reset-permissions

PROJECT_NAME = MyScreen
TEAM_ID = 4S269D79GZ
SIGN_FLAGS = CODE_SIGN_IDENTITY="Apple Development" DEVELOPMENT_TEAM=$(TEAM_ID)

generate:
	xcodegen generate

build: generate
	xcodebuild -project $(PROJECT_NAME).xcodeproj -scheme $(PROJECT_NAME) -configuration Debug build $(SIGN_FLAGS)

run: generate
	xcodebuild -project $(PROJECT_NAME).xcodeproj -scheme $(PROJECT_NAME) -configuration Debug build $(SIGN_FLAGS) && \
	open build/Debug/$(PROJECT_NAME).app

release: generate
	xcodebuild -project $(PROJECT_NAME).xcodeproj -scheme $(PROJECT_NAME) -configuration Release build $(SIGN_FLAGS) \
		SWIFT_OPTIMIZATION_LEVEL=-O \
		GCC_OPTIMIZATION_LEVEL=s \
		SWIFT_COMPILATION_MODE=wholemodule
	@echo ""
	@echo "Release build at: build/Release/$(PROJECT_NAME).app"

reset-permissions:
	tccutil reset Accessibility com.myscreen.app
	@echo "Accessibility permission reset. Re-launch the app to trigger the authorization prompt."

clean:
	rm -rf build/Debug build/Release build/MyScreen.build DerivedData $(PROJECT_NAME).xcodeproj
