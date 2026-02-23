.PHONY: generate build run clean

PROJECT_NAME = MyScreen

generate:
	xcodegen generate

build: generate
	xcodebuild -project $(PROJECT_NAME).xcodeproj -scheme $(PROJECT_NAME) -configuration Debug build

run: generate
	xcodebuild -project $(PROJECT_NAME).xcodeproj -scheme $(PROJECT_NAME) -configuration Debug build && \
	open build/Debug/$(PROJECT_NAME).app

clean:
	rm -rf build DerivedData $(PROJECT_NAME).xcodeproj
