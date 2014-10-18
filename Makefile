BUILD_DIR=build
PROJECT=Vienna.xcodeproj
WORKSPACE=Vienna.xcworkspace
SCHEME=Vienna
TARGET=Vienna

default:
	xcodebuild -project $(PROJECT) -target "Archive and Prep for Upload" -configuration Deployment

release:
	xcodebuild -project $(PROJECT) -target "Archive and Prep for Upload" -configuration Deployment

development:
	xcodebuild -workspace $(WORKSPACE) -scheme $(SCHEME) -configuration Development

clean:
	xcodebuild -workspace $(WORKSPACE) -scheme $(SCHEME) -configuration Development clean
	xcodebuild -workspace $(WORKSPACE) -scheme $(SCHEME) -configuration Deployment clean
	rm -fr build
