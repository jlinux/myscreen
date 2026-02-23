.PHONY: generate build run clean

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

clean:
	rm -rf build DerivedData $(PROJECT_NAME).xcodeproj
